#!/bin/bash
# Hyprsunset toggle/status/apply - matches candy-utils.js exactly
STATE_FILE="$HOME/.config/hyprcandy/hyprsunset.state"

case "$1" in
    status|apply|restore)
        if [ -f "$STATE_FILE" ]; then
            if ! pgrep -x hyprsunset >/dev/null 2>&1; then
                ( hyprsunset >/dev/null 2>&1 & ) &
            fi
            echo "on"
        else
            echo "off"
        fi
        ;;
    toggle|*)
        if [ -f "$STATE_FILE" ]; then
            pkill -x hyprsunset 2>/dev/null
            rm -f "$STATE_FILE"
        else
            # Double-fork to fully detach (survives parent death)
            ( hyprsunset >/dev/null 2>&1 & ) &
            echo "enabled" > "$STATE_FILE"
        fi
        ;;
esac
