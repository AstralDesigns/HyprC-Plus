pragma Singleton

import QtQuick
import Quickshell.Io

Item {
    id: state
    property bool active: false

    // Watch for /tmp/qs-candylock-trans.lock created by candylock.sh
    Process {
        id: watchProc
        command: ["bash", "-c",
            "F=/tmp/qs-candylock-trans.lock; " +
            "while true; do " +
            "  if [ -f \"$F\" ]; then echo 1; else echo 0; fi; " +
            "  inotifywait -q -e create,delete,attrib,modify /tmp --include 'qs-candylock-trans.lock' 2>/dev/null || sleep 0.15; " +
            "done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const isAct = line.trim() === "1"
                if (state.active !== isAct) state.active = isAct
            }
        }
        Component.onCompleted: running = true
    }

    // Safety fallback: auto-deactivate after 12s if process terminated abnormally
    Timer {
        id: safetyTimeout
        interval: 12000
        repeat: false
        running: state.active
        onTriggered: {
            state.active = false
        }
    }
}
