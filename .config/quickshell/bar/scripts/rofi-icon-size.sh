#!/bin/bash
# Rofi icon size adjustment (+/-)
ROFI_CONF="$HOME/.config/rofi/config.rasi"

delta="${1:-0}"

if [ -f "$ROFI_CONF" ]; then
    # Extract current size from element-icon block
    blk=$(sed -n '/element-icon/,/}/p' "$ROFI_CONF")
    v=$(echo "$blk" | grep -oP 'size:\s*\K[0-9.]+')
    if [ -n "$v" ]; then
        nv=$(echo "$v + $delta" | bc)
        # Clamp minimum to 0.5
        if (( $(echo "$nv < 0.5" | bc -l) )); then nv="0.5"; fi
        # Format with proper spacing to match original
        sed -i "/element-icon/,/}/{s/size:[[:space:]]*${v}em/size:                        ${nv}em/}" "$ROFI_CONF"
    fi
fi
