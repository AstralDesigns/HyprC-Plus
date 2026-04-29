#!/bin/bash
# autostart.sh — session-restore launcher for the HyprCandy dock
#
# Add to Hyprland config:
#   exec-once = ~/.hyprcandy/GJS/hyprcandydock/autostart.sh
#
# Behaviour:
#   - If dock.state exists and equals "0", the user intentionally hid the
#     dock last session — skip launch to respect that choice.
#   - Otherwise (file missing = first run, or value is "1") launch the dock
#     at the position saved in dock.pos (default: bottom), then start the
#     app-launcher daemon so it is ready for the dock's start-button.
#
# State files (same directory):
#   dock.pos   0=bottom 1=right 2=top 3=left  (default: 0)
#   dock.state 1=running 0=hidden

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
POS_FILE="$SCRIPT_DIR/dock.pos"
STATE_FILE="$SCRIPT_DIR/dock.state"
LAUNCHER="$SCRIPT_DIR/app-launcher.js"

# Respect an explicit "hidden" state from last session
if [[ -f "$STATE_FILE" ]] && [[ "$(cat "$STATE_FILE")" == "0" ]]; then
    exit 0
fi

# Map dock.pos index → launch flag (default bottom)
idx=0
[[ -f "$POS_FILE" ]] && idx=$(cat "$POS_FILE")
case "$idx" in
    1) FLAG="-r" ;;
    2) FLAG="-t" ;;
    3) FLAG="-l" ;;
    *) FLAG="-b" ;;
esac

# ── Start the app-launcher daemon ──────────────────────────────────────────
# Kill any stale instance first, then launch fresh in the background.
pkill -f "gjs $LAUNCHER" 2>/dev/null

if   [ -f "/usr/lib/libgtk4-layer-shell.so"   ]; then
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:${LD_PRELOAD}"
elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:${LD_PRELOAD}"
fi

cd "$SCRIPT_DIR"
setsid gjs "$LAUNCHER" </dev/null >/dev/null 2>&1 &

# ── Launch the dock ────────────────────────────────────────────────────────
exec "$SCRIPT_DIR/launch-modular.sh" "$FLAG"
