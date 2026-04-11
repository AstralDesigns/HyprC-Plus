#!/bin/bash
# Opacity toggle with state persistence
STATE_FILE="$HOME/.config/hyprcandy/opacity.state"
OPAC_SCRIPT="$HOME/.config/hypr/scripts/window-opacity.sh"

if [ "$1" = "toggle" ]; then
    bash "$OPAC_SCRIPT"
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
