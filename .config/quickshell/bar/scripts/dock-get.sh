#!/bin/bash
# Get dock config value
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"
key="$1"

if [ -f "$CONFIG" ]; then
    # Use digit-only pattern for numeric keys to avoid runaway matches into comments/paths
    case "$key" in
        appIconSize|buttonSpacing|innerPadding|borderWidth|borderRadius)
            grep -oP "${key}:\s*\K[0-9]+" "$CONFIG" | head -1
            ;;
        *)
            grep -oP "${key}:\s*\K[^,]+" "$CONFIG" | head -1 | tr -d " '"
            ;;
    esac
fi
