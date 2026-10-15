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
import time
import shutil
import threading
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
# Wallust regenerates this alongside colors.css on wallpaper changes; matugen
# only drives colors.css, so without reading this file the injected
# --wallust-* tokens stayed frozen at their static theme.css fallbacks.
COLORS_WALLUST_CSS = os.path.join(HOME, ".config", "gtk-4.0",
                                  "colors-wallust.css")
# Durable agent-store blob (provider/model/sessions). The app mirrors its
# localStorage payload here through the store_persist bridge action and
# rehydrates from it at bootstrap, so a hard kill can no longer reset the
# workspace to the openrouter/free default.
AGENT_STORE_PATH = os.path.join(HOME, ".local", "share", "hyprcandy",
                                "agent-state.json")
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
  // store_state is the durable JSON blob the app mirrors to disk via the
  // store_persist action — the authoritative hydrate source (localStorage is
  // only a cache; Chromium does not flush it on a hard kill).
  fetch('/bridge', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ action: 'bootstrap' })
  }).then(function (r) { return r.json(); })
    .then(function (o) {
      if (!o) return;
      if (o.store_state) dispatchWhenReady({ type: 'store_state', payload: o.store_state }, 0);
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
    # Wallust palette lives in a separate file and is prefixed so applyTheme
    # maps each entry to --wallust-<name> (bridge.ts wallust_ branch). Without
    # this the file was never shipped and --wallust-* never hot-reloaded.
    try:
        with open(COLORS_WALLUST_CSS, "r", encoding="utf-8",
                  errors="replace") as f:
            wtext = f.read()
        for name, val in re.findall(
                r"@define-color\s+([a-zA-Z0-9_-]+)\s+([^;]+);", wtext):
            out["wallust_" + name] = val.strip()
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


# ── Clipboard (QtWebEngine blocks navigator.clipboard) ─────────────────────
def handle_copy_to_clipboard(id_, payload):
    text = payload.get("text")
    if not isinstance(text, str):
        return {"id": id_, "type": "response", "error": "copy_to_clipboard requires string text"}
    # Prefer wl-copy (Wayland), fall back to xclip/xsel for an X11 session.
    for cmd in (["wl-copy"], ["xclip", "-selection", "clipboard", "-in"],
                ["xsel", "--clipboard", "--input"]):
        try:
            p = subprocess.run(cmd, input=text.encode("utf-8"), timeout=5)
            if p.returncode == 0:
                return {"id": id_, "type": "response", "payload": {"ok": True}}
        except (FileNotFoundError, OSError):
            continue
        except Exception:  # noqa: BLE001
            continue
    return {"id": id_, "type": "response", "error": "no clipboard helper (wl-copy/xclip/xsel)"}


# ── Filesystem change polling (external-edit auto-refresh) ─────────────────
def handle_stat_files(id_, payload):
    """Return {path: mtime_ms} for every requested path (0 when missing).

    One batched round-trip for the app's focus/interval poll: open editor
    paths plus the directories the explorer is showing, so the React side can
    diff mtimes against what it last loaded without a per-file request."""
    out = {}
    targets = set()
    for key in ("paths", "dirs"):
        val = payload.get(key)
        if isinstance(val, list):
            targets.update(str(x) for x in val if x)
    for path in targets:
        try:
            out[path] = int(os.stat(path).st_mtime * 1000)
        except OSError:
            out[path] = 0
    return {"id": id_, "type": "response", "payload": out}


# VCS / build dirs a recursive search should never descend into.
_SEARCH_SKIP = {".git", "node_modules", "__pycache__", ".venv", "venv",
                "target", "dist", "build", ".mypy_cache", ".cache"}


def handle_search_files(id_, payload):
    """Nautilus-style recursive name search under a root, ranked + bounded.

    Returns flat matches (dirs first, then shallowest, then name) so a deep
    file surfaces at the top even when its parent folders stay collapsed."""
    root = payload.get("root") or HOME
    query = str(payload.get("query") or "").strip().lower()
    limit = int(payload.get("limit") or 300)
    if not query:
        return {"id": id_, "type": "response", "payload": []}
    results = []
    scanned = 0
    # Bound the walk by wall-clock so a huge tree returns partial matches well
    # inside the client's request timeout instead of hanging the spinner.
    deadline = time.monotonic() + 6.0
    try:
        for dirpath, dirnames, filenames in os.walk(root):
            # Prune heavy/noise dirs only. Hidden dirs stay searchable because a
            # config tree keeps real files under dot-folders (e.g. .candyinstall).
            dirnames[:] = [d for d in dirnames if d not in _SEARCH_SKIP]
            for name in dirnames + filenames:
                scanned += 1
                if query not in name.lower():
                    continue
                full = os.path.join(dirpath, name)
                is_dir = os.path.isdir(full)
                try:
                    size = 0 if is_dir else os.path.getsize(full)
                except OSError:
                    size = 0
                results.append({
                    "name": name,
                    "path": full,
                    "isDir": bool(is_dir),
                    "size": int(size),
                    "relPath": os.path.relpath(full, root),
                    "depth": rel_depth(full, root),
                })
            if len(results) >= limit or scanned > 200000 or time.monotonic() > deadline:
                break
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}
    results.sort(key=lambda r: (not r["isDir"], r["depth"], r["name"].lower()))
    return {"id": id_, "type": "response", "payload": results[:limit]}


def rel_depth(path, root):
    return len(os.path.relpath(path, root).split("/"))


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


# ── Durable store + live theme (Quickshell parity with the GJS launcher) ───
def handle_store_persist(id_, payload):
    """Atomically mirror the app's store blob to AGENT_STORE_PATH.

    The payload is written verbatim (it is already a JSON string from the
    app's persist path); temp+rename keeps a hard kill from truncating it."""
    try:
        raw = payload if isinstance(payload, str) else json.dumps(payload)
        os.makedirs(os.path.dirname(AGENT_STORE_PATH), exist_ok=True)
        tmp = AGENT_STORE_PATH + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            f.write(raw)
        os.replace(tmp, AGENT_STORE_PATH)
        return {"id": id_, "type": "response", "payload": {"ok": True}}
    except Exception as err:  # noqa: BLE001
        return {"id": id_, "type": "response", "error": str(err)}


def read_store_state():
    """Current durable blob parsed, or None (bootstrap omits it when absent)."""
    try:
        with open(AGENT_STORE_PATH, "r", encoding="utf-8") as f:
            return json.loads(f.read())
    except Exception:  # noqa: BLE001
        return None


def handle_theme(id_, _payload):
    """Re-read colors.css so QML can push a live theme_update after matugen.

    Returned as a ``theme_update`` DISPATCH (not a request/response) because
    the QML caller posts {action:'theme'} with no id and never registers a
    pending request — the shim dispatches whatever comes back straight into
    __hyprcandy_agent_dispatch, which only acts on the theme_update type."""
    return {"type": "theme_update", "payload": read_theme_map()}


# ── inotify-backed filesystem event feed (external-change detection) ──────
# The React app tells us exactly which directories it is showing (watch_paths);
# we run ONE non-recursive inotifywait over that bounded set and buffer touched
# paths. The app drains them (fs_drain) on a short tick, so updates are near-
# instant and independent of window focus — unlike mtime polling. Non-recursive
# keeps the watch count tiny (visible folders + open files' parents only), so a
# huge tree can never exhaust inotify limits.
FS_LOCK = threading.Lock()
FS_CHANGED = set()      # absolute paths touched since the last drain
FS_WATCH_DIRS = set()   # dirs the live inotifywait is monitoring
FS_PROC = None


def _fs_reader(proc):
    # Use explicit readline() (not `for line in stdout`) so each event is picked
    # up the instant it is written instead of waiting for Python's iterator to
    # fill its read-ahead buffer.
    try:
        stream = proc.stdout
        if stream is None:
            return
        readline = stream.readline
        while True:
            line = readline()
            if not line:
                break
            p = line.strip()
            if p:
                with FS_LOCK:
                    if len(FS_CHANGED) < 8000:
                        FS_CHANGED.add(p)
    except Exception:  # noqa: BLE001
        pass


def _fs_restart_watcher(dirs):
    global FS_PROC, FS_WATCH_DIRS
    if FS_PROC:
        try:
            FS_PROC.kill()
            FS_PROC.wait(timeout=1)
        except Exception:  # noqa: BLE001
            pass
        FS_PROC = None
    FS_WATCH_DIRS = set(dirs)
    with FS_LOCK:
        FS_CHANGED.clear()
    if not dirs:
        return
    inotify_cmd = [
        "inotifywait", "-mq",
        "-e", "close_write", "-e", "create", "-e", "delete",
        "-e", "moved_to", "-e", "moved_from",
        "--format", "%w%f", *sorted(dirs),
    ]
    # inotifywait block-buffers stdout when piped; force line-buffering so a
    # single create/modify surfaces immediately rather than after a 4 KB flush.
    if shutil.which("stdbuf"):
        inotify_cmd = ["stdbuf", "-oL", *inotify_cmd]
    try:
        proc = subprocess.Popen(
            inotify_cmd,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, bufsize=1)
    except (FileNotFoundError, OSError):
        return  # inotifywait absent: the mtime-poll fallback still runs
    FS_PROC = proc
    threading.Thread(target=_fs_reader, args=(proc,), daemon=True).start()


def handle_watch_paths(id_, payload):
    dirs = [str(d) for d in (payload.get("dirs") or []) if d and os.path.isdir(d)]
    with FS_LOCK:
        same = set(dirs) == FS_WATCH_DIRS
    alive = FS_PROC is not None and FS_PROC.poll() is None
    if not (same and alive):
        _fs_restart_watcher(dirs)
    return {"id": id_, "type": "response", "payload": {"ok": True}}


def handle_fs_drain(id_, _payload):
    with FS_LOCK:
        paths = list(FS_CHANGED)
        FS_CHANGED.clear()
    return {"id": id_, "type": "response", "payload": {"paths": paths}}


ACTIONS = {
    "runtime_request": handle_runtime_request,
    "list_directory": handle_list_directory,
    "read_file": handle_read_file,
    "write_file": handle_write_file,
    "exec_command": handle_exec_command,
    "fetch_url": handle_fetch_url,
    "take_screenshot": handle_take_screenshot,
    "file_dialog": handle_file_dialog,
    "copy_to_clipboard": handle_copy_to_clipboard,
    "stat_files": handle_stat_files,
    "search_files": handle_search_files,
    "watch_paths": handle_watch_paths,
    "fs_drain": handle_fs_drain,
    "searxng_start": handle_searxng_start,
    "secret_store": handle_secret_store,
    "secret_lookup": handle_secret_lookup,
    "secret_clear": handle_secret_clear,
    "web_search": handle_web_search,
    "searxng_status": handle_searxng_status,
    "open_external_url": handle_open_external,
    "store_persist": handle_store_persist,
    "theme": handle_theme,
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
                "store_state": read_store_state(),
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
