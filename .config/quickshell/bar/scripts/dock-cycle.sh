#!/bin/bash
# Dock position cycle — fully detaches from the Quickshell process tree so
# the dock is never a child of QS and cannot be killed when CC closes/hides.
#
# setsid creates a new session (new PGID, no controlling terminal) so the
# dock process is unreachable via QS's SIGHUP or process-group cleanup.
# disown removes it from the shell's job table before we exit.

DOCK_DIR="$HOME/.hyprcandy/GJS/hyprcandydock"

setsid bash "$DOCK_DIR/cycle.sh" >/dev/null 2>&1 &
disown $!

exit 0
