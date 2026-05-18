#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/hyprland-lua-state.sh"
# Adjust border width in hyprviz-state.lua.
delta="${1:--1}"
"$HELPER" adjust border_size "$delta"
hyprctl reload 2>/dev/null || true
