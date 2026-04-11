#!/bin/bash
# Set inactive border color/variable in hyprviz.conf

HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
value="${1:-$background}"

[ -f "$HYPR_CONF" ] || exit 1

sed -i "s/^\([[:space:]]*\)col\.inactive_border = .*/\1col.inactive_border = $value/" "$HYPR_CONF"
hyprctl reload 2>/dev/null || true
