#!/bin/bash
# Blur passes ± adjustment — writes to ~/.config/hypr/hyprviz.conf and reloads.
# Same awk state-machine approach as hyprland-blur-size.sh to handle
# Hyprland's mixed-indentation blur {} blocks reliably.

HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
delta="${1:--1}"

[ -f "$HYPR_CONF" ] || exit 1

# Extract current value of 'passes' inside the first blur {} block
v=$(awk '
    /blur[[:space:]]*\{/   { inblur=1; next }
    inblur && /^\s*\}/ { inblur=0; next }
    inblur && /^\s*passes[[:space:]]*=/ {
        match($0, /[0-9]+/)
        print substr($0, RSTART, RLENGTH)
        exit
    }
' "$HYPR_CONF")

[ -n "$v" ] || exit 1

nv=$(( v + delta ))
[ "$nv" -lt 0 ] && nv=0

sed -i "/blur[[:space:]]*{/,/}/{s/\(^\s*passes[[:space:]]*=\s*\)${v}\b/\1${nv}/}" "$HYPR_CONF"
hyprctl reload
