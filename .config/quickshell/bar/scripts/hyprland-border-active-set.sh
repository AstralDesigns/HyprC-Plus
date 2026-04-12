#!/bin/bash
# Set active border color/variable in hyprviz.conf

HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
value="${1:-$source_color}"

[ -f "$HYPR_CONF" ] || exit 1

sed -i "s/^\([[:space:]]*\)col\.active_border = .*/\1col.active_border = $value/" "$HYPR_CONF"
hyprctl reload 2>/dev/null || true
