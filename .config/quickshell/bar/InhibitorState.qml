pragma Singleton
import QtQuick
import Quickshell.Io

// Shared idle-inhibitor state.
//
// The IdleInhibitor Wayland protocol object lives in InhibitorAnchor (shell.qml),
// which is always mapped.  This singleton holds the single source of truth for
// whether the inhibitor is active.  Both the bar module (modules/IdleInhibitor.qml)
// and the ControlCenter Hypridle pill drive toggle() below, so they always agree
// and share the same probe/write path.
//
// State persists to [cc-idle-v1] idleInhibitor= in hyprcandy-bar.conf so the
// choice survives logout/reboot and is auto-applied on the next session start
// (InhibitorAnchor calls _load()).  A missing file/section/key defaults to ON
// and is materialised on first load — a fresh/live ISO session must not sleep
// while the installer is being used.
Item {
    id: sm

    property bool active: false

    // Called once by InhibitorAnchor at startup
    function _load() {
        _readSeen = false
        _readProc.running = true
    }

    function toggle() {
        sm.active = !sm.active
        _writeProc.running = true
    }

    // ── Persistence: hyprcandy-bar.conf [cc-idle-v1] ────────────────────────
    property bool _readSeen: false

    Process {
        id: _readProc
        command: ["bash", "-c",
            "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
            "[ -f \"$f\" ] || exit 0; " +
            "awk '/^\\[cc-idle-v1\\]/{s=1;next} /^\\[/{s=0} s&&/^idleInhibitor=/{sub(/^idleInhibitor=/,\"\"); print}' \"$f\""]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const v = line.trim()
                if (v === "") return
                sm._readSeen = true
                sm.active = (v === "true")
            }
        }
        onExited: {
            running = false
            // No flag yet (fresh install / live ISO): default ON and persist it.
            if (!sm._readSeen) {
                sm.active = true
                _writeProc.running = true
            }
        }
    }

    // Atomic section rewrite, same idiom as Config.qml's cava conf writer.
    Process {
        id: _writeProc
        command: ["bash", "-c",
            "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; sec=\"cc-idle-v1\"; " +
            "mkdir -p \"$(dirname \"$f\")\"; [ -f \"$f\" ] || touch \"$f\"; " +
            "awk -v s=\"[$sec]\" '/^\\[/{in_s=($0==s)} !in_s{print}' \"$f\" > \"$f.tmp\" && mv \"$f.tmp\" \"$f\"; " +
            "printf '[%s]\\nidleInhibitor=%s\\n' \"$sec\" \"$1\" >> \"$f\"",
            "--", sm.active ? "true" : "false"]
        running: false
        onExited: running = false
    }
}