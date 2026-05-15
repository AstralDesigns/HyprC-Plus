#!/bin/bash
# Set border radius (rounding) value directly or adjust by delta
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"

value="$1"

if [ -n "$value" ] && [ -f "$HYPR_CONF" ]; then
    if [[ "$value" =~ ^[+-][0-9]+$ ]]; then
        current=$(grep "rounding = " "$HYPR_CONF" 2>/dev/null | head -1 | grep -oP '[0-9]+')
        [ -z "$current" ] && current=10
        nv=$((current + value))
    else
        nv=$(echo "$value" | grep -oP '[0-9]+')
    fi
    if [ -n "$nv" ]; then
        [ "$nv" -lt 0 ] 2>/dev/null && nv=0
        [ "$nv" -gt 50 ] 2>/dev/null && nv=50
        sed -i '/decoration {/,/^}/ s/rounding = [0-9]*/rounding = '"$nv"'/' "$HYPR_CONF"
        hyprctl reload
        echo "ok"
    fi
fi
