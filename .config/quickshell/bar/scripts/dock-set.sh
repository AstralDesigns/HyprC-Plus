#!/bin/bash
# Dock setting writer
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"

key="$1"
value="$2"

if [ -n "$key" ] && [ -n "$value" ] && [ -f "$CONFIG" ]; then
    sed -i "s/${key}: [0-9]*/${key}: ${value}/" "$CONFIG"
    pkill -SIGUSR2 -f 'gjs dock-main.js'
fi
