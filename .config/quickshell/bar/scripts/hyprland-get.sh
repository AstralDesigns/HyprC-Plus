#!/bin/bash
# Get hyprland config value
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
key="$1"

if [ -n "$key" ] && [ -f "$HYPR_CONF" ]; then
    grep "^$key = " "$HYPR_CONF" 2>/dev/null | grep -oP '[0-9.]+' | head -1
fi
