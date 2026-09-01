#!/bin/bash
# toggle.sh — show/hide the HyprCandy dock (pure toggle)
#
# Position is always read from dock.pos (written by cycle.sh and direction
# scripts).  No positional args — use cycle.sh to change position.
#
# When the dock is shown:   app-launcher daemon is also started (if not already
#                           running — existing daemon is ALWAYS preserved).
# When the dock is hidden:  SIGUSR1 is sent to hide the launcher window
#                           WITHOUT killing the daemon — WebKit sessions,
#                           cookies, and search state are preserved in memory.
#
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

# ── launcher helpers ───────────────────────────────────────────────────────────

_launcher_running() {
    pgrep -f "gjs.*app-launcher\.js" > /dev/null 2>&1
}

_ensure_launcher() {
    # NEVER kill an existing daemon — it holds WebKit sessions, cookies,
    # search results, and all in-memory state.  Only launch if not running.
    if _launcher_running; then
        return 0
    fi
    if   [ -f "/usr/lib/libgtk4-layer-shell.so"   ]; then
        export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:${LD_PRELOAD}"
    elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
        export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:${LD_PRELOAD}"
    fi
    cd "$SCRIPT_DIR"
    setsid gjs "$LAUNCHER" </dev/null >/dev/null 2>&1 &
    # Give daemon a moment to fully initialise before any SIGUSR1
    sleep 0.5
}

_hide_launcher_window() {
    # Send SIGUSR1 to hide the launcher window gracefully (same as start button).
    # Only send if window is currently shown (launcher.state == open).
    local state_path="$HOME/.cache/hyprcandy/launcher.state"
    if [ -f "$state_path" ] && grep -q "^open" "$state_path" 2>/dev/null; then
        pkill -10 -f "gjs.*app-launcher\.js" 2>/dev/null
    else
        # Send anyway if state file is missing/stale — no harm if window is hidden
        pkill -10 -f "gjs.*app-launcher\.js" 2>/dev/null || true
    fi
}

# ── toggle ─────────────────────────────────────────────────────────────────────

if pgrep -f "gjs dock-main.js" > /dev/null 2>&1; then
    # Dock is running → hide it
    echo 0 > "$STATE_FILE"
    pkill -f "gjs dock-main.js"

    # Hide launcher window but KEEP daemon alive — preserves WebKit &
    # search state so next re-show is instant with full session intact.
    _hide_launcher_window
else
    # Dock is hidden → show it
    echo 1 > "$STATE_FILE"
    # Ensure launcher daemon is running (start only if not already alive)
    _ensure_launcher
    exec "$SCRIPT_DIR/launch-modular.sh" "$(_pos_flag)"
fi
