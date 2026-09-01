#!/bin/bash
# toggle-app-launcher.sh — show/hide the HyprCandy App Launcher daemon.
#
# The launcher runs as a persistent daemon (started once by autostart.sh or
# when the dock is first shown).
#
# Toggle = send SIGUSR1 (10) to the running daemon.  The daemon's own signal
# handler shows or hides the window without creating a new process, preserving
# all WebKit sessions, cookies, and search results in memory.
#
# If the daemon is not running (first boot, crashed, etc.) we start it here.
#
# Called by:
#   • dock start-button left-click
#   • Hyprland keybind (SUPER + A)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LAUNCHER="$SCRIPT_DIR/app-launcher.js"

# ── Send SIGUSR1 to the running daemon ──────────────────────────────────────
# Use a broad pattern so it matches regardless of how the path was passed,
# avoiding false "not found" that would spawn a duplicate process.

if pkill -10 -f "gjs.*app-launcher\.js" 2>/dev/null; then
    # Signal delivered — daemon will show/hide itself
    exit 0
fi

# ── Daemon not running — start it ───────────────────────────────────────────
# gtk4-layer-shell must be LD_PRELOADed for layer-shell anchoring to work.

if   [ -f "/usr/lib/libgtk4-layer-shell.so"   ]; then
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:${LD_PRELOAD}"
elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:${LD_PRELOAD}"
fi

# Run from the dock directory so imports.searchPath picks up config.js etc.
cd "$SCRIPT_DIR"
setsid gjs "$LAUNCHER" </dev/null >/dev/null 2>&1 &
