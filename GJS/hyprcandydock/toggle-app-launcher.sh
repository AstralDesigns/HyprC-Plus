#!/bin/bash
# toggle-app-launcher.sh — toggle the HyprCandy App Launcher
#
# If the launcher is already running: kill it (dismiss).
# If it is not running: start it at the position stored in dock.pos.
#
# Called by the dock's start-button left-click handler.
# Usage: toggle-app-launcher.sh
#
# The launcher reads dock.pos itself, so no position flag is needed here.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$SCRIPT_DIR/app-launcher.js"

# ── Toggle ─────────────────────────────────────────────────────────────────

if pkill -0 -f "gjs $LAUNCHER" 2>/dev/null; then
    # Running — dismiss it
    pkill -f "gjs $LAUNCHER"
    exit 0
fi

# ── Launch ─────────────────────────────────────────────────────────────────

# gtk4-layer-shell must be LD_PRELOADed for layer-shell anchoring to work.
# (Same requirement as launch-modular.sh for the dock itself.)
if   [ -f "/usr/lib/libgtk4-layer-shell.so"   ]; then
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:${LD_PRELOAD}"
elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:${LD_PRELOAD}"
fi

# Run from the dock directory so imports.searchPath picks up config.js / daemon.js
cd "$SCRIPT_DIR"
exec gjs "$LAUNCHER" &
