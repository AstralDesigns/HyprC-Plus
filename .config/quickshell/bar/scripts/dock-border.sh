#!/bin/bash
# Write dock WINDOW border color (GTK4 @name) into style.css and hot-reload.
# Handles both matugen named tokens (primary, background, …) and wallust tokens (color0–color15).
# Usage: dock-border.sh <gtk_name>     e.g. primary, on_secondary, color4
#        dock-border.sh @primary      (@ prefix is stripped)

STYLE="$HOME/.hyprcandy/GJS/hyprcandydock/style.css"
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"
DIR="$HOME/.hyprcandy/GJS/hyprcandydock"
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

# Primary write target — GTK reads @name from style.css (dock window border)
sed -i "16s/\(border-color:[[:space:]]*\)@[a-zA-Z0-9_]*/\1@${gtk}/" "$STYLE"

# Mirror into config.js for @HCD hot-reload metadata
if [ -f "$CONFIG" ] && grep -q 'borderColorVar:' "$CONFIG"; then
    sed -i "s/^\([[:space:]]*borderColorVar:\)[[:space:]]*'[^']*'/\1 '${gtk}'/" "$CONFIG"
fi

# Update window.hyprcandy-launcher border-color in app-launcher.js (line 718)
if [ -f "$LAUNCHER" ]; then
    sed -i "718s/\(border-color:[[:space:]]*\)@[a-zA-Z0-9_]*/\1@${gtk}/" "$LAUNCHER"
fi

# ── Signal live processes with SIGUSR2 (12) for instant in-place hot-reload ───
pkill -12 -f 'gjs.*dock-main\.js' 2>/dev/null || true
pkill -12 -f 'gjs.*app-launcher\.js' 2>/dev/null || true

# If launcher daemon is not running at all, start it cleanly
if ! pgrep -f "gjs.*app-launcher\.js" >/dev/null 2>&1; then
    "$DIR/toggle-app-launcher.sh" >/dev/null 2>&1 &
fi

echo "$gtk"
