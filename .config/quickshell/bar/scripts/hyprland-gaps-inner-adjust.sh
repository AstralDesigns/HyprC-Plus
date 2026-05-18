#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/hyprland-lua-state.sh"
# Adjust inner gaps in hyprviz-state.lua.
delta="${1:--1}"
"$HELPER" adjust gaps_in "$delta"
hyprctl reload 2>/dev/null || true
