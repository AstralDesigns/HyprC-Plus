#!/bin/bash
# Lua-aware presets: persist through the CC state helper so the hyprviz-state.lua
# overrides (loaded after hyprviz.lua) don't revert the preset on the next reload.
HELPER="$HOME/.config/quickshell/bar/scripts/hyprland-lua-state.sh"

case "$1" in
    "minimal")
        GAPS_OUT=2
        GAPS_IN=1
        BORDER=2
        ROUNDING=3
        ;;
    "balanced")
        GAPS_OUT=6
        GAPS_IN=4
        BORDER=3
        ROUNDING=10
        ;;
    "spacious")
        GAPS_OUT=10
        GAPS_IN=6
        BORDER=3
        ROUNDING=10
        ;;
    "zero")
        GAPS_OUT=0
        GAPS_IN=0
        BORDER=0
        ROUNDING=0
        ;;
    *)
        echo "Usage: $0 {minimal|balanced|spacious|zero}"
        exit 1
        ;;
esac

"$HELPER" set gaps_out "$GAPS_OUT" >/dev/null
"$HELPER" set gaps_in "$GAPS_IN" >/dev/null
"$HELPER" set border_size "$BORDER" >/dev/null
"$HELPER" set rounding "$ROUNDING" >/dev/null
hyprctl reload

echo "🎨 Applied $1 preset: gaps_out=$GAPS_OUT, gaps_in=$GAPS_IN, border=$BORDER, rounding=$ROUNDING"
notify-send "Visual Preset Applied" "$1: OUT=$GAPS_OUT IN=$GAPS_IN BORDER=$BORDER ROUND=$ROUNDING" -t 3000
