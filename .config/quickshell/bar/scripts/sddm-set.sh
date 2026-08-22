#!/bin/bash
# SDDM theme.conf setter
# Usage: sddm-set.sh <key> <value> [state_file]
# Automatically preserves quoted/unquoted format from the existing line in theme.conf.
SDDM_THEME="/usr/share/sddm/themes/sugar-candy/theme.conf"
STATE_DIR="$HOME/.config/hyprcandy"

key="$1"
value="$2"
state_file="$3"

if [ -n "$key" ] && [ -n "$value" ]; then
    # Check if the existing value for this key is quoted in theme.conf
    if grep -q "^${key}=\"" "$SDDM_THEME" 2>/dev/null; then
        # Preserve quoted format: Key="value"
        sudo sed -i "s|^${key}=.*|${key}=\"${value}\"|" "$SDDM_THEME"
    else
        # Unquoted format: Key=value
        sudo sed -i "s|^${key}=.*|${key}=${value}|" "$SDDM_THEME"
    fi
    # Save state
    if [ -n "$state_file" ]; then
        mkdir -p "$STATE_DIR"
        echo "$value" > "$STATE_DIR/$state_file"
    fi
fi
