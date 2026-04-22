#!/bin/bash

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# If the bar instance is already running, just toggle the control center via IPC.
# If not, start the bar first, then toggle.
if pgrep -f "qs -c bar" > /dev/null; then
    qs ipc -c bar call bar toggleControlCenter
else
    qs -c bar &
    sleep 1
    qs ipc -c bar call bar toggleControlCenter
fi
