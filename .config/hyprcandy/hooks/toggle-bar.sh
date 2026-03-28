#!/bin/bash

if pgrep -f "/usr/bin/waybar" > /dev/null; then
    # If running, kill it
    systemctl --user stop waybar.service
    pkill -x waybar
else
    # If not running, start it
    systemctl --user restart waybar.service
    bash "$HOME/.config/waybar/scripts/idle-inhibitor.sh"
fi
