#!/bin/bash
# toggle.sh — show/hide the HyprCandy dock (pure toggle)
#
# Position is always read from dock.pos (written by cycle.sh and direction
# scripts).  No positional args — use cycle.sh to change position.
#
# When the dock is shown:   app-launcher daemon is also started.
# When the dock is hidden:  app-launcher daemon is also killed.
# The dock's start-button continues to use toggle-app-launcher.sh (SIGUSR1)
# to show/hide the launcher UI while the dock is running.
#
# State files (same directory):
#   dock.pos   0=bottom 1=right 2=top 3=left  (default: 0)
#   dock.state 1=running 0=hidden              (written here)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POS_FILE="$SCRIPT_DIR/dock.pos"
STATE_FILE="$SCRIPT_DIR/dock.state"
LAUNCHER="$SCRIPT_DIR/app-launcher.js"

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

# ── launcher helper ────────────────────────────────────────────────────────────

_start_launcher() {
    pkill -f "gjs $LAUNCHER" 2>/dev/null
    if   [ -f "/usr/lib/libgtk4-layer-shell.so"   ]; then
        export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:${LD_PRELOAD}"
    elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
        export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:${LD_PRELOAD}"
    fi
    cd "$SCRIPT_DIR"
    setsid gjs "$LAUNCHER" </dev/null >/dev/null 2>&1 &
}

# ── toggle ─────────────────────────────────────────────────────────────────────

if pgrep -f "gjs dock-main.js" > /dev/null 2>&1; then
    # Dock is running → hide it and kill the launcher daemon
    echo 0 > "$STATE_FILE"
    pkill -f "gjs dock-main.js"
    pkill -f "gjs $LAUNCHER" 2>/dev/null
else
    # Dock is hidden → show it and start the launcher daemon
    echo 1 > "$STATE_FILE"
    _start_launcher
    exec "$SCRIPT_DIR/launch-modular.sh" "$(_pos_flag)"
fi
