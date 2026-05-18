#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/hyprland-lua-state.sh"
# Set active border color variable in hyprviz-state.lua.
value="${1:-\$source_color}"
[ -n "$value" ] || exit 1
if [[ "$value" =~ ^[+-][0-9]+([.][0-9]+)?$ ]]; then
    "$HELPER" adjust active_border "$value" >/dev/null
else
    "$HELPER" set active_border "$value" >/dev/null
fi
hyprctl reload 2>/dev/null || true
echo "ok"
