#!/bin/bash
# Border width ± adjustment — writes to ~/.config/hypr/hyprviz.conf and reloads.
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
delta="${1:--1}"

[ -f "$HYPR_CONF" ] || exit 1

v=$(grep -m1 'border_size[[:space:]]*=' "$HYPR_CONF" | grep -oP '[0-9]+' | head -1)
[ -n "$v" ] || exit 1

nv=$(( v + delta ))
[ "$nv" -lt 0 ] && nv=0
[ "$nv" -gt 20 ] && nv=20

sed -i "/general[[:space:]]*{/,/}/{s/\(^[[:space:]]*border_size[[:space:]]*=[[:space:]]*\)[0-9]*/\1${nv}/}" "$HYPR_CONF"
hyprctl reload
echo "$nv"
