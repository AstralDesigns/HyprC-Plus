#!/bin/bash

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# If the control center instance is already running, just toggle it.
# If not, start it and then toggle open.
if pgrep -f "qs -c controlcenter" > /dev/null; then
    qs ipc -c controlcenter call controlcenter toggleVisibility
else
    qs -c controlcenter &
    # Brief pause so the IPC target registers, then show it
    sleep 0.3
    qs ipc -c controlcenter call controlcenter toggleVisibility
fi
