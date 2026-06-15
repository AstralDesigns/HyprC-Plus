#!/bin/bash
# toggle-app-launcher.sh — toggle the HyprCandy App Launcher daemon.
#
# The launcher now runs as a persistent daemon (started once by autostart.sh).
# Toggle = send SIGUSR1 (10) to the running daemon.
#
# If the daemon is not running yet (first boot before autostart fires, or it
# crashed), fall back to launching it so the user isn't left with nothing.
#
# Called by the dock's start-button left-click handler.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$SCRIPT_DIR/app-launcher.js"

# ── Send SIGUSR1 to the running daemon ─────────────────────────────────────

if pkill -10 -f "gjs $LAUNCHER" 2>/dev/null; then
    # Signal delivered — daemon will show/hide itself
    exit 0
fi

# ── Daemon not running — start it ──────────────────────────────────────────
# gtk4-layer-shell must be LD_PRELOADed for layer-shell anchoring to work.

if   [ -f "/usr/lib/libgtk4-layer-shell.so"   ]; then
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:${LD_PRELOAD}"
elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:${LD_PRELOAD}"
fi

# Run from the dock directory so imports.searchPath picks up config.js etc.
cd "$SCRIPT_DIR"
setsid gjs "$LAUNCHER" </dev/null >/dev/null 2>&1 &
