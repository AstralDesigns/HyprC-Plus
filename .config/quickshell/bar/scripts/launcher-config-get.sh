#!/bin/bash
# App Launcher setting reader — reads a single key from launcherConfig.js.
# Usage: launcher-config-get.sh <key>
# Prints the numeric value, or nothing if not found.
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/launcherConfig.js"

key="$1"

if [ -n "$key" ] && [ -f "$CONFIG" ]; then
    grep -oP "${key}:\s*\K[0-9][0-9.]*" "$CONFIG" | head -1
fi
