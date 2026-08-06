import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// Combined updates indicator — system packages + HyprCandy Plus dotfiles.
// Shows 󰏗 when everything is up-to-date, 󰏖 (OnSurfVar colour) when any
// updates are pending.  Click opens UpdatesPopup with two sections.
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  updIcon.implicitWidth + Config.moduleHPad * 2 + (updBadge.visible ? 6 : 0)
    implicitHeight: Config.moduleHeight

    // ── System update state ───────────────────────────────────────────────────
    property string _text:       "󰏗"
    property string _tooltip:    "Checking for updates…"
    property bool   _hasUpdates: false
    property bool   _checking:   false
    property string _sysBuffer:  ""

    // ── HC update state ───────────────────────────────────────────────────────
    property bool   _hcHasUpdates: false
    property bool   _hcChecking:   false
    property string _hcBuffer:     ""

    readonly property bool _anyUpdates: _hasUpdates || UpdatesPopupState.hcHasUpdates
    readonly property bool _anyChecking: _checking   || _hcChecking

    // ── Loader animation ──────────────────────────────────────────────────────
    readonly property var _loaderFrames: ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    property int _loaderIdx: 0
    Timer {
        id: loaderTick
        interval: 80; running: root._anyChecking; repeat: true
        onTriggered: root._loaderIdx = (root._loaderIdx + 1) % root._loaderFrames.length
    }

    // ── Gaming detection ────────────────────────────────────────────────────────
    // Process/executable name fragments for common Linux gaming launchers,
    // compatibility layers, and overlays. Matched with `pgrep -f` (regex, OR'd).
    // Add more here as needed — kept as a single property for easy tuning.
    readonly property var _gamingPatterns: [
        "steam", "steamwebhelper", "lutris", "heroic", "Heroic",
        "faugus", "legendary", "bottles", "minigalaxy", "playonlinux",
        "gamescope", "gamemoderun", "gamemoded", "mangohud",
        "wine64-preloader", "wineserver", "proton", "retroarch"
    ]

    // ── Trigger a fresh scan of both checks — skipped while gaming ────────────
    function rescan() {
        if (_gamingCheckProc.running) return
        // Flip the "checking" flags immediately so the spinner animation
        // covers the gaming-detection step too, not just the real checks.
        root._checking   = true
        root._hcChecking = true
        _gamingCheckProc.running = true
    }

    // Actually kicks off the two check processes (called once we know the
    // user isn't gaming).
    function _rescanNow() {
        root._hcBuffer  = ""
        root._sysBuffer = ""
        if (!checkProc.running)   checkProc.running   = true
        if (!hcCheckProc.running) hcCheckProc.running = true
    }

    // Exit code 0 → a gaming pattern matched, so skip the scan entirely.
    // Non-zero → clear to proceed.
    Process {
        id: _gamingCheckProc
        command: ["pgrep", "-x", root._gamingPatterns.join("|")]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                // Gaming detected — abort, drop the spinner we optimistically started.
                root._checking   = false
                root._hcChecking = false
                return
            }
            root._rescanNow()
        }
    }

    // ── System update check ───────────────────────────────────────────────────
    Process {
        id: checkProc
        command: [Config.scriptsDir + "/system-update.sh"]

        onRunningChanged: {
            root._checking = running
            if (running) root._sysBuffer = ""
        }

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const t = l.trim()
                if (t) root._sysBuffer = t
            }
        }

        onExited: {
            const t = root._sysBuffer.trim()
            if (!t) return
            try {
                const d = JSON.parse(t)
                root._text       = d.text    || "󰏗"
                root._tooltip    = d.tooltip || "System is up to date"
                root._hasUpdates = !!(d.text && d.text !== "󰏗")
            } catch(e) {
                root._text       = t
                root._tooltip    = t
                root._hasUpdates = false
            }
        }
    }

    // ── HC update check ───────────────────────────────────────────────────────
    Process {
        id: hcCheckProc
        command: [Config.scriptsDir + "/hc-update-check.sh"]

        onRunningChanged: root._hcChecking = running

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const t = l.trim()
                if (t) root._hcBuffer = t
            }
        }

        onExited: {
            const t = root._hcBuffer.trim()
            if (!t) return
            try {
                const d = JSON.parse(t)
                const hasUp = !!d.hasUpdates
                const noSt  = !!d.noStore
                const tip   = d.tooltip || ""
                root._hcHasUpdates = hasUp
                UpdatesPopupState.updateHC(hasUp, tip, noSt)
            } catch(e) {
                // leave previous state
            }
            root._hcBuffer = ""
        }
    }

    // ── Startup delay (avoids singleton race on bar init) ─────────────────────
    Timer {
        id: startupDelay
        interval: 1500; running: true; repeat: false
        onTriggered: root.rescan()
    }

    // ── Hourly poll ───────────────────────────────────────────────────────────
    Timer {
        interval: 3600000; running: true; repeat: true
        onTriggered: root.rescan()
    }

    // ── Icon ──────────────────────────────────────────────────────────────────
    Text {
        id: updIcon
        anchors.centerIn: parent
        text:  root._anyChecking ? root._loaderFrames[root._loaderIdx]
                                 : (root._anyUpdates ? "󰏖" : "󰏗")
        color: root._anyChecking ? Config.rightGroupColor
             : root._anyUpdates  ? Theme.cPrimary
             :                     Config.rightGroupColor
        font.family:    Config.fontFamily
        font.pixelSize: Config.fontSize
        font.weight:    Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    Rectangle {
        id: updBadge
        visible: root._anyUpdates
        anchors { top: parent.top; right: parent.right; topMargin: 3; rightMargin: 1 }
        width: badgeLabel.implicitWidth + 4
        height: 10; radius: 5
        color: Theme.cPrimary

        Text {
            id: badgeLabel
            anchors.centerIn: parent
            text: "󰇚"
            color: Theme.cOnPrimary
            font.family:    Config.fontFamily
            font.pixelSize: 7
            font.weight: Font.Bold
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            const cx = root.mapToItem(null, root.width / 2, 0).x
            UpdatesPopupState.toggle(cx, root._tooltip, root._hasUpdates)
        }
    }

    // ── Expose rescan so UpdatesPopup can call it after updates complete ──────
    // (UpdatesPopup reaches this via the singleton — see UpdatesPopupState)
    Connections {
        target: UpdatesPopupState
        function onRescanRequested() { root.rescan() }
    }
}
