#!/bin/bash
# cycle.sh — cycle the HyprCandy dock clockwise through 4 positions
#
# Position map (clockwise):
#   0 = bottom (-b)   ← default
#   1 = right  (-r)
#   2 = top    (-t)
#   3 = left   (-l)
#
# Always shows the dock at the new position regardless of previous visibility.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POS_FILE="$SCRIPT_DIR/dock.pos"
STATE_FILE="$SCRIPT_DIR/dock.state"

# Position index → launch flag
_pos_flag() {
    case "$1" in
        1) echo "-r" ;;
        2) echo "-t" ;;
        3) echo "-l" ;;
        *) echo "-b" ;;
    esac
}

# Read current position (default 0)
CURRENT=0
[[ -f "$POS_FILE" ]] && CURRENT=$(cat "$POS_FILE")

# Advance clockwise
NEXT=$(( (CURRENT + 1) % 4 ))

# Write new position
echo "$NEXT" > "$POS_FILE"

# Kill any existing instance
pkill -f "gjs dock-main.js" 2>/dev/null
sleep 0.3

# Launch at new position and mark as running
echo 1 > "$STATE_FILE"
exec "$SCRIPT_DIR/launch-modular.sh" "$(_pos_flag "$NEXT")"
