#!/bin/bash

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# If the startmenu instance is already running, just toggle it.
# If not, start it and then toggle open.
if pgrep -f "qs -c startmenu" > /dev/null; then
    qs ipc -c startmenu call startmenu toggle
else
    qs -c startmenu &
    # Wait for the IPC socket to be ready before calling toggle
    for i in $(seq 1 20); do
        sleep 0.1
        if qs ipc -c startmenu call startmenu toggle 2>/dev/null; then
            break
        fi
    done
fi
