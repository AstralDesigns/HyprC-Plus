#!/bin/bash
# Dock setting writer (numeric + rectBgStyle — border color uses dock-border.sh)
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"

key="$1"
value="$2"

_dock_hot_reload() {
    pkill -SIGUSR2 -f 'gjs dock-main.js' 2>/dev/null || pkill -12 -f 'gjs dock-main.js' 2>/dev/null || true
}

# marginFromEdge writes margin_from_edge to the [dock] section of hyprcandy-bar.conf
# and hot-reloads the dock via SIGUSR2 (signal 12).
# Kept in a dedicated Process (_dockMarginWrite) in QML so it never contends
# with the Hyprland Lua state writer that runs through _confWriteProc.
if [ "$key" = "marginFromEdge" ]; then
    f="$HOME/.config/hyprcandy/hyprcandy-bar.conf"
    mkdir -p "$(dirname "$f")"

    [ -f "$f" ] || printf '[bar]\nautohide=false\nautohide_delay=5\n\n[dock]\nautohide=false\nautohide_delay=5\nlayer=top\nmargin_from_edge=6\n' > "$f"
    grep -q '^\[dock\]' "$f" || printf '\n[dock]\nautohide=false\nautohide_delay=5\nlayer=top\nmargin_from_edge=6\n' >> "$f"
    grep -q '^margin_from_edge=' "$f" || sed -i '/^\[dock\]/a margin_from_edge=6' "$f"
    sed -i "/^\[dock\]/,/^\[/{s/^margin_from_edge=.*/margin_from_edge=${value}/}" "$f"

    _dock_hot_reload
    exit 0
fi

if [ -z "$key" ] || [ -z "$value" ]; then
    echo "dock-set: usage: dock-set.sh <key> <value>" >&2
    exit 1
fi

if [ ! -f "$CONFIG" ]; then
    echo "dock-set: config not found: $CONFIG" >&2
    exit 1
fi

case "$key" in
    rectBgStyle)
        if grep -q 'rectBgStyle:' "$CONFIG"; then
            sed -i "s/^\([[:space:]]*rectBgStyle:\)[[:space:]]*'[^']*'/\1 '${value}'/" "$CONFIG"
        else
            sed -i "/innerPadding:/a\\    rectBgStyle: '${value}', // @HCD:rectBgStyle" "$CONFIG"
        fi
        _dock_hot_reload
        ;;
    *)
        if grep -q "^[[:space:]]*${key}:" "$CONFIG"; then
            sed -i "s/^\([[:space:]]*${key}:\)[[:space:]]*[0-9]*/\1 ${value}/" "$CONFIG"
        fi
        _dock_hot_reload
        ;;
esac
