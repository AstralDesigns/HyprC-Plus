#!/usr/bin/env python3
# ═══════════════════════════════════════════════════════════════════════════
#  agent_loopback_server.py — Quickshell port of the GJS launcher's
#  createAgentLoopbackServer() + agent bridge (app-launcher.js). Serves the
#  built agent-app (Vite/React) bundle over a private loopback origin so the
#  launcher's own-session WebEngineView can host it like a browser tab, and
#  re-implements the WebKit "host" half of the agent bridge in plain HTTP so
#  QtWebEngine (which has no window.webkit.messageHandlers) can use it.
#
#  Mirrors the GJS libsoup server contract:
#    • COOP/COEP/CORP headers on every response (SharedArrayBuffer /
#      pthread-enabled wllama WASM builds require a cross-origin-isolated
#      context).
#    • /_media_file/<abs-path> range-streaming route (local images/audio/video).
#    • Vite SPA fallback to index.html for extension-less routes; real asset
#      misses stay 404 so diagnostics aren't masked.
#    • Traversal rejection before joining paths.
#
#  Bridge contract (identical to the React app's WebKit build):
#    app → host : window.webkit.messageHandlers.agent.postMessage(JSON)
#    host → app : window.__hyprcandy_agent_dispatch(obj)
#  QtWebEngine cannot provide the WebKit handler, so index.html is served
#  with a small document-start shim that reroutes postMessage to POST
#  /bridge and feeds the JSON reply back through __hyprcandy_agent_dispatch.
#  All privileged work (secrets, runtime proxy, theming) happens here — the
#  React app never talks to :17900 directly, which would break COEP.
#
#  Safe to spawn more than once: if the port is already bound (e.g. a warm
#  instance or the GJS launcher), this exits quietly instead of crashing.
#
#  Env:
#    HC_AGENT_DIST   dist root (default: ~/.hyprcandy/.../agent-app/dist)
#    HC_AGENT_PORT   loopback port (default: 17842)
#    HC_RUNTIME_URL  Python runtime base (default: http://127.0.0.1:17900)
# ═══════════════════════════════════════════════════════════════════════════
import os
import re
import sys
import json
import subprocess
import mimetypes
import datetime as _dt
import urllib.request
import urllib.error
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, quote


def _shq(s):
    # POSIX single-quote escaping (GLib.shell_quote parity) for exec_command cwd.
    return "'" + str(s).replace("'", "'\\''") + "'"

HOME = os.path.expanduser("~")
DIST = os.path.expanduser(os.environ.get(
    "HC_AGENT_DIST", "~/.hyprcandy/GJS/hyprcandydock/agent-app/dist"))
HOST = "127.0.0.1"
PORT = int(os.environ.get("HC_AGENT_PORT", "17842"))
RUNTIME_URL = os.environ.get("HC_RUNTIME_URL", "http://127.0.0.1:17900")
DEFAULT_PROJECT_ROOT = os.path.join(
    HOME, ".hyprcandy", "GJS", "hyprcandydock")
COLORS_CSS = os.path.join(HOME, ".config", "gtk-4.0", "colors.css")
# libsecret attributes the GJS launcher writes keys under. We don't pass
# xdg:schema on lookup so items stored by either side are found.
SECRET_SCHEMA = "org.hyprcandy.LauncherCredentials"
SECRET_DEFAULT_SERVICE = "hyprcandy_byok"

mimetypes.add_type("application/wasm", ".wasm")
mimetypes.add_type("text/javascript", ".js")
mimetypes.add_type("text/javascript", ".mjs")
mimetypes.add_type("application/manifest+json", ".webmanifest")

