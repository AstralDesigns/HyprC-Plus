#!/bin/bash

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# If the notifications instance is already running, just toggle it.
# If not, start it and then toggle open.
if pgrep -f "qs -c notifications" > /dev/null; then
    qs ipc -c notifications call notifications toggle
else
    qs -c notifications &
    # Wait for the IPC socket to be ready before calling toggle
    for i in $(seq 1 20); do
        sleep 0.1
        if qs ipc -c notifications call notifications toggle 2>/dev/null; then
            break
        fi
    done
fi
