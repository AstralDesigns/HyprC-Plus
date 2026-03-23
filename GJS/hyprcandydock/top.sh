#!/bin/bash
# top.sh — launch the HyprCandy dock at the top of the screen
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pkill -f "gjs dock-main.js" 2>/dev/null
sleep 0.3
echo 2 > "$SCRIPT_DIR/dock.pos"
echo 1 > "$SCRIPT_DIR/dock.state"
exec "$SCRIPT_DIR/launch-modular.sh" -t
