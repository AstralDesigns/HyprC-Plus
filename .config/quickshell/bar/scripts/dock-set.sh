#!/bin/bash
# Dock setting writer
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"

key="$1"
value="$2"

# marginFromEdge writes margin_from_edge to the [dock] section of hyprcandy-bar.conf
# and hot-reloads the dock via SIGUSR2 (signal 12).
# Kept in a dedicated Process (_dockMarginWrite) in QML so it never contends
# with the Hyprland Lua state writer that runs through _confWriteProc.
if [ "$key" = "marginFromEdge" ]; then
    f="$HOME/.config/hyprcandy/hyprcandy-bar.conf"
    mkdir -p "$(dirname "$f")"

    # Create bare conf if the file doesn't exist yet
    [ -f "$f" ] || printf '[bar]\nautohide=false\nautohide_delay=5\n\n[dock]\nautohide=false\nautohide_delay=5\nlayer=top\nmargin_from_edge=6\n' > "$f"

    # Create [dock] section if the file exists but has no [dock] header
    grep -q '^\[dock\]' "$f" || printf '\n[dock]\nautohide=false\nautohide_delay=5\nlayer=top\nmargin_from_edge=6\n' >> "$f"

    # Insert margin_from_edge under [dock] if the key is missing
    grep -q '^margin_from_edge=' "$f" || sed -i '/^\[dock\]/a margin_from_edge=6' "$f"

    # Replace the value
    sed -i "/^\[dock\]/,/^\[/{s/^margin_from_edge=.*/margin_from_edge=${value}/}" "$f"

    pkill -12 -f 'gjs dock-main.js' 2>/dev/null || true
    exit 0
fi

if [ -n "$key" ] && [ -n "$value" ] && [ -f "$CONFIG" ]; then
    case "$key" in
        rectBgStyle)
            # String key — replace the quoted value
            sed -i "s/rectBgStyle: '[^']*'/rectBgStyle: '${value}'/" "$CONFIG"
            ;;
        *)
            # Numeric keys
            sed -i "s/${key}: [0-9]*/${key}: ${value}/" "$CONFIG"
            ;;
    esac
    pkill -SIGUSR2 -f 'gjs dock-main.js'
fi
