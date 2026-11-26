"""cdp_client.py — live web-preview inspection for the agentic loop.

The launcher's Qt WebEngine runs with --remote-debugging-port=9222 (loopback
only, see shell.qml), so the agent can drive the SAME page the user sees in
the canvas web-preview pane: evaluate JS in the preview frame's execution
context, read its console, click/type through DOM calls and grab screenshots.

The preview iframe is cross-origin (credentialless, to satisfy the loopback
server's COEP require-corp), so parent-page JS cannot reach it — CDP can.
Same-site previews (127.0.0.1:<dev-port>) share the agent-app renderer and
appear as extra execution contexts; cross-site previews become their own
debug target. Both cases are resolved here.

Stdlib-only WebSocket client on purpose: the runtime venv bootstrap installs
a fixed dep set, and a hand-rolled client keeps ISO/venv parity untouched.
"""
import base64
import json
import os
import queue
import socket
import struct
import threading
import time
import urllib.request

CDP_PORT = int(os.environ.get("HC_CDP_PORT", "9222"))
APP_ORIGIN = "http://127.0.0.1:17842"


class CDPUnavailable(RuntimeError):
    pass


def _http_json(path: str):
    with urllib.request.urlopen(f"http://127.0.0.1:{CDP_PORT}{path}", timeout=3) as r:
        return json.load(r)


class _WS:
    """Minimal RFC6455 client: text frames, masked sends, ping/pong, fragments."""

    def __init__(self, host: str, port: int, path: str):
        self.s = socket.create_connection((host, port), timeout=10)
        key = base64.b64encode(os.urandom(16)).decode()
        self.s.sendall((
            f"GET {path} HTTP/1.1\r\nHost: {host}:{port}\r\n"
            "Upgrade: websocket\r\nConnection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
        ).encode())
        resp = b""
        while b"\r\n\r\n" not in resp:
            chunk = self.s.recv(4096)
            if not chunk:
                raise CDPUnavailable("debug port closed the handshake")
            resp += chunk
        if b"101" not in resp.split(b"\r\n")[0]:
            raise CDPUnavailable("debug port refused the WebSocket upgrade")
        self.buf = b""

    def _read(self, n: int) -> bytes:
        while len(self.buf) < n:
            chunk = self.s.recv(65536)
            if not chunk:
                raise EOFError
            self.buf += chunk
        out, self.buf = self.buf[:n], self.buf[n:]
        return out

    def send(self, obj: dict):
        payload = json.dumps(obj).encode()
        mask = os.urandom(4)
        n = len(payload)
        header = bytes([0x81])
        if n < 126:
            header += bytes([0x80 | n])
        elif n < 65536:
            header += bytes([0x80 | 126]) + struct.pack(">H", n)
        else:
            header += bytes([0x80 | 127]) + struct.pack(">Q", n)
        self.s.sendall(header + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))

    def recv(self) -> dict:
        msg = b""
        while True:
            b1, b2 = self._read(2)
            fin, op = b1 & 0x80, b1 & 0x0F
            n = b2 & 0x7F
            if n == 126:
                n = struct.unpack(">H", self._read(2))[0]
            elif n == 127:
                n = struct.unpack(">Q", self._read(8))[0]
            data = self._read(n)
            if op == 9:  # ping -> pong
                self.s.sendall(bytes([0x8A, 0x80]) + os.urandom(4))
                continue
            if op == 8:
                raise EOFError
            msg += data
            if fin:
                return json.loads(msg.decode())

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


class _Session:
    """One debug target: reader thread buffers events, call() matches ids."""

    def __init__(self, ws_url: str):
        rest = ws_url.split("://", 1)[1]
        hostport, path = rest.split("/", 1)
        host, port = hostport.split(":")
        self.ws = _WS(host, int(port), "/" + path)
        self.inbox: queue.Queue = queue.Queue()
        self.dead = False
        self.console: list = []
        self.contexts: dict = {}   # frameId -> executionContextId
        self.frames: dict = {}     # frameId -> url
        self._id = 0
        self._lock = threading.Lock()
        threading.Thread(target=self._reader, daemon=True).start()
        self.call("Runtime.enable")
        self.call("Page.enable")
        self.call("Log.enable")
        tree = self.call("Page.getFrameTree").get("result", {}).get("frameTree", {})
        self._walk_frames(tree)

    def _walk_frames(self, node: dict):
        frame = node.get("frame", {})
        if frame.get("id"):
            self.frames[frame["id"]] = frame.get("url", "")
        for child in node.get("childFrames", []) or []:
            self._walk_frames(child)

    def _reader(self):
        try:
            while True:
                self.inbox.put(self.ws.recv())
        except (EOFError, OSError, ValueError):
            self.dead = True
            self.inbox.put({"__dead__": True})

    def _event(self, m: dict):
        method = m.get("method")
        p = m.get("params", {})
        if method == "Runtime.executionContextCreated":
            ctx = p.get("context", {})
            aux = ctx.get("auxData", {})
            self.contexts[aux.get("frameId", "")] = ctx.get("id")
        elif method == "Runtime.executionContextDestroyed":
            cid = p.get("executionContextId")
            for fid, c in list(self.contexts.items()):
                if c == cid:
                    del self.contexts[fid]
        elif method == "Page.frameNavigated":
            frame = p.get("frame", {})
            if frame.get("id"):
                self.frames[frame["id"]] = frame.get("url", "")
        elif method == "Runtime.consoleAPICalled":
            args = p.get("args", [])
            text = " ".join(str(a.get("value", a.get("description", ""))) for a in args)
            self._log(p.get("type", "log"), text)
        elif method == "Runtime.exceptionThrown":
            det = p.get("exceptionDetails", {})
            self._log("error", det.get("text", "") + " " + json.dumps(det.get("exception", {}))[:200])
        elif method == "Log.entryAdded":
            e = p.get("entry", {})
            self._log(e.get("level", "log"), e.get("text", ""))

    def _log(self, level: str, text: str):
        self.console.append({"ts": time.time(), "level": level, "text": text[:1000]})
        del self.console[:-300]

    def call(self, method: str, timeout: float = 15.0, **params) -> dict:
        with self._lock:
            if self.dead:
                raise CDPUnavailable("debug session died (page closed?)")
            self._id += 1
            mid = self._id
            self.ws.send({"id": mid, "method": method, "params": params})
            deadline = time.time() + timeout
            while True:
                left = deadline - time.time()
                if left <= 0:
                    raise CDPUnavailable(f"{method} timed out")
                try:
                    m = self.inbox.get(timeout=left)
                except queue.Empty:
                    raise CDPUnavailable(f"{method} timed out")
                if m.get("__dead__"):
                    raise CDPUnavailable("debug session died (page closed?)")
                if m.get("id") == mid:
                    return m
                self._event(m)