# ── Document-start bridge shim (injected before the React bundle) ──────────
BRIDGE_SHIM = """<script>
(function () {
  "use strict";
  function dispatch(obj) {
    if (typeof window.__hyprcandy_agent_dispatch === "function") {
      try { window.__hyprcandy_agent_dispatch(obj); } catch (e) {}
    }
  }
  function dispatchWhenReady(obj, tries) {
    tries = tries || 0;
    if (typeof window.__hyprcandy_agent_dispatch === "function") { dispatch(obj); }
    else if (tries < 100) { setTimeout(function () { dispatchWhenReady(obj, tries + 1); }, 50); }
  }
  function post(raw) {
    try {
      fetch('/bridge', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: String(raw)
      }).then(function (r) { return r.json(); })
        .then(function (obj) { if (obj) dispatch(obj); })
        .catch(function () {});
    } catch (e) {}
  }
  window.webkit = window.webkit || {};
  window.webkit.messageHandlers = window.webkit.messageHandlers || {};
  window.webkit.messageHandlers.agent = { postMessage: post };
  // Cold start: pull theme + runtime config the same way _agentInjectTheme
  // pushed them under WebKit, and rehydrate via __hyprcandy_agent_dispatch.
  fetch('/bridge', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'bootstrap' })
  }).then(function (r) { return r.json(); })
    .then(function (o) {
      if (!o) return;
      if (o.theme) dispatchWhenReady({ type: 'theme_update', payload: o.theme }, 0);
      if (o.runtime_config) dispatchWhenReady({ type: 'runtime_config', payload: o.runtime_config }, 0);
    })
    .catch(function () {});
})();
</script>
"""


def guess(path):
    return mimetypes.guess_type(path)[0] or "application/octet-stream"


def read_theme_map():
    """Parse gtk-4.0/colors.css @define-color entries (GJS parity)."""
    out = {}
    try:
        with open(COLORS_CSS, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        for name, val in re.findall(
                r"@define-color\s+([a-zA-Z0-9_-]+)\s+([^;]+);", text):
            out[name] = val.strip()
    except Exception:  # noqa: BLE001
        pass
    return out


def _secret_args(payload):
    svc = str(payload.get("service") or SECRET_DEFAULT_SERVICE)
    acct = str(payload.get("account") or "")
    args = ["service", svc]
    if acct:
        args += ["account", acct]
    return svc, acct, args


# ── Bridge action handlers (return the object to send back) ────────────────
def handle_runtime_request(id_, payload):
    url = payload.get("url") or (RUNTIME_URL + "/health")
    method = (payload.get("method") or "POST").upper()
    body = None if method == "GET" else json.dumps(
        payload.get("payload") or {}).encode("utf-8")
    req = urllib.request.Request(url, data=body, method=method)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=220) as resp:
            text = resp.read().decode("utf-8", "replace")
            try:
                parsed = json.loads(text)
            except Exception:  # noqa: BLE001
                parsed = {"text": text}
            return {"id": id_, "type": "response", "payload": parsed}
    except urllib.error.HTTPError as err:
        raw = err.read().decode("utf-8", "replace") if err.fp else ""
        return {"id": id_, "type": "response",
                "error": "Runtime HTTP %s: %s" % (err.code, raw[:200])}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response",
                "error": "Runtime request error: %s" % err}


