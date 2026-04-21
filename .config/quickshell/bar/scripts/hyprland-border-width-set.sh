#!/bin/bash
# Set border width value directly or adjust by delta
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"

value="$1"

if [ -n "$value" ] && [ -f "$HYPR_CONF" ]; then
    if [[ "$value" =~ ^[+-][0-9]+$ ]]; then
        current=$(grep "border_size = " "$HYPR_CONF" 2>/dev/null | head -1 | grep -oP '[0-9]+')
        [ -z "$current" ] && current=2
        nv=$((current + value))
    else
        nv=$(echo "$value" | grep -oP '[0-9]+')
    fi
    if [ -n "$nv" ]; then
        [ "$nv" -lt 0 ] 2>/dev/null && nv=0
        [ "$nv" -gt 20 ] 2>/dev/null && nv=20
        sed -i "/general {/,/^}/ s/border_size = [0-9]*/border_size = $nv/" "$HYPR_CONF"
        hyprctl reload
        echo "ok"
    fi
fi
