#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/hyprland-lua-state.sh"
# Set border radius in hyprviz-state.lua.
value="${1:-}"
[ -n "$value" ] || exit 1
if [[ "$value" =~ ^[+-][0-9]+([.][0-9]+)?$ ]]; then
    "$HELPER" adjust rounding "$value" >/dev/null
else
    "$HELPER" set rounding "$value" >/dev/null
fi
hyprctl reload 2>/dev/null || true
echo "ok"