def handle_secret_store(id_, payload):
    svc, acct, args = _secret_args(payload)
    secret = str(payload.get("secret") or "")
    label = "HyprCandy: %s (%s)" % (svc, acct)
    cmd = ["secret-tool", "store", "--label=" + label] + args
    try:
        p = subprocess.run(cmd, input=secret.encode("utf-8"), timeout=15)
        return {"id": id_, "type": "response", "payload": {"ok": p.returncode == 0}}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_secret_lookup(id_, payload):
    _svc, _acct, args = _secret_args(payload)
    try:
        p = subprocess.run(["secret-tool", "lookup"] + args,
                           capture_output=True, timeout=15)
        if p.returncode == 0 and p.stdout:
            secret = p.stdout.decode("utf-8", "replace").strip("\r\n")
            return {"id": id_, "type": "response", "payload": {"secret": secret or None}}
        return {"id": id_, "type": "response", "payload": {"secret": None}}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_secret_clear(id_, payload):
    _svc, _acct, args = _secret_args(payload)
    try:
        p = subprocess.run(["secret-tool", "clear"] + args, timeout=15)
        return {"id": id_, "type": "response", "payload": {"ok": p.returncode == 0}}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_web_search(id_, payload):
    query = payload.get("query") or ""
    url = "http://127.0.0.1:8080/search?q=%s&format=json" % quote(query)
    try:
        with urllib.request.urlopen(url, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8", "replace"))
            return {"id": id_, "type": "response", "payload": data.get("results") or []}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_searxng_status(id_, _payload):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080/", timeout=3) as resp:
            running = 200 <= resp.status < 400
    except Exception:  # noqa: BLE001
        running = False
    return {"id": id_, "type": "response", "payload": {"running": running}}


def handle_open_external(id_, payload):
    url = str(payload.get("url") or "")
    if url.startswith("http://") or url.startswith("https://"):
        try:
            subprocess.Popen(["xdg-open", url])
        except Exception:  # noqa: BLE001
            pass
    return {"id": id_, "type": "response", "payload": {"ok": True}}


def handle_searxng_start(id_, _payload):
    # Best-effort docker start of the local SearXNG stack (GJS parity).
    try:
        subprocess.run(["docker", "compose", "-f",
                        os.path.join(HOME, ".config", "searxng", "docker-compose.yml"),
                        "up", "-d"], capture_output=True, timeout=30)
    except Exception:  # noqa: BLE001
        try:
            subprocess.run(["docker", "start", "searxng"], capture_output=True, timeout=15)
        except Exception:  # noqa: BLE001
            pass
    return {"id": id_, "type": "response", "payload": {"success": True}}


# ── File / project navigation (GJS _agentHandleMessage parity) ─────────────
def handle_list_directory(id_, payload):
    dir_path = payload.get("path") or HOME
    try:
        items = []
        with os.scandir(dir_path) as it:
            for entry in it:
                try:
                    is_dir = entry.is_dir()
                    size = 0 if is_dir else entry.stat().st_size
                except OSError:
                    is_dir = entry.is_dir(follow_symlinks=False)
                    size = 0
                items.append({"name": entry.name, "isDir": bool(is_dir), "size": int(size)})
        # Dirs first, then case-insensitive name — matches the tree UX.
        items.sort(key=lambda x: (not x["isDir"], x["name"].lower()))
        return {"id": id_, "type": "response", "payload": items}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_read_file(id_, payload):
    path = payload.get("path")
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            text = f.read()
        offset = int(payload.get("offset") or 0)
        limit = int(payload.get("limit") or 0)
        if offset > 0 or limit > 0:
            lines = text.split("\n")
            start = offset - 1 if offset > 0 else 0
            end = start + limit if limit > 0 else len(lines)
            text = "\n".join(lines[start:end])
        return {"id": id_, "type": "response", "payload": text}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_write_file(id_, payload):
    path = payload.get("path")
    content = payload.get("content")
    if not path or not isinstance(content, str):
        return {"id": id_, "type": "response",
                "error": "write_file requires a path and string content"}
    try:
        parent = os.path.dirname(path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(path, "w", encoding="utf-8") as f:
            f.write(content)
        return {"id": id_, "type": "response", "payload": {"success": True}}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_exec_command(id_, payload):
    cmd = payload.get("command") or ""
    cwd = payload.get("cwd") or HOME
    try:
        p = subprocess.run(["/bin/bash", "-c", "cd %s && %s" % (_shq(cwd), cmd)],
                           capture_output=True, text=True, timeout=120)
        return {"id": id_, "type": "response", "payload": {
            "exitCode": p.returncode, "stdout": p.stdout or "", "stderr": p.stderr or ""}}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_fetch_url(id_, payload):
    url = str(payload.get("url") or "")
    if not re.match(r"^https?://", url, re.I):
        return {"id": id_, "type": "response",
                "error": "fetch_url requires an absolute http(s) URL"}
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "HyprCandyLauncher/1.0"})
        with urllib.request.urlopen(req, timeout=12) as resp:
            raw = resp.read()
        try:
            text = raw.decode("utf-8", "replace")
        except Exception:  # noqa: BLE001
            text = ""
        return {"id": id_, "type": "response",
                "payload": {"url": url, "text": text[:20000]}}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_take_screenshot(id_, payload):
    shot_dir = os.path.join(HOME, "Pictures", "Screenshots")
    try:
        os.makedirs(shot_dir, exist_ok=True)
        ts = _dt.datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = "screenshot_%s.png" % ts
        file_path = os.path.join(shot_dir, filename)
        args = ["grim"]
        region = payload.get("region")
        if isinstance(region, str) and region.strip():
            args += ["-g", region.strip()]
        args.append(file_path)
        p = subprocess.run(args, capture_output=True, text=True, timeout=15)
        if p.returncode == 0 and os.path.isfile(file_path):
            return {"id": id_, "type": "response", "payload": {"path": file_path, "filename": filename}}
        return {"id": id_, "type": "response",
                "error": (p.stderr or "").strip() or ("grim exited with code %d" % p.returncode)}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def handle_file_dialog(id_, payload):
    is_dir = bool(payload.get("directory"))
    curr = payload.get("currentFolder") or HOME
    args = ["zenity", "--file-selection", "--filename=%s/" % curr]
    if is_dir:
        args.append("--directory")
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=120)
        picked = (p.stdout or "").strip() if p.returncode == 0 else None
        return {"id": id_, "type": "response", "payload": picked or None}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


