#!/usr/bin/env bash
# cava-autostart.sh — Start the cava manager on Hyprland startup.
# Add to hyprland.conf:  exec-once = ~/.config/waybar/scripts/cava-autostart.sh

CAVA="$HOME/.config/waybar/scripts/cava.py"

# Start the persistent manager (no-op if already running)
python3 "$CAVA" manager &
disown

# Give it a moment to create the socket, then connect as a waybar client.
# The client process is what feeds data to the waybar cava modules — it keeps
# running in the background and reconnects automatically if waybar restarts.
sleep 2 && python3 "$CAVA" waybar --json --left --width 10 \
    --bar '⣀⣄⣤⣦⣶⣷⣿' --transparent-when-inactive &
disown
