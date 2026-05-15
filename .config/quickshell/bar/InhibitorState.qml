pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared idle-inhibitor state.
//
// The IdleInhibitor Wayland protocol object lives in InhibitorAnchor (shell.qml),
// which is always mapped.  This singleton holds the single source of truth for
// whether the inhibitor is active and persists it to disk so the choice survives
// Quickshell restarts.
Item {
    id: sm

    property bool active: false
    readonly property string _stateFile:
        Quickshell.env("HOME") + "/.config/hyprcandy/inhibitor-state"

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
            "mkdir -p \"$(dirname \"$1\")\" && echo \"$2\" > \"$1\"",
            "--", sm._stateFile, sm.active ? "enabled" : "disabled"]
        running: false
    }
}
