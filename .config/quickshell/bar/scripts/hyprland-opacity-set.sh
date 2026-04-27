#!/bin/bash
# Set opacity value directly
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"

value="$1"

if [ -n "$value" ] && [ -f "$HYPR_CONF" ]; then
    # Validate and clamp between 0 and 1
    nv=$(echo "$value" | grep -oP '[0-9.]+')
    if [ -n "$nv" ]; then
        if (( $(echo "$nv < 0" | bc -l) )); then nv="0"; fi
        if (( $(echo "$nv > 1" | bc -l) )); then nv="1"; fi
        sed -i "s/active_opacity = .*/active_opacity = $nv/" "$HYPR_CONF"
        sed -i "s/inactive_opacity = .*/inactive_opacity = $nv/" "$HYPR_CONF"
        hyprctl reload
        echo "ok"
    fi
fi
