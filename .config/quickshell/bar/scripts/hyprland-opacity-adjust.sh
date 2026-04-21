#!/bin/bash
# Opacity ± adjustment — writes to ~/.config/hypr/hyprviz.conf and reloads.
# Uses awk for float arithmetic (bc may not be installed or may lack -l).
# Targets every active_opacity / inactive_opacity line in the file so both
# decoration blocks stay in sync (hyprland uses the last one, but we keep
# them identical the way the GJS CC did).

HYPR_CONF="$HOME/.config/hypr/hyprviz.conf"
delta="${1:--0.05}"

[ -f "$HYPR_CONF" ] || exit 1

# Read current value from the first matching line
v=$(grep -m1 '^[[:space:]]*active_opacity' "$HYPR_CONF" | grep -oP '[0-9]+\.[0-9]+|[0-9]+' | head -1)
[ -n "$v" ] || exit 1

# Clamp to [0.0, 1.0] with 2 decimal places
nv=$(awk -v v="$v" -v d="$delta" 'BEGIN {
    r = v + d
    if (r < 0) r = 0
    if (r > 1) r = 1
    printf "%.2f", r
}')

sed -i "s/^\([[:space:]]*\)active_opacity = .*/\1active_opacity = $nv/"   "$HYPR_CONF"
sed -i "s/^\([[:space:]]*\)inactive_opacity = .*/\1inactive_opacity = $nv/" "$HYPR_CONF"
hyprctl reload
