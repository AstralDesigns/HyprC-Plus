#!/bin/bash
# X-Ray toggle with state persistence
STATE_FILE="$HOME/.config/hyprcandy/xray.state"
XRAY_SCRIPT="$HOME/.config/hypr/scripts/xray.sh"

if [ "$1" = "toggle" ]; then
    bash "$XRAY_SCRIPT"
    if [ -f "$STATE_FILE" ]; then
        rm -f "$STATE_FILE"
        echo "off"
    else
        echo "enabled" > "$STATE_FILE"
        echo "on"
    fi
elif [ "$1" = "status" ]; then
    [ -f "$STATE_FILE" ] && echo "on" || echo "off"
fi
