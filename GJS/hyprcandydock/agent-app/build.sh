#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"
echo "Building llama.cpp llama-server..."
./build-llama-server.sh

echo "Installing agent-app dependencies..."
if [[ ! -d node_modules/@wllama/wllama ]]; then
  npm ci --include=dev --no-audit --no-fund --loglevel=error
fi
./node_modules/.bin/tsc --noEmit
./node_modules/.bin/vite build
echo "Build complete: llama-server and dist/index.html are ready."
