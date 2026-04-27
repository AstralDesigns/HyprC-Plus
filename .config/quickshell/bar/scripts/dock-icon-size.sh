#!/bin/bash
# Dock icon size setter.
# Writes the new size to config.js then restarts the dock (toggle × 2 with a
# 1 s gap) because Gtk.Image pixel_size is baked in at construction time and
# cannot be changed via SIGUSR2 hot-reload.
#
# The restart loop is fully detached from the Quickshell process tree via
# setsid + disown so CC hide/show cannot kill the dock mid-restart.

CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"
TOGGLE="$HOME/.hyprcandy/GJS/hyprcandydock/toggle.sh"

size="$1"
[ -n "$size" ] && [ -f "$CONFIG" ] || exit 0

# Write new icon size
sed -i "s/appIconSize: [0-9]*/appIconSize: ${size}/" "$CONFIG"

# Restart dock in a fully detached session
setsid bash -c "bash \"$TOGGLE\"; sleep 1; bash \"$TOGGLE\"" >/dev/null 2>&1 &
disown $!

exit 0
