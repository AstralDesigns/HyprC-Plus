#!/bin/bash
# Read state file value
STATE_DIR="$HOME/.config/hyprcandy"
key="$1"
fallback="${2:-}"

if [ -f "$STATE_DIR/$key" ]; then
    cat "$STATE_DIR/$key"
else
    echo "$fallback"
fi
