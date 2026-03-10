#!/bin/bash
# left.sh — launch the HyprCandy dock on the left edge (vertical layout)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pkill -f "gjs dock-main.js" 2>/dev/null
sleep 0.3
echo 3 > "$SCRIPT_DIR/dock.pos"
echo 1 > "$SCRIPT_DIR/dock.state"
exec "$SCRIPT_DIR/launch-modular.sh" -l
