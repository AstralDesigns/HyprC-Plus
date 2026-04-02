#!/bin/bash

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# If the wallpaper picker is already running, just toggle visibility via IPC.
# If not, start it (hidden) and then open it.
if pgrep -f "qs -c wallpaper" > /dev/null; then
    pkill -f "qs -c wallpaper"
else
    qs -c wallpaper &
    # Wait for IPC socket to be ready, then open
    for i in $(seq 1 20); do
        sleep 0.1
        if qs ipc -c wallpaper call wallpaper open 2>/dev/null; then
            break
        fi
    done
fi
