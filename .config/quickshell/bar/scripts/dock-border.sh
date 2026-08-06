#!/bin/bash
# Write dock WINDOW border color (GTK4 @name) into style.css line 10 and hot-reload.
# Handles both matugen named tokens (primary, background, …) and wallust tokens (color0–color15).
# Usage: dock-border.sh <gtk_name>     e.g. primary, on_secondary, color4
#        dock-border.sh @primary      (@ prefix is stripped)

STYLE="$HOME/.hyprcandy/GJS/hyprcandydock/style.css"
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"
DIR="$HOME/.hyprcandy/GJS/hyprcandydock"
POS_FILE="$DIR/dock.pos"
STATE_FILE="$DIR/dock.state"
LAUNCHER="$DIR/app-launcher.js"

gtk="${1#@}"
gtk="${gtk#\$}"   # tolerate accidental $ prefix from bar-style vars

if [ -z "$gtk" ]; then
    echo "dock-border: usage: dock-border.sh <gtk_name>" >&2
    exit 1
fi

if [ ! -f "$STYLE" ]; then
    echo "dock-border: style.css not found: $STYLE" >&2
    exit 1
fi

if ! grep -q 'border-color:' "$STYLE"; then
    echo "dock-border: no border-color rule in style.css" >&2
    exit 1
fi

# Primary write target — GTK reads @name from style.css (line 10: dock window border)
sed -i "16s/\(border-color:[[:space:]]*\)@[a-zA-Z0-9_]*/\1@${gtk}/" "$STYLE"

# Mirror into config.js for @HCD hot-reload metadata (optional, not the visual source)
if [ -f "$CONFIG" ] && grep -q 'borderColorVar:' "$CONFIG"; then
    sed -i "s/^\([[:space:]]*borderColorVar:\)[[:space:]]*'[^']*'/\1 '${gtk}'/" "$CONFIG"
    sed -i "541s/\(border-color:[[:space:]]*\)@[a-zA-Z0-9_]*/\1@${gtk}/" "$LAUNCHER"
fi

pkill -f 'gjs.*app-launcher.js' 2>/dev/null || true
pkill -SIGUSR2 -f 'gjs dock-main.js' 2>/dev/null || pkill -12 -f 'gjs dock-main.js' 2>/dev/null || true
sleep 0.5

# ── Start the app-launcher daemon ──────────────────────────────────────────
# Kill any stale instance first, then launch fresh in the background.
pkill -f "gjs $LAUNCHER" 2>/dev/null

if   [ -f "/usr/lib/libgtk4-layer-shell.so"   ]; then
    export LD_PRELOAD="/usr/lib/libgtk4-layer-shell.so:${LD_PRELOAD}"
elif [ -f "/usr/lib64/libgtk4-layer-shell.so" ]; then
    export LD_PRELOAD="/usr/lib64/libgtk4-layer-shell.so:${LD_PRELOAD}"
fi

cd "$DIR"
setsid gjs "$LAUNCHER" </dev/null >/dev/null 2>&1 &

echo "$gtk"
