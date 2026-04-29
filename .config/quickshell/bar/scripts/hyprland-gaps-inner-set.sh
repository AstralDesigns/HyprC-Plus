#!/bin/bash
# Set inner gaps value directly or adjust by delta
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"

value="$1"

if [ -n "$value" ] && [ -f "$HYPR_CONF" ]; then
    # Check if this is a delta (starts with + or -)
    if [[ "$value" =~ ^[+-][0-9]+$ ]]; then
        # Get current value
        current=$(grep "gaps_in = " "$HYPR_CONF" 2>/dev/null | head -1 | grep -oP '[0-9]+')
        if [ -z "$current" ]; then current=8; fi
        nv=$((current + value))
    else
        # Absolute value
        nv=$(echo "$value" | grep -oP '[0-9]+')
    fi
    
    if [ -n "$nv" ]; then
        # Validate and clamp between 0 and 100
        [ "$nv" -lt 0 ] 2>/dev/null && nv=0
        [ "$nv" -gt 100 ] 2>/dev/null && nv=100
        sed -i '/general {/,/^}/ s/gaps_in = [0-9]*/gaps_in = '"$nv"'/' "$HYPR_CONF"
        hyprctl reload
        echo "ok"
    fi
fi
