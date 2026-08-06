#!/bin/bash
# Read current dock border GTK color name from style.css (without @ prefix).
STYLE="$HOME/.hyprcandy/GJS/hyprcandydock/style.css"

if [ -f "$STYLE" ]; then
    grep -oP 'border-color:\s*@\K[a-zA-Z0-9_]+' "$STYLE" | head -1
fi
