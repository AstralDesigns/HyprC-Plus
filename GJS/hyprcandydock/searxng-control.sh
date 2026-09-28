#!/usr/bin/env bash
# Backward-compatible wrapper delegating to hyprcandy-docker.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/hyprcandy-docker.sh" "$@"
