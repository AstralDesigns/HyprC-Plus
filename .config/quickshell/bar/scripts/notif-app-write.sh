#!/bin/bash
# Write ~/.config/notif-running-apps from arguments.
# Each argument is one JSON line. Pass no args to clear the file.
# Usage: notif-app-write.sh [jsonline1 jsonline2 ...]

OUT="$HOME/.config/notif-running-apps"

if [ $# -eq 0 ]; then
    > "$OUT"
else
    printf '%s\n' "$@" > "$OUT"
fi
exit 0
