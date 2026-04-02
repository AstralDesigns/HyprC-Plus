#!/bin/bash
# Set blur passes value directly or adjust by delta
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"

value="$1"

if [ -n "$value" ] && [ -f "$HYPR_CONF" ]; then
    if [[ "$value" =~ ^[+-][0-9]+$ ]]; then
        current=$(sed -n '/blur {/,/^}/p' "$HYPR_CONF" 2>/dev/null | grep "passes = " | head -1 | grep -oP '[0-9]+')
        [ -z "$current" ] && current=1
        nv=$((current + value))
    else
        nv=$(echo "$value" | grep -oP '[0-9]+')
    fi
    if [ -n "$nv" ]; then
        [ "$nv" -lt 0 ] 2>/dev/null && nv=0
        [ "$nv" -gt 10 ] 2>/dev/null && nv=10
        sed -i '/blur {/,/^}/ s/passes = [0-9]*/passes = '"$nv"'/' "$HYPR_CONF"
        hyprctl reload
        echo "ok"
    fi
fi
