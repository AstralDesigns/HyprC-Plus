#!/bin/bash
# Toggle start menu via the bar's in-process StartMenuState.

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

if pgrep -f "qs -c bar" > /dev/null; then
    qs ipc -c bar --newest call bar toggleStartMenu
else
    qs -c bar &
    for i in $(seq 1 20); do
        sleep 0.1
        if qs ipc -c bar --newest call bar toggleStartMenu 2>/dev/null; then
            break
        fi
    done
fi
