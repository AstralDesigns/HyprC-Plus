#!/bin/bash
# Hyprsunset toggle/status - matches candy-utils.js exactly
STATE_FILE="$HOME/.config/hyprcandy/hyprsunset.state"

case "$1" in
    status)
        [ -f "$STATE_FILE" ] && echo "on" || echo "off"
        ;;
    toggle|*)
        if [ -f "$STATE_FILE" ]; then
            pkill hyprsunset
            rm -f "$STATE_FILE"
        else
            # Double-fork to fully detach (survives parent death)
            ( hyprsunset >/dev/null 2>&1 & ) &
            echo "enabled" > "$STATE_FILE"
        fi
        ;;
esac
