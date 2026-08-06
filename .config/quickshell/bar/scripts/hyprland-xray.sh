#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELPER="$SCRIPT_DIR/hyprland-lua-state.sh"
# X-Ray toggle/status with Lua state persistence.
STATE_FILE="$HOME/.config/hyprcandy/xray.state"
case "${1:-toggle}" in
    status)
        [ -f "$STATE_FILE" ] && echo "on" || echo "off"
        ;;
    toggle|*)
        if [ -f "$STATE_FILE" ]; then
            rm -f "$STATE_FILE"
            "$HELPER" set xray false >/dev/null
            echo "off"
        else
            mkdir -p "$(dirname '$STATE_FILE')"
            echo "enabled" > "$STATE_FILE"
            "$HELPER" set xray true >/dev/null
            echo "on"
        fi
        hyprctl reload 2>/dev/null || true
        ;;
esac
