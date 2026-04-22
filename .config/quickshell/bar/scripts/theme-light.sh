#!/bin/bash
# Theme setter - Light mode
WI="$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh"
G3="$HOME/.config/matugen/templates/gtk3.css"
G4="$HOME/.config/matugen/templates/gtk4.css"

# Switch to light mode
sed -i 's/-m dark/-m light/g' "$WI"

# GTK3 dialog colors
sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @primary_fixed_dim;/' "$G3"
sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @inverse_primary;/' "$G3"

# GTK4 dialog colors
sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @primary_fixed_dim;/' "$G4"
sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @inverse_primary;/' "$G4"

# Trigger wallpaper integration
bash "$WI"
