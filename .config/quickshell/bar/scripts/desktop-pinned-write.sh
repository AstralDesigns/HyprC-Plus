#!/bin/bash
# Write ~/.config/desktop-pinned from arguments, then signal GJS dock.
# Usage: desktop-pinned-write.sh [class1 class2 ...]
# Each argument is one pinned app class name. Pass no args to clear the file.

PINNED="$HOME/.config/desktop-pinned"

if [ $# -eq 0 ]; then
    > "$PINNED"
else
    printf '%s\n' "$@" > "$PINNED"
fi

pkill -12 -f 'dock-main\.js' 2>/dev/null
exit 0
