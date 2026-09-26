#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

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
  npm ci --include=dev --no-audit --no-fund --loglevel=error
fi
./node_modules/.bin/tsc --noEmit
./node_modules/.bin/vite build

echo "Setup complete: the Python runtime venv is ready, and dist/index.html is built."
echo "Nothing was started — the Python runtime starts itself the first time the agent workspace is opened."
