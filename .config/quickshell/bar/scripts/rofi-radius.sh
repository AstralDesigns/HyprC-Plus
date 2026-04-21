#!/bin/bash
# Rofi radius setter
ROFI_RADIUS="$HOME/.config/hyprcandy/settings/rofi-border-radius.rasi"

radius="$1"

if [ -n "$radius" ] && [ -f "$ROFI_RADIUS" ]; then
    vs=$(printf "%.1f" "$radius")
    sed -i "s/border-radius: [0-9.]*em/border-radius: ${vs}em/" "$ROFI_RADIUS"
fi
