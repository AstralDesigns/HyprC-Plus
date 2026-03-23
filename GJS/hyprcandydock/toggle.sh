#!/bin/bash
# toggle.sh — show/hide the HyprCandy dock (pure toggle)
#
# Position is always read from dock.pos (written by cycle.sh and direction
# scripts).  No positional args — use cycle.sh to change position.
#
# State files (same directory):
#   dock.pos   0=bottom 1=right 2=top 3=left  (default: 0)
#   dock.state 1=running 0=hidden              (written here)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POS_FILE="$SCRIPT_DIR/dock.pos"
STATE_FILE="$SCRIPT_DIR/dock.state"

# ── position helper ────────────────────────────────────────────────────────────

_pos_flag() {
    local idx=0
    [[ -f "$POS_FILE" ]] && idx=$(cat "$POS_FILE")
    case "$idx" in
        1) echo "-r" ;;
        2) echo "-t" ;;
        3) echo "-l" ;;
        *) echo "-b" ;;
    esac
}

# ── toggle ─────────────────────────────────────────────────────────────────────

if pgrep -f "gjs dock-main.js" > /dev/null 2>&1; then
    echo 0 > "$STATE_FILE"
    pkill -f "gjs dock-main.js"
else
    echo 1 > "$STATE_FILE"
    exec "$SCRIPT_DIR/launch-modular.sh" "$(_pos_flag)"
fi
