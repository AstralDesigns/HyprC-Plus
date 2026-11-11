#!/usr/bin/env bash
# start.sh — Launch the HyprCandy local Python runtime server
# Called by app-launcher.js on startup. Port 17900.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV="$SCRIPT_DIR/.venv"
PIDFILE="$SCRIPT_DIR/.runtime.pid"
LOG="$SCRIPT_DIR/.runtime.log"

# ── Create venv and install deps if needed ─────────────────────────────────
if [ ! -f "$VENV/bin/uvicorn" ]; then
    echo "[runtime] Setting up Python virtual environment..."
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet \
        fastapi \
        uvicorn[standard] \
        httpx \
        pydantic
fi

# ── Kill any stale instance ────────────────────────────────────────────────
if [ -f "$PIDFILE" ]; then
    OLD_PID=$(cat "$PIDFILE" 2>/dev/null || true)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        kill "$OLD_PID" 2>/dev/null || true
        sleep 0.5
    fi
    rm -f "$PIDFILE"
fi

# ── Start server ────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR"
if command -v systemd-run >/dev/null 2>&1 && systemctl --user is-system-running >/dev/null 2>&1; then
    systemctl --user stop hyprcandy-runtime.service 2>/dev/null || true
    systemd-run --user --unit=hyprcandy-runtime \
        "$VENV/bin/uvicorn" runtime_server:app \
        --app-dir "$SCRIPT_DIR" \
        --host 127.0.0.1 \
        --port 17900 \
        --log-level warning
    PID=$(systemctl --user show -p MainPID --value hyprcandy-runtime.service 2>/dev/null || echo "")
else
    nohup "$VENV/bin/uvicorn" runtime_server:app \
        --host 127.0.0.1 \
        --port 17900 \
        --log-level warning \
        --no-access-log \
        >> "$LOG" 2>&1 &
    PID=$!
    disown $PID
fi
echo $PID > "$PIDFILE"
echo "[runtime] Server started (PID $PID) on http://127.0.0.1:17900"
