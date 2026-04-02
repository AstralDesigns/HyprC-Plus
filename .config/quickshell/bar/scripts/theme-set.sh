#!/bin/bash
# theme-set.sh — unified theme setter
# Replaces theme-dark.sh + theme-light.sh.
# Mirrors the exact GJS candy-utils.js Light / Dark / else three-branch logic
# for GTK3 and GTK4 files only (hyprcandy-dock hot-reloads via GTK4 color watch;
# waybar, swaync, nwg-dock-hyprland are no longer written to from here).
#
# Usage:
#   theme-set.sh light                 → Light mode (any scheme)
#   theme-set.sh scheme-fidelity       → Dark, Fidelity branch
#   theme-set.sh scheme-monochrome     → Dark, Monochrome branch
#   theme-set.sh scheme-content        → Dark, else branch
#   theme-set.sh scheme-expressive     → Dark, else branch
#   (etc. — anything not "light", "scheme-fidelity", "scheme-monochrome")

WI="$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh"
G3="$HOME/.config/matugen/templates/gtk3.css"
G4="$HOME/.config/matugen/templates/gtk4.css"
SCHEME="${1:-scheme-content}"

# ── Light ─────────────────────────────────────────────────────────────────────
if [ "$SCHEME" = "light" ]; then
    sed -i 's/-m dark/-m light/g' "$WI"

    # GTK3
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @primary_fixed_dim;/' "$G3"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @inverse_primary;/'  "$G3"
    # GTK4
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @primary_fixed_dim;/' "$G4"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @inverse_primary;/'  "$G4"

# ── Dark — Fidelity / Monochrome ──────────────────────────────────────────────
elif [ "$SCHEME" = "scheme-fidelity" ] || [ "$SCHEME" = "scheme-monochrome" ]; then
    sed -i 's/-m light/-m dark/g' "$WI"
    sed -i "s/--type scheme-[^ ]*/--type ${SCHEME}/" "$WI"

    # GTK3: global swap @on_secondary → @on_primary_fixed_variant, then dialog colors
    sed -i 's/@on_secondary/@on_primary_fixed_variant/g' "$G3"
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_primary_fixed_variant;/' "$G3"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/'                  "$G3"
    # GTK4: same
    sed -i 's/@on_secondary/@on_primary_fixed_variant/g' "$G4"
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_primary_fixed_variant;/' "$G4"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/'                  "$G4"

# ── Dark — all other schemes (scheme-content, scheme-expressive, scheme-neutral, …) ──
else
    sed -i 's/-m light/-m dark/g' "$WI"
    sed -i "s/--type scheme-[^ ]*/--type ${SCHEME}/" "$WI"

    # GTK3: global swap @on_primary_fixed_variant → @on_secondary, then dialog colors
    sed -i 's/@on_primary_fixed_variant/@on_secondary/g' "$G3"
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_secondary;/' "$G3"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/'      "$G3"
    # GTK4: same
    sed -i 's/@on_primary_fixed_variant/@on_secondary/g' "$G4"
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_secondary;/' "$G4"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/'      "$G4"
fi

# Trigger wallpaper integration (runs matugen → rewrites GTK / Hyprland colors)
bash "$WI"

# Persist scheme state for restart / reload
echo "$SCHEME" > "$HOME/.config/hyprcandy/matugen-state"
