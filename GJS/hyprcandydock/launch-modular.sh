#!/bin/bash

# Launch HyprCandy GTK4 Layer Shell Dock
# Usage: ./launch-modular.sh [-b|-t|-l|-r]
#   -b  bottom (default)
#   -t  top
#   -l  left
#   -r  right

# Position flag — default to bottom
POSITION_FLAG="${1:--b}"

# Preload GTK4 Layer Shell (required for layer shell anchoring)
if [ -f "/usr/lib/libgtk4-layer-shell.so" ]; then
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:$LD_PRELOAD"
elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:$LD_PRELOAD"
fi

# Change to script directory so imports.searchPath.unshift('.') finds daemon.js / config.js
cd "$(dirname "$0")"

exec gjs dock-main.js "$POSITION_FLAG"