ACTIONS = {
    "runtime_request": handle_runtime_request,
    "list_directory": handle_list_directory,
    "read_file": handle_read_file,
    "write_file": handle_write_file,
    "exec_command": handle_exec_command,
    "fetch_url": handle_fetch_url,
    "take_screenshot": handle_take_screenshot,
    "file_dialog": handle_file_dialog,
    "searxng_start": handle_searxng_start,
    "secret_store": handle_secret_store,
    "secret_lookup": handle_secret_lookup,
    "secret_clear": handle_secret_clear,
    "web_search": handle_web_search,
    "searxng_status": handle_searxng_status,
    "open_external_url": handle_open_external,
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):  # keep the launcher log quiet
        pass

    def _isolation_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")

    def _respond(self, code, ctype, data, extra=None, head_only=False):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self._isolation_headers()
        if extra:
            for k, v in extra.items():
                self.send_header(k, v)
        self.end_headers()
        if not head_only:
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

    def _serve_index(self, fp, head_only):
        # Read the SPA shell and splice the bridge shim in before the first
        # <script> so it is installed at document-start, ahead of the bundle.
        try:
            with open(fp, "rb") as f:
                html = f.read().decode("utf-8", "replace")
            if "<head" in html:
                idx = html.lower().index("<head")
                close = html.find(">", idx)
                html = html[:close + 1] + BRIDGE_SHIM + html[close + 1:]
            else:
                html = BRIDGE_SHIM + html
            data = html.encode("utf-8")
            self._respond(200, "text/html; charset=utf-8", data,
                          extra={"Cache-Control": "no-cache"}, head_only=head_only)
        except Exception as err:  # noqa: BLE001
            sys.stderr.write("hc-agent index inject error: %s\n" % err)
            self._send_file(fp, head_only, "no-cache")

    def _send_file(self, fp, head_only, cache):
        try:
            size = os.path.getsize(fp)
            rng = self.headers.get("Range")
            if rng and rng.startswith("bytes=") and size > 0:
                spec = rng[6:].strip().split("-")
                start = int(spec[0]) if spec[0] else 0
                end = int(spec[1]) if len(spec) > 1 and spec[1] else size - 1
                if end >= size:
                    end = size - 1
                if start > end:
                    self._respond(416, "text/plain", b"", head_only=head_only)
                    return
                length = end - start + 1
                with open(fp, "rb") as f:
                    f.seek(start)
                    data = f.read(length)
                self._respond(206, guess(fp), data, extra={
                    "Accept-Ranges": "bytes",
                    "Content-Range": "bytes %d-%d/%d" % (start, end, size),
                    "Cache-Control": cache,
                }, head_only=head_only)
            else:
                with open(fp, "rb") as f:
                    data = f.read()
                self._respond(200, guess(fp), data, extra={
                    "Accept-Ranges": "bytes",
                    "Cache-Control": cache,
                }, head_only=head_only)
        except Exception as err:  # noqa: BLE001
            sys.stderr.write("hc-agent serve error %s: %s\n" % (fp, err))
            self._respond(500, "text/plain", b"server error", head_only=head_only)

    def _media(self, path, head_only):
        target = unquote(path[len("/_media_file/"):])
        if not target.startswith("/"):
            target = "/" + target
        if not os.path.isfile(target):
            self._respond(404, "text/plain", b"not found", head_only=head_only)
            return
        self._send_file(target, head_only, "public, max-age=3600")

    def _is_index(self, fp):
        return os.path.basename(fp) == "index.html"

    def _static(self, path, head_only):
        rel = unquote(path.split("?", 1)[0]).lstrip("/")
        if rel == "" or rel.endswith("/"):
            rel += "index.html"
        if ".." in rel.split("/"):
            self._respond(404, "text/plain", b"not found", head_only=head_only)
            return
        fp = os.path.normpath(os.path.join(DIST, *rel.split("/")))
        if not fp.startswith(DIST) or not os.path.isfile(fp):
            idx = os.path.join(DIST, "index.html")
            base = os.path.basename(rel)
            if "." not in base and os.path.isfile(idx):
                fp = idx  # SPA fallback for client-side routes
            else:
                self._respond(404, "text/plain", b"not found", head_only=head_only)
                return
        if self._is_index(fp):
            self._serve_index(fp, head_only)
        else:
            self._send_file(fp, head_only, "no-cache")

    def _dispatch(self, head_only):
        if self.path.startswith("/_media_file/"):
            self._media(self.path, head_only)
        else:
            self._static(self.path, head_only)

    def do_GET(self):
        self._dispatch(False)

    def do_HEAD(self):
        self._dispatch(True)

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/bridge":
            self._respond(404, "text/plain", b"not found")
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
            raw = self.rfile.read(length).decode("utf-8", "replace") if length else "{}"
            msg = json.loads(raw)
        except Exception as err:  # noqa: BLE001
            self._respond(400, "application/json",
                          json.dumps({"type": "response",
                                      "error": "bad json: %s" % err}).encode())
            return
        action = msg.get("action")
        id_ = msg.get("id")
        payload = msg.get("payload") or {}
        if action == "bootstrap":
            body = json.dumps({
                "theme": read_theme_map(),
                "runtime_config": {
                    "homeDir": HOME,
                    "defaultProjectRoot": DEFAULT_PROJECT_ROOT,
                    "runtimeUrl": RUNTIME_URL,
                    "bridge": "quickshell-loopback",
                },
            }).encode("utf-8")
            self._respond(200, "application/json", body)
            return
        if action in ("console_log", "client_error", "model_status_update",
                      "workspace_startup_state"):
            # Non-privileged / bookkeeping — acknowledge without work.
            extra = {"enabled": True} if action == "workspace_startup_state" else None
            resp = {"id": id_, "type": "response", "payload": extra or {"ok": True}}
            self._respond(200, "application/json", json.dumps(resp).encode())
            return
        handler = ACTIONS.get(action)
        if handler is None:
            self._respond(200, "application/json", json.dumps(
                {"id": id_, "type": "response", "payload": {"ok": True}}).encode())
            return
        try:
            result = handler(id_, payload)
        except Exception as err:  # noqa: BLE001
            result = {"id": id_, "type": "response", "error": str(err)}
        self._respond(200, "application/json", json.dumps(result).encode())


def main():
    if not os.path.isfile(os.path.join(DIST, "index.html")):
        sys.stderr.write("hc-agent: dist index.html not found at %s\n" % DIST)
        return 0  # nothing to serve; exit quietly
    try:
        srv = ThreadingHTTPServer((HOST, PORT), Handler)
    except OSError as err:
        # Port already bound by a warm instance / the GJS launcher: fine.
        sys.stderr.write("hc-agent: %s:%d unavailable (%s); assuming warm instance\n"
                         % (HOST, PORT, err))
        return 0
    sys.stderr.write("hc-agent: serving %s on http://%s:%d/ (runtime %s)\n"
                     % (DIST, HOST, PORT, RUNTIME_URL))
    sys.stderr.flush()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
