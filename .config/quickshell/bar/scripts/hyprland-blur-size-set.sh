#!/bin/bash
# Set blur size value directly or adjust by delta
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"

value="$1"

if [ -n "$value" ] && [ -f "$HYPR_CONF" ]; then
    if [[ "$value" =~ ^[+-][0-9]+$ ]]; then
        current=$(sed -n '/blur {/,/^}/p' "$HYPR_CONF" 2>/dev/null | grep "size = " | head -1 | grep -oP '[0-9]+')
        [ -z "$current" ] && current=3
        nv=$((current + value))
    else
        nv=$(echo "$value" | grep -oP '[0-9]+')
    fi
    if [ -n "$nv" ]; then
        [ "$nv" -lt 0 ] 2>/dev/null && nv=0
        [ "$nv" -gt 50 ] 2>/dev/null && nv=50
        sed -i '/blur {/,/^}/ s/size = [0-9]*/size = '"$nv"'/' "$HYPR_CONF"
        hyprctl reload
        echo "ok"
    fi
fi
