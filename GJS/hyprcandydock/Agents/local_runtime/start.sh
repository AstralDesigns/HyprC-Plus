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
nohup "$VENV/bin/uvicorn" runtime_server:app \
    --host 127.0.0.1 \
    --port 17900 \
    --log-level warning \
    --no-access-log \
    >> "$LOG" 2>&1 &
PID=$!
disown $PID
echo $PID > "$PIDFILE"
echo "[runtime] Server started (PID $PID) on http://127.0.0.1:17900"
