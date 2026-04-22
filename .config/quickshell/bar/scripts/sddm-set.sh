#!/bin/bash
# SDDM theme.conf setter
SDDM_THEME="/usr/share/sddm/themes/sugar-candy/theme.conf"
STATE_DIR="$HOME/.config/hyprcandy"

key="$1"
value="$2"
state_file="$3"

if [ -n "$key" ] && [ -n "$value" ]; then
    # Use sudo to edit root-owned file
    sudo sed -i "s|^${key}=.*|${key}=${value}|" "$SDDM_THEME"
    # Save state
    if [ -n "$state_file" ]; then
        mkdir -p "$STATE_DIR"
        echo "$value" > "$STATE_DIR/$state_file"
    fi
fi
