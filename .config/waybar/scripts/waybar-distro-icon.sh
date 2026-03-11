#!/bin/bash
# Waybar Start/Distro Icon — signal-driven exec script
# candy-utils writes ~/.config/hyprcandy/waybar-start-icon.txt
# then sends `pkill -SIGRTMIN+9 waybar` to trigger a re-run.
# No waybar restart needed.

STATE_FILE="$HOME/.config/hyprcandy/waybar-start-icon.txt"
DEFAULT_ICON=" "   # fallback if state file absent

icon=$(cat "$STATE_FILE" 2>/dev/null | tr -d '\n')
[ -z "$icon" ] && icon="$DEFAULT_ICON"

printf '{"text":"%s","tooltip":"Click: Candy-Settings\\nRight-click: Hyprland-Settings","class":"distro"}\n' "$icon"
