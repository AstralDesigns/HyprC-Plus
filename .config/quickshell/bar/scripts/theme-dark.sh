#!/bin/bash
# Theme setter - Dark mode with scheme
WI="$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh"
G3="$HOME/.config/matugen/templates/gtk3.css"
G4="$HOME/.config/matugen/templates/gtk4.css"
SCHEME="${1:-scheme-content}"

# Switch to dark mode
sed -i 's/-m light/-m dark/g' "$WI"

# Update scheme in wallpaper integration
sed -i "s/--type scheme-[^ ]*/--type ${SCHEME}/" "$WI"

# GTK3 dialog colors (dark mode variants)
if [ "$SCHEME" = "scheme-fidelity" ] || [ "$SCHEME" = "scheme-monochrome" ]; then
    sed -i 's/@on_secondary/@on_primary_fixed_variant/g' "$G3"
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_primary_fixed_variant;/' "$G3"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' "$G3"
    sed -i 's/@on_primary_fixed_variant/@on_secondary/g' "$G4"
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_secondary;/' "$G4"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' "$G4"
else
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_secondary;/' "$G3"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' "$G3"
    sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_secondary;/' "$G4"
    sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' "$G4"
fi

# Trigger wallpaper integration
bash "$WI"

# Save scheme state
echo "$SCHEME" > "$HOME/.config/hyprcandy/matugen-state"