_sessions: dict = {}   # targetId -> _Session


def _session_for(url: str):
    """Resolve the debug session + execution context showing `url`."""
    try:
        targets = _http_json("/json/list")
    except (OSError, ValueError) as e:
        raise CDPUnavailable(
            f"Qt WebEngine remote debugging port {CDP_PORT} not reachable ({e}). "
            "The launcher shell must be running with --remote-debugging-port=9222 "
            "(shell.qml ships it); restart the shell after updating dotfiles."
        )
    norm = url.rstrip("/")
    # Cross-site previews are OOPIFs: their own debug target.
    own = next((t for t in targets if t.get("type") == "page"
                and t.get("url", "").rstrip("/").startswith(norm)
                and not t.get("url", "").startswith(APP_ORIGIN)), None)
    app = next((t for t in targets if t.get("type") == "page"
                and t.get("url", "").startswith(APP_ORIGIN)), None)
    target = own or app
    if not target:
        raise CDPUnavailable("no launcher agent-app page found on the debug port")
    sess = _sessions.get(target["id"])
    if sess is None or sess.dead:
        sess = _Session(target["webSocketDebuggerUrl"])
        _sessions[target["id"]] = sess
    if own:
        return sess, None  # default context of the preview's own target
    # Same-site preview: an iframe execution context inside the app renderer.
    fid = next((fid for fid, furl in sess.frames.items()
                if furl.rstrip("/").startswith(norm)), None)
    if fid is None:
        raise CDPUnavailable(f"no frame showing {url} — open the web preview first")
    ctx = sess.contexts.get(fid)
    if ctx is None:
        raise CDPUnavailable(f"frame for {url} has no live execution context yet")
    return sess, ctx


def available() -> bool:
    try:
        _http_json("/json/version")
        return True
    except (OSError, ValueError):
        return False


def evaluate(url: str, js: str) -> dict:
    sess, ctx = _session_for(url)
    params = {"expression": js, "returnByValue": True, "awaitPromise": True}
    if ctx is not None:
        params["contextId"] = ctx
    r = sess.call("Runtime.evaluate", **params).get("result", {})
    if r.get("exceptionDetails"):
        det = r["exceptionDetails"]
        return {"ok": False, "error": det.get("text", "exception") + " " +
                str(det.get("exception", {}).get("description", ""))[:500]}
    return {"ok": True, "value": r.get("result", {}).get("value")}


_SNAPSHOT_JS = """(() => {
  const pick = el => ({
    tag: el.tagName.toLowerCase(),
    id: el.id || undefined,
    text: (el.innerText || el.value || el.getAttribute('aria-label') || '').trim().slice(0, 60),
    href: el.getAttribute('href') || undefined,
  });
  return {
    title: document.title,
    url: location.href,
    text: (document.body ? document.body.innerText : '').slice(0, 6000),
    interactive: Array.from(document.querySelectorAll(
      'a,button,input,select,textarea,[role="button"]')).slice(0, 80).map(pick),
  };
})()"""


def snapshot(url: str) -> dict:
    return evaluate(url, _SNAPSHOT_JS)


def console_entries(url: str, clear: bool = False) -> list:
    sess, _ = _session_for(url)
    entries = list(sess.console)
    if clear:
        sess.console.clear()
    return entries


def screenshot(url: str, path: str) -> str:
    sess, _ = _session_for(url)
    r = sess.call("Page.captureScreenshot", format="png").get("result", {})
    data = r.get("data")
    if not data:
        raise CDPUnavailable("captureScreenshot returned no image")
    with open(path, "wb") as f:
        f.write(base64.b64decode(data))
    return path