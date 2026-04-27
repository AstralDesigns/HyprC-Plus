#!/bin/bash
# Set outer gaps value directly or adjust by delta
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"

value="$1"

if [ -n "$value" ] && [ -f "$HYPR_CONF" ]; then
    if [[ "$value" =~ ^[+-][0-9]+$ ]]; then
        current=$(grep "gaps_out = " "$HYPR_CONF" 2>/dev/null | head -1 | grep -oP '[0-9]+')
        [ -z "$current" ] && current=16
        nv=$((current + value))
    else
        nv=$(echo "$value" | grep -oP '[0-9]+')
    fi
    if [ -n "$nv" ]; then
        [ "$nv" -lt 0 ] 2>/dev/null && nv=0
        [ "$nv" -gt 100 ] 2>/dev/null && nv=100
        sed -i '/general {/,/^}/ s/gaps_out = [0-9]*/gaps_out = '"$nv"'/' "$HYPR_CONF"
        hyprctl reload
        echo "ok"
    fi
fi
