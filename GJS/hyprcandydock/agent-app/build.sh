#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

# One-shot first-time setup for a new install: prepares everything the agent
# workspace needs to run, without starting or auto-starting any of it —
# llama-server and the Python runtime server are both left OFF. The GJS
# launcher starts the Python runtime itself on demand (it's lightweight, no
# model loaded), and llama-server only ever starts when the user activates a
# model from the Model Manager's Local tab.

echo "== 1/3: llama.cpp (llama-server) =="
./build-llama-server.sh

echo "== 2/3: Python runtime (Agents/local_runtime) =="
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

echo "== 3/3: agent-app frontend (React UI) =="
if [[ ! -d node_modules ]]; then
  npm ci --include=dev --no-audit --no-fund --loglevel=error
fi
./node_modules/.bin/tsc --noEmit
./node_modules/.bin/vite build

echo "Setup complete: llama-server is installed, the Python runtime venv is ready, and dist/index.html is built."
echo "Nothing was started — llama-server activates from the Model Manager's Local tab; the Python runtime starts itself the first time the agent workspace is opened."
