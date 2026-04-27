#!/bin/bash

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# If the bar instance is already running, just toggle it.
# If not, start it and then toggle open.
if pgrep -f "qs -c bar" > /dev/null; then
    qs ipc -c bar call bar toggleVisibility
else
    qs -c bar &
fi
