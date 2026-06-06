#!/bin/bash
# Get dock config value
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"
key="$1"

if [ -f "$CONFIG" ]; then
    # Use digit-only pattern for numeric keys to avoid runaway matches into comments/paths
    case "$key" in
        borderTopLeftRadius|borderTopRightRadius|borderBottomLeftRadius|borderBottomRightRadius)
            v=$(grep -oP "${key}:\s*\K[0-9]+" "$CONFIG" | head -1)
            if [ -z "$v" ]; then
                grep -oP 'borderRadius:\s*\K[0-9]+' "$CONFIG" | head -1
            else
                echo "$v"
            fi
            ;;
        appIconSize|buttonSpacing|innerPadding|borderWidth|borderRadius)
            grep -oP "${key}:\s*\K[0-9]+" "$CONFIG" | head -1
            ;;
        rectBgStyle)
            grep -oP "${key}:\s*'\K[^']+" "$CONFIG" | head -1
            ;;
        *)
            grep -oP "${key}:\s*\K[^,]+" "$CONFIG" | head -1 | tr -d " '"
            ;;
    esac
fi
