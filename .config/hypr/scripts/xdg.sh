#!/bin/bash
# __  ______   ____
# \ \/ /  _ \ / ___|
#  \  /| | | | |  _
#  /  \| |_| | |_| |
# /_/\_\____/ \____|

killall -e xdg-desktop-portal          2>/dev/null

sleep 1

# Stop all managed services cleanly
systemctl --user stop \
    xdg-desktop-portal \

sleep 1

# Start portals in the correct order:

systemctl --user start xdg-desktop-portal
