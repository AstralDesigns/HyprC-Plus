#!/bin/bash
HYPR="$HOME/.config/hypr/hyprviz.conf"
XRAY="$HOME/.config/hyprcandy/settings/xray-on"
if [ ! -f "$XRAY" ]; then
    sed -i "s/xray = false/xray = true/" "$HYPR"
    sed -i "s/xray off/xray on/" "$HYPR"
    hyprctl reload
    touch "$XRAY"
    #notify-send "Opacity" "Decreased" -t 2000
else
    sed -i "s/xray = true/xray = false/" "$HYPR"
    sed -i "s/xray on/xray off/" "$HYPR"
    hyprctl reload
    rm "$XRAY"
    #notify-send "Opacity" "Increased" -t 2000
fi
