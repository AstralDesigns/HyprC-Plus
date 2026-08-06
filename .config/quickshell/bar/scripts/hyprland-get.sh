#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/hyprland-lua-state.sh"
# Read a Hyprland value from Quickshell state with migrated Lua defaults.
key="${1:-}"
[ -n "$key" ] || exit 1
case "$key" in
    active_opacity|inactive_opacity) key="opacity" ;;
    size|blur_size) key="blur_size" ;;
    passes|blur_passes) key="blur_passes" ;;
    col.active_border|active_border) key="active_border" ;;
    col.inactive_border|inactive_border) key="inactive_border" ;;
esac
"$HELPER" get "$key"
