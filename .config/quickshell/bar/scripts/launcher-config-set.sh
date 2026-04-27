#!/bin/bash
# App Launcher setting writer — edits launcherConfig.js in-place, then
# respawns the launcher (if it was open) so changes take effect immediately.
# Usage: launcher-config-set.sh <key> <value>
CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/launcherConfig.js"
TOGGLE="$HOME/.hyprcandy/GJS/hyprcandydock/toggle-app-launcher.sh"

key="$1"
value="$2"

if [ -z "$key" ] || [ -z "$value" ] || [ ! -f "$CONFIG" ]; then
    exit 1
fi

# Write the new value — matches both integer and decimal fields
sed -i "s/\(${key}:[[:space:]]*\)[0-9][0-9.]*/\1${value}/" "$CONFIG"

# If the launcher is currently running, kill it and respawn it with the new config.
# If it is not running (user has it closed), do nothing — it will pick up the new
# values the next time it opens.
if pgrep -f 'gjs.*app-launcher.js' > /dev/null 2>&1; then
    pkill -f 'gjs.*app-launcher.js' 2>/dev/null || true
    # Brief pause so the old process fully exits before we relaunch
    sleep 0.15
    # Relaunch via the toggle script so LD_PRELOAD and cwd are set correctly
    if [ -x "$TOGGLE" ]; then
        setsid bash "$TOGGLE" </dev/null >/dev/null 2>&1 &
    fi
fi
