#!/bin/bash
# Lua-aware visual adjust: persist through the CC state helper (hyprcandy-bar.conf
# + hyprviz-state.lua), then reload. The legacy hyprviz.conf + `hyprctl keyword`
# path never persisted on Hyprland 0.55+ Lua configs (file absent, keyword invalid).
HELPER="$HOME/.config/quickshell/bar/scripts/hyprland-lua-state.sh"
NEW_VALUE=$("$HELPER" adjust gaps_out +1)
hyprctl reload

echo "🔼 Gaps OUT increased: gaps_out=$NEW_VALUE"
notify-send "Gaps OUT Increased" "gaps_out: $NEW_VALUE" -t 2000
