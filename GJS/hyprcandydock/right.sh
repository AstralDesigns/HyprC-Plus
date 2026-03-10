#!/bin/bash
# right.sh — launch the HyprCandy dock on the right edge (vertical layout)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
pkill -f "gjs dock-main.js" 2>/dev/null
sleep 0.3
echo 1 > "$SCRIPT_DIR/dock.pos"
echo 1 > "$SCRIPT_DIR/dock.state"
exec "$SCRIPT_DIR/launch-modular.sh" -r
