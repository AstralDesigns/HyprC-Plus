#!/bin/bash
# Set dock START/TRASH icon island border color, width, and alpha.
# • Color token → written to config.js AND style.css (for cold-start fallback)
# • Width       → written to config.js AND style.css (for cold-start fallback)
# • Alpha       → written to config.js (rendered live as rgba() by dynamic CSS)
#
# Usage:
#   dock-island-border.sh <gtk_name>    e.g. primary, on_secondary, color0, @primary
#   dock-island-border.sh width <N>     e.g. width 2
#   dock-island-border.sh alpha <A>     e.g. alpha 0.5

STYLE="$HOME/.hyprcandy/GJS/hyprcandydock/style.css"
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"

_dock_hot_reload() {
    pkill -SIGUSR2 -f 'gjs dock-main.js' 2>/dev/null || pkill -12 -f 'gjs dock-main.js' 2>/dev/null || true
}

cmd="${1#@}"
cmd="${cmd#\$}"

if [ -z "$cmd" ]; then
    echo "dock-island-border: usage: dock-island-border.sh <gtk_name> | width <N> | alpha <A>" >&2
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "dock-island-border: config.js not found: $CONFIG" >&2; exit 1
fi

if [ "$cmd" = "width" ]; then
    w="$2"
    [ -z "$w" ] && exit 1
    if grep -q 'islandBorderWidth:' "$CONFIG"; then
        sed -i "s/^\([[:space:]]*islandBorderWidth:\)[[:space:]]*[0-9.]*/\1 ${w}/" "$CONFIG"
    else
        sed -i "/borderColorVar:/a\\    islandBorderWidth: ${w}, // @HCD:islandBorderWidth" "$CONFIG"
    fi
    # Also sync style.css border-width for cold-start fallback
    if [ -f "$STYLE" ]; then
        awk -v w="${w}" '
            /#start-icon/             { in_block=1 }
            in_block && /^\s*\}/      { in_block=0 }
            in_block && /border-width:/ { sub(/border-width:[[:space:]]*[0-9.]+px/, "border-width: " w "px") }
            { print }
        ' "$STYLE" > "${STYLE}.tmp" && mv "${STYLE}.tmp" "$STYLE"
    fi
    _dock_hot_reload; echo "$w"; exit 0
fi

if [ "$cmd" = "alpha" ]; then
    a="$2"
    [ -z "$a" ] && exit 1
    if grep -q 'islandBorderAlpha:' "$CONFIG"; then
        sed -i "s/^\([[:space:]]*islandBorderAlpha:\)[[:space:]]*[0-9.]*/\1 ${a}/" "$CONFIG"
    else
        sed -i "/islandBorderWidth:/a\\    islandBorderAlpha: ${a}, // @HCD:islandBorderAlpha" "$CONFIG"
    fi
    _dock_hot_reload; echo "$a"; exit 0
fi

# Default: GTK color token name — write to config.js AND style.css
gtk="$cmd"
if grep -q 'islandBorderColorVar:' "$CONFIG"; then
    sed -i "s/^\([[:space:]]*islandBorderColorVar:\)[[:space:]]*'[^']*'/\1 '${gtk}'/" "$CONFIG"
else
    sed -i "/islandBorderAlpha:/a\\    islandBorderColorVar: '${gtk}', // @HCD:islandBorderColorVar" "$CONFIG"
fi

# Sync style.css border-color (cold-start fallback) using awk for robustness
if [ -f "$STYLE" ]; then
    awk -v gtk="${gtk}" '
        /#start-icon/             { in_block=1 }
        in_block && /^\s*\}/      { in_block=0 }
        in_block && /border-color:/ { sub(/border-color:[[:space:]]*@[a-zA-Z0-9_]*/, "border-color: @" gtk) }
        { print }
    ' "$STYLE" > "${STYLE}.tmp" && mv "${STYLE}.tmp" "$STYLE"
fi

_dock_hot_reload
echo "$gtk"
