#!/bin/bash
# Write dock START/TRASH icon border color (GTK4 @name) into style.css line 49 and hot-reload.
# Handles both matugen named tokens (primary, background, …) and wallust tokens (color0–color15).
# This is the ISLAND BORDER counterpart to dock-border.sh (which targets the dock window at line 10).
# Usage: dock-island-border.sh <gtk_name>    e.g. on_secondary, color0
#        dock-island-border.sh @color0      (@ prefix is stripped)
STYLE="$HOME/.hyprcandy/GJS/hyprcandydock/style.css"
gtk="${1#@}"
gtk="${gtk#\$}"   # tolerate accidental $ prefix from bar-style vars
if [ -z "$gtk" ]; then
    echo "dock-island-border: usage: dock-island-border.sh <gtk_name>" >&2
    exit 1
fi
if [ ! -f "$STYLE" ]; then
    echo "dock-island-border: style.css not found: $STYLE" >&2
    exit 1
fi
# Write to style.css line 49: start/trash icon border-color
# Line 49 contains:  border-color: @<token>; /* CC border picker → dock-island-border.sh */
sed -i "49s/\(border-color:[[:space:]]*\)@[a-zA-Z0-9_]*/\1@${gtk}/" "$STYLE"
# Hot-reload the dock (SIGUSR2 / signal 12)
pkill -SIGUSR2 -f 'gjs dock-main.js' 2>/dev/null || pkill -12 -f 'gjs dock-main.js' 2>/dev/null || true
echo "$gtk"

