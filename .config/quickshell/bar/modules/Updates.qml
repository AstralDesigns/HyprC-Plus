import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// Combined updates indicator — system packages + HyprCandy Plus dotfiles.
// Shows 󰏗 when everything is up-to-date, 󰏖 (primary colour) when any
// updates are pending.  Click opens UpdatesPopup with two sections.
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  updIcon.implicitWidth + Config.moduleHPad * 2
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

    readonly property bool _anyUpdates:  _hasUpdates || _hcHasUpdates
    readonly property bool _anyChecking: _checking   || _hcChecking

    // ── Paths ─────────────────────────────────────────────────────────────────
    readonly property string _hcStatePath:   Quickshell.env("HOME") + "/.config/hyprcandy/hc-update-state.json"
    readonly property string _rescanSentinel: Quickshell.env("HOME") + "/.config/hyprcandy/qs-rescan-updates"

    // ── Loader animation ──────────────────────────────────────────────────────
    readonly property var _loaderFrames: ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    property int _loaderIdx: 0
    Timer {
        id: loaderTick
        interval: 80; running: root._anyChecking; repeat: true
        onTriggered: root._loaderIdx = (root._loaderIdx + 1) % root._loaderFrames.length
    }

    // ── Restore persisted HC state on startup ─────────────────────────────────
    // Read ~/.config/hyprcandy/hc-update-state.json written by hc-update-check.sh
    // so a bar restart or session restart remembers the last known HC+ update status.
    FileView {
        id: hcStateFile
        path: root._hcStatePath
        // onLoaded fires once the file has been read
        onLoaded: {
            const t = (hcStateFile.text || "").trim()
            if (!t) return
            try {
                const d = JSON.parse(t)
                const hasUp = !!d.hasUpdates
                const noSt  = !!d.noStore
                const tip   = d.tooltip || ""
                // Only restore an "updates available" state — don't restore
                // an "up to date" state because that's the safe default anyway.
                if (hasUp) {
                    root._hcHasUpdates = hasUp
                    UpdatesPopupState.updateHC(hasUp, tip, noSt)
                }
            } catch(e) { /* malformed file, ignore */ }
        }
    }

    // ── Rescan sentinel watcher ─────────────────────────────────────────────
    // system-update.sh and Candy_Update.sh both touch
    // ~/.config/hyprcandy/qs-rescan-updates when the user declines
    // reboot/logout.  We poll for that file every 2 s with a Process test
    // rather than FileView so it only acts when the file genuinely exists —
    // FileView.onLoaded fires at startup regardless of file presence.
    Timer {
        id: sentinelPoller
        interval: 2000; running: true; repeat: true
        onTriggered: sentinelCheck.running = true
    }
    Process {
        id: sentinelCheck
        command: ["bash", "-c", "test -f '" + root._rescanSentinel + "'"]
        running: false
        onExited: function(code) {
            if (code !== 0) return   // file absent — nothing to do
            sentinelCleanup.running = true
            root._hcBuffer  = ""
            root._sysBuffer = ""
            if (!checkProc.running)   checkProc.running   = true
            if (!hcCheckProc.running) hcCheckProc.running = true
        }
    }
    Process {
        id: sentinelCleanup
        command: ["rm", "-f", root._rescanSentinel]
        running: false
    }

        // ── System update check ───────────────────────────────────────────────────
    Process {
        id: checkProc
        command: [Config.scriptsDir + "/system-update.sh"]

        onRunningChanged: {
            root._checking = running
            // Only clear buffer when starting a fresh run, not on exit
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

        // Only track checking state here — buffer is cleared at run start
        // separately so onExited always sees the last populated buffer
        // regardless of signal ordering between onExited/onRunningChanged.
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
                if (hasUp) {
                    // Real updates found — always apply
                    root._hcHasUpdates = true
                    UpdatesPopupState.updateHC(hasUp, tip, noSt)
                } else {
                    // Script reported up-to-date. This is either:
                    //   a) emit_uptodate re-catting the state file (user hasn't
                    //      updated yet) — state file present, don't clear icon
                    //   b) genuine up-to-date after user ran the update and
                    //      _hcStateCleanup deleted the state file — clear icon
                    // Distinguish by checking state file existence.
                    hcStateExistCheck.tip    = tip
                    hcStateExistCheck.noSt   = noSt
                    hcStateExistCheck.running = true
                }
            } catch(e) {
                // leave previous state
            }
            // Clear after parse so a future stale buffer can't bleed through
            root._hcBuffer = ""
        }
    }

    // ── HC state file existence check ────────────────────────────────────────
    // Runs after hcCheckProc reports hasUpdates:false to determine whether
    // that false came from emit_uptodate re-catting a persisted state (file
    // present → keep icon) or from a genuine post-update clean scan (file
    // absent → clear icon).
    Process {
        id: hcStateExistCheck
        property string tip:  ""
        property bool   noSt: false
        command: ["bash", "-c", "test -f '" + root._hcStatePath + "'"]
        running: false
        onExited: function(code) {
            if (code === 0) {
                // State file still present — persisted update, keep icon lit
                // (do nothing; _hcHasUpdates already true from prior detection)
            } else {
                // State file gone — user completed the update, clear icon
                root._hcHasUpdates = false
                UpdatesPopupState.updateHC(false, hcStateExistCheck.tip, hcStateExistCheck.noSt)
            }
        }
    }

    // ── Startup delay (avoids singleton race on bar init) ─────────────────────
    Timer {
        id: startupDelay
        interval: 1500; running: true; repeat: false
        onTriggered: {
            // Clear HC buffer here, just before launch, so ordering is safe
            root._hcBuffer  = ""
            root._sysBuffer = ""
            if (!checkProc.running)   checkProc.running   = true
            if (!hcCheckProc.running) hcCheckProc.running = true
        }
    }

    // ── Hourly poll ───────────────────────────────────────────────────────────
    Timer {
        interval: 3600000; running: true; repeat: true
        onTriggered: {
            root._hcBuffer  = ""
            root._sysBuffer = ""
            if (!checkProc.running)   checkProc.running   = true
            if (!hcCheckProc.running) hcCheckProc.running = true
        }
    }

    // ── Icon ──────────────────────────────────────────────────────────────────
    Text {
        id: updIcon
        anchors.centerIn: parent
        text:  root._anyChecking ? root._loaderFrames[root._loaderIdx]
                                 : (root._anyUpdates ? "󰏖" : "󰏗")
        color: root._anyChecking ? Theme.cOnSurfVar
             : root._anyUpdates  ? Theme.cPrimary
             :                     Theme.cOnSurfVar
        font.family:    Config.fontFamily
        font.pixelSize: Config.fontSize
        font.weight:    Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
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
}
