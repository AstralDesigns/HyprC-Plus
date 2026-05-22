pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared idle-inhibitor state.
//
// The IdleInhibitor Wayland protocol object lives in InhibitorAnchor (shell.qml),
// which is always mapped.  This singleton holds the single source of truth for
// whether the inhibitor is active and persists it to disk so the choice survives
// Quickshell restarts within the same session.
//
// State is stored in /tmp so it is automatically cleared on logout/reboot/shutdown,
// ensuring the toggle always starts inactive on a new session — matching the
// compositor which always resets inhibition on restart.
Item {
    id: sm

    property bool active: false
    readonly property string _stateFile:
        "/tmp/hyprcandy-inhibitor-state"

    // Called once by InhibitorAnchor at startup
    function _load() { _readProc.reload() }

    function toggle() {
        sm.active = !sm.active
        _writeProc.running = true
    }

    // ── Persistence ─────────────────────────────────────────────────────────
    FileView {
        id: _readProc
        path: sm._stateFile
        onLoaded: sm.active = text().trim() === "enabled"
    }

    Process {
        id: _writeProc
        command: ["bash", "-c",
            "echo \"$2\" > \"$1\"",
            "--", sm._stateFile, sm.active ? "enabled" : "disabled"]
        running: false
    }
}
