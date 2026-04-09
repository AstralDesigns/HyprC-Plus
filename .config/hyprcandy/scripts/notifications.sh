#!/bin/bash
# Toggle notification history via the bar's in-process NotificationsState.

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

if pgrep -f "qs -c bar" > /dev/null; then
    qs ipc -c bar --newest call bar toggleNotifications
else
    qs -c bar &
    for i in $(seq 1 20); do
        sleep 0.1
        if qs ipc -c bar --newest call bar toggleNotifications 2>/dev/null; then
            break
        fi
    done
fi
