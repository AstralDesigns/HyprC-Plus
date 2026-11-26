#!/bin/bash
# Lua-aware visual adjust: persist through the CC state helper (hyprcandy-bar.conf
# + hyprviz-state.lua), then reload. The legacy hyprviz.conf + `hyprctl keyword`
# path never persisted on Hyprland 0.55+ Lua configs (file absent, keyword invalid).
HELPER="$HOME/.config/quickshell/bar/scripts/hyprland-lua-state.sh"
NEW_VALUE=$("$HELPER" adjust rounding +1)
hyprctl reload

echo "🔼 Rounding increased: rounding=$NEW_VALUE"
notify-send "Rounding Increased" "rounding: $NEW_VALUE" -t 2000
