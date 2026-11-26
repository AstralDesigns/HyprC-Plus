#!/bin/bash
# Lua-aware visual adjust: persist through the CC state helper (hyprcandy-bar.conf
# + hyprviz-state.lua), then reload. The legacy hyprviz.conf + `hyprctl keyword`
# path never persisted on Hyprland 0.55+ Lua configs (file absent, keyword invalid).
HELPER="$HOME/.config/quickshell/bar/scripts/hyprland-lua-state.sh"
NEW_VALUE=$("$HELPER" adjust gaps_in +1)
hyprctl reload

echo "🔼 Gaps IN increased: gaps_in=$NEW_VALUE"
notify-send "Gaps IN Increased" "gaps_in: $NEW_VALUE" -t 2000
