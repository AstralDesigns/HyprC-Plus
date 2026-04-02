#!/bin/bash
# Blur size ± adjustment — writes to ~/.config/hypr/hyprviz.conf and reloads.
# Uses an awk state machine to locate 'size = N' strictly inside a blur {}
# block, so it handles Hyprland's mixed-indentation style and won't touch
# other 'size' keys (shadow, etc.).

HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
delta="${1:--1}"

[ -f "$HYPR_CONF" ] || exit 1

# Extract current value of 'size' inside the first blur {} block
v=$(awk '
    /blur[[:space:]]*\{/   { inblur=1; next }
    inblur && /^\s*\}/ { inblur=0; next }
    inblur && /^\s*size[[:space:]]*=/ {
        match($0, /[0-9]+/)
        print substr($0, RSTART, RLENGTH)
        exit
    }
' "$HYPR_CONF")

[ -n "$v" ] || exit 1

nv=$(( v + delta ))
[ "$nv" -lt 0 ] && nv=0

# Replace 'size = <old>' → 'size = <new>' inside blur blocks only.
# The sed address range /blur {/,/}/ matches each blur block; within it
# we replace the size line. Using the exact old value avoids false matches.
sed -i "/blur[[:space:]]*{/,/}/{s/\(^\s*size[[:space:]]*=\s*\)${v}\b/\1${nv}/}" "$HYPR_CONF"
hyprctl reload
