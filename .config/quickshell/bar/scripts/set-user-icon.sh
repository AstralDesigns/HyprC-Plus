#!/bin/bash
# User icon setter - sets both CC and startmenu icons simultaneously
#
# Usage:
#   set-user-icon.sh <src> [x_offset] [y_offset]
#
# With no offsets (or 0 0): crops from the centre (legacy behaviour).
# With offsets: uses -gravity NorthWest so the caller can pan the image
# to any desired region.  Offsets are pixel coordinates into the image
# *after* it has been scaled to cover 96×96 (i.e. -resize 96x96^).
# The crop window is always 96×96.

SRC="$1"
X_OFF="${2:-}"   # optional; empty → centre gravity (legacy)
Y_OFF="${3:-}"

USER_ICON="$HOME/.config/hyprcandy/user-icon.png"
SM_ICON="/tmp/qs_sm_user_circle.png"

if [ -n "$SRC" ] && [ -f "$SRC" ]; then
    mkdir -p "$HOME/.config/hyprcandy"

    # Choose crop strategy based on whether offsets were supplied
    if [ -n "$X_OFF" ] && [ -n "$Y_OFF" ]; then
        # Caller-specified crop origin (NorthWest anchor)
        # Clamp offsets to non-negative integers
        X_OFF=$(( X_OFF < 0 ? 0 : X_OFF ))
        Y_OFF=$(( Y_OFF < 0 ? 0 : Y_OFF ))
        CROP_GRAVITY="-gravity NorthWest"
        CROP_GEOM="96x96+${X_OFF}+${Y_OFF}"
    else
        # Legacy: centre gravity, zero offset
        CROP_GRAVITY="-gravity center"
        CROP_GEOM="96x96"
    fi

    # Build the first frame selector for GIF/animated sources
    SRC_ARG="$SRC"
    case "${SRC,,}" in
        *.gif) SRC_ARG="${SRC}[0]" ;;
    esac

    # Create user icon (96×96 circular PNG)
    magick "$SRC_ARG" -resize 96x96^ $CROP_GRAVITY -extent $CROP_GEOM \
        \( +clone -alpha extract -fill black -colorize 100 \
           -fill white -draw 'circle 48,48 48,0' \) \
        -alpha off -compose CopyOpacity -composite -strip \
        "$USER_ICON"

    # Mirror to the startmenu cache (re-apply circle mask to avoid double-clipping)
    magick "$USER_ICON" \
        \( +clone -alpha extract -fill black -colorize 100 \
           -fill white -draw 'circle 48,48 48,0' \) \
        -alpha off -compose CopyOpacity -composite -strip \
        "$SM_ICON"
fi
