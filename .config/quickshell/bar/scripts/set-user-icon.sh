#!/bin/bash
# User icon setter - sets both CC and startmenu icons simultaneously
# Uses exact same magick logic for both

SRC="$1"
USER_ICON="$HOME/.config/hyprcandy/user-icon.png"
SM_ICON="/tmp/qs_sm_user_circle.png"

if [ -n "$SRC" ] && [ -f "$SRC" ]; then
    mkdir -p "$HOME/.config/hyprcandy"
    
    # Create user icon (96x96 circle) - same for both CC and startmenu
    magick "$SRC" -resize 96x96^ -gravity center -extent 96x96 \
        \( +clone -alpha extract -fill black -colorize 100 \
           -fill white -draw 'circle 48,48 48,0' \) \
        -alpha off -compose CopyOpacity -composite -strip \
        "$USER_ICON"
    
    # Create startmenu processed icon using EXACT same magick command
    # This ensures both icons are identical
    magick "$USER_ICON" -resize 96x96^ -gravity center -extent 96x96 \
        \( +clone -alpha extract -fill black -colorize 100 \
           -fill white -draw 'circle 48,48 48,0' \) \
        -alpha off -compose CopyOpacity -composite -strip \
        "$SM_ICON"
fi
