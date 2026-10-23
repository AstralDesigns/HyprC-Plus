#!/bin/bash

GTK_FILE="$HOME/.config/gtk-3.0/settings.ini"
ICON_HOOK="$HOME/.config/hyprcandy/hooks/update_icon_theme.sh"

while [ ! -f "$GTK_FILE" ]; do sleep 1; done
"$ICON_HOOK"

# Track previous values to avoid redundant hook calls
PREV_ICON=$(grep "^gtk-icon-theme-name=" "$GTK_FILE" | cut -d'=' -f2-)

inotifywait -m -e modify "$GTK_FILE" | while read -r path event file; do
    CUR_ICON=$(grep "^gtk-icon-theme-name=" "$GTK_FILE" | cut -d'=' -f2-)

    if [ "$CUR_ICON" != "$PREV_ICON" ]; then
        "$ICON_HOOK"
        PREV_ICON="$CUR_ICON"
    fi
done
