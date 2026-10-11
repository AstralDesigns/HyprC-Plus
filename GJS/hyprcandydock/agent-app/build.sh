#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

# ── Size the V8 heap for this machine before the React build ─────────────────
# `tsc --noEmit` + `vite build` need more old-space than Node's default ceiling;
# on low-RAM devices the build aborts with "ineffective mark-compacts near heap
# limit allocation failed - javascript heap out of memory" (seen on a 4-cpu
# i5-3337U box). Give the build ~half of MemTotal (MB), clamped to [1024,8192] so
# we never ask for more than the machine has. Honours a caller-set NODE_OPTIONS.
if [ -z "${NODE_OPTIONS:-}" ]; then
  _mem_mb="$(awk '/MemTotal/{print int($2/1024); exit}' /proc/meminfo 2>/dev/null)"
  case "$_mem_mb" in ''|*[!0-9]*) _mem_mb=2048 ;; esac
  _heap=$((_mem_mb/2))
  if [ "$_heap" -lt 1024 ]; then _heap=1024; fi
  if [ "$_heap" -gt 8192 ]; then _heap=8192; fi
  export NODE_OPTIONS="--max-old-space-size=${_heap}"
  echo "Build heap: NODE_OPTIONS=$NODE_OPTIONS (MemTotal=${_mem_mb}MB)"
fi

# One-shot first-time setup for a new install: prepares everything the agent
# workspace needs to run, without starting or auto-starting any of it.
# The GJS launcher starts the Python runtime itself on demand (it's lightweight,
# BYOK / cloud inference).

echo "== 1/2: Python runtime (Agents/local_runtime) =="
RUNTIME_DIR="../Agents/local_runtime"
VENV="$RUNTIME_DIR/.venv"
if [[ ! -f "$VENV/bin/uvicorn" ]]; then
  echo "Creating Python virtual environment and installing dependencies..."
  python3 -m venv "$VENV"
  # Keep this package list identical to start.sh's own bootstrap — that
  # script re-checks/re-installs the same way on every launch, so the two
  # must never drift.
  "$VENV/bin/pip" install --quiet \
    fastapi \
    "uvicorn[standard]" \
    httpx \
    pydantic
else
  echo "Python virtual environment already present at $VENV — skipping."
fi

echo "== 2/2: agent-app frontend (React UI) =="
if [[ ! -d node_modules ]]; then
  npm ci --include=dev --no-audit --no-fund --loglevel=error || npm install --include=dev --no-audit --no-fund
fi
./node_modules/.bin/tsc --noEmit
./node_modules/.bin/vite build

echo "Setup complete: the Python runtime venv is ready, and dist/index.html is built."
echo "Nothing was started — the Python runtime starts itself the first time the agent workspace is opened."
