#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/hyprland-lua-state.sh"
# Adjust window opacity in hyprviz-state.lua.
delta="${1:--0.05}"
"$HELPER" adjust opacity "$delta"
hyprctl reload 2>/dev/null || true
