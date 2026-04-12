#!/bin/bash
# Rofi border setter
ROFI_BORDER="$HOME/.config/hyprcandy/settings/rofi-border.rasi"

border="$1"

if [ -n "$border" ] && [ -f "$ROFI_BORDER" ]; then
    sed -i "s/border-width: [0-9]*px/border-width: ${border}px/" "$ROFI_BORDER"
fi
