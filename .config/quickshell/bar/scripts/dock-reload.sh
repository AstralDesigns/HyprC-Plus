#!/bin/bash
# The restart loop is fully detached from the Quickshell process tree via
# setsid + disown so CC hide/show cannot kill the dock mid-restart.

TOGGLE="$HOME/.hyprcandy/GJS/hyprcandydock/toggle.sh"

# Restart dock in a fully detached session
setsid bash -c "bash \"$TOGGLE\"; sleep 1; bash \"$TOGGLE\"" >/dev/null 2>&1 &
disown $!

exit 0
