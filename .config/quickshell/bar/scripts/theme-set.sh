#!/bin/bash
# theme-set.sh — unified theme setter
# Replaces theme-dark.sh + theme-light.sh.
# Mirrors the exact GJS candy-utils.js Light / Dark / else three-branch logic
# for GTK3 and GTK4 files only (hyprcandy-dock hot-reloads via GTK4 color watch;
# waybar, swaync, nwg-dock-hyprland are no longer written to from here).
#
# Usage:
#   theme-set.sh light                 → Light mode (any scheme)
#   theme-set.sh scheme-smart          → Adaptive (auo-selection of schemes based on background)
#   theme-set.sh scheme-content        → Dark, else branch
#   theme-set.sh scheme-expressive     → Dark, else branch
#   (etc. — anything not "light")

WI="$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh"
G3="$HOME/.config/matugen/templates/gtk3.css"
G4="$HOME/.config/matugen/templates/gtk4.css"
WL="$HOME/.config/wallust/wallust.toml"
SCHEME="${1:-scheme-content}"

# ── Light ─────────────────────────────────────────────────────────────────────
if [ "$SCHEME" = "light" ]; then
    sed -i 's/wal -s -t -i "$bg_path" -n --cols16 darken/wal -s -t -l -i "$bg_path" -n --cols16 lighten/g' "$WI"
    sed -i 's/wal -s -t -i "$bg_path" -n --cols16 foxify-darken/wal -s -t -l -i "$bg_path" -n --cols16 lighten/g' "$WI"
    sed -i 's/palette = "softdark"/palette = "softlight"/g' "$WL"
    sed -i 's/-m dark/-m light/g' "$WI"
    sed -i 's/-m smart/-m light/g' "$WI"

# ── Smart  ──
elif [ "$SCHEME" = "scheme-smart" ]; then
    sed -i 's/wal -s -t -l -i "$bg_path" -n --cols16 lighten/wal -s -t -i "$bg_path" -n --cols16 foxify-darken/g' "$WI"
    sed -i 's/wal -s -t -i "$bg_path" -n --cols16 darken/wal -s -t -i "$bg_path" -n --cols16 foxify-darken/g' "$WI"
    sed -i 's/palette = "softlight"/palette = "softdark"/g' "$WL"
    sed -i 's/-m light/-m smart/g' "$WI"
    sed -i 's/-m dark/-m smart/g' "$WI"
    sed -i "s/--type scheme-[^ ]*/--type scheme-smart/" "$WI"

# ── Dark — all other schemes ──
else
    sed -i 's/wal -s -t -l -i "$bg_path" -n --cols16 lighten/wal -s -t -i "$bg_path" -n --cols16 darken/g' "$WI"
    sed -i 's/wal -s -t -i "$bg_path" -n --cols16 foxify-darken/wal -s -t -i "$bg_path" -n --cols16 darken/g' "$WI"
    sed -i 's/palette = "softlight"/palette = "softdark"/g' "$WL"
    sed -i 's/-m light/-m dark/g' "$WI"
    sed -i 's/-m smart/-m dark/g' "$WI"
    sed -i "s/--type scheme-[^ ]*/--type ${SCHEME}/" "$WI"
fi

# Trigger wallpaper integration (runs matugen → rewrites GTK / Hyprland colors)
bash "$WI"

# Persist scheme state for restart / reload
echo "$SCHEME" > "$HOME/.config/hyprcandy/matugen-state"
