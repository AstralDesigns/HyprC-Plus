#!/bin/bash
# Inner gaps ± adjustment — writes to ~/.config/hypr/hyprviz.conf and reloads.
HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
delta="${1:--1}"

[ -f "$HYPR_CONF" ] || exit 1

v=$(grep -m1 'gaps_in[[:space:]]*=' "$HYPR_CONF" | grep -oP '[0-9]+' | head -1)
[ -n "$v" ] || exit 1

nv=$(( v + delta ))
[ "$nv" -lt 0 ] && nv=0
[ "$nv" -gt 100 ] && nv=100

sed -i "/general[[:space:]]*{/,/}/{s/\(^[[:space:]]*gaps_in[[:space:]]*=[[:space:]]*\)[0-9]*/\1${nv}/}" "$HYPR_CONF"
hyprctl reload
echo "$nv"
