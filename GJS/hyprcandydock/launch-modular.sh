#!/bin/bash

# Launch HyprCandy GTK4 Layer Shell Dock
# Usage: ./launch-modular.sh [-b|-t|-l|-r]
#   -b  bottom (default)
#   -t  top
#   -l  left
#   -r  right

echo "🪟 Launching HyprCandy GTK4 Layer Shell Dock"

# Position flag — default to bottom
POSITION_FLAG="${1:--b}"
echo "📍 Position: $POSITION_FLAG"

# Set Wayland backend
export GDK_BACKEND=wayland

# Set display
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

echo "📊 Display: $WAYLAND_DISPLAY"
echo "🎨 Backend: $GDK_BACKEND"

# Preload GTK4 Layer Shell (required for proper layer shell behavior)
if [ -f "/usr/lib/libgtk4-layer-shell.so" ]; then
    echo "🔗 Preload: /usr/lib/libgtk4-layer-shell.so"
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:$LD_PRELOAD"
elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
    echo "🔗 Preload: /usr/lib64/libgtk4-layer-shell.so"
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:$LD_PRELOAD"
fi

# Change to script directory so imports.searchPath.unshift('.') finds daemon.js / config.js
cd "$(dirname "$0")"

# Launch the dock, forwarding the position flag
exec gjs dock-main.js "$POSITION_FLAG"
