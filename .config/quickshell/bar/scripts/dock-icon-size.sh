#!/bin/bash
# Dock icon size setter.
# Writes the new size to config.js then restarts the dock (toggle × 2 with a
# 1 s gap) because Gtk.Image pixel_size is baked in at construction time and
# cannot be changed via SIGUSR2 hot-reload.

CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"

size="$1"
[ -n "$size" ] && [ -f "$CONFIG" ] || exit 0

# Write new icon size
sed -i "s/appIconSize: [0-9]*/appIconSize: ${size}/" "$CONFIG"

exit 0
