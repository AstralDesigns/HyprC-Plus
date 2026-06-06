#!/bin/bash
# Write dock window border color (GTK4 matugen @name) into style.css and hot-reload.
# Usage: dock-border.sh <gtk_name>     e.g. primary, on_secondary, outline_variant
#        dock-border.sh @primary      (@ prefix is stripped)

STYLE="$HOME/.hyprcandy/GJS/hyprcandydock/style.css"
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"

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

# Primary write target — GTK reads @name from style.css
sed -i "s/\(border-color:[[:space:]]*\)@[a-zA-Z0-9_]*/\1@${gtk}/" "$STYLE"

# Mirror into config.js for @HCD hot-reload metadata (optional, not the visual source)
if [ -f "$CONFIG" ] && grep -q 'borderColorVar:' "$CONFIG"; then
    sed -i "s/^\([[:space:]]*borderColorVar:\)[[:space:]]*'[^']*'/\1 '${gtk}'/" "$CONFIG"
fi

pkill -SIGUSR2 -f 'gjs dock-main.js' 2>/dev/null || pkill -12 -f 'gjs dock-main.js' 2>/dev/null || true
echo "$gtk"
