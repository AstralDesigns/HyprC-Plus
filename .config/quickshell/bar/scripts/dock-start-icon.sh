#!/bin/bash
# Dock start icon setter — hot-reloads via SIGUSR2 (signal 12).
#
# IMPORTANT: The sed replacement must preserve the trailing // @HCD:startIcon
# comment. dock-main.js reloadConfigFromFile() strRe requires that tag on the
# same line to pick up the new value. Replacing with .* strips it, breaking
# every reload after the first.

CONFIG="$HOME/.hyprcandy/GJS/hyprcandydock/config.js"
icon="$1"
[ -n "$icon" ] && [ -f "$CONFIG" ] || exit 0

# Replace only the quoted value — keep everything after the closing quote+comma intact
# Pattern matches:  startIcon: '<anything>',  and replaces only the '<anything>' part
sed -i "s/\(startIcon: '\)[^']*\('.*\)/\1${icon}\2/" "$CONFIG"

sync

pids=$(pgrep -f 'gjs dock-main.js')
[ -n "$pids" ] && kill -12 $pids

exit 0
