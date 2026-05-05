import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: win
    visible: UpdatesPopupState.visible
    color: "transparent"

    readonly property bool _barAtBottom: Config.barPosition === "bottom"

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : (Config.barHeight + Config.outerMarginTop + Config.outerMarginBottom + 3)
        bottom: _barAtBottom ? (Config.barHeight + Config.outerMarginTop + Config.outerMarginBottom + 3) : 0
    }
    exclusionMode: ExclusionMode.Ignore
    implicitHeight: popRect.implicitHeight + 8

    // ── Tracks whether Candy_Update.sh is running (sentinel-file approach) ──────
    // True while we are waiting for /tmp/hc-update-complete to appear.
    // Does NOT depend on pgrep / process-table visibility, so it works
    // correctly even when the script runs under a pkexec-elevated UID.
    property bool _hcScriptRunning: false

    // On every QS load check whether the sentinel already exists — handles the
    // case where QS is reloaded mid-update (the timer will start automatically
    // because _hcScriptRunning is bound to it).
    Component.onCompleted: _hcSentinelCheckProc.running = true

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: UpdatesPopupState.close()
    }

    Rectangle {
        id: popRect
        x: Math.min(
               Math.max(0, UpdatesPopupState.anchorX - implicitWidth / 2),
               Math.max(0, win.width - implicitWidth - 8))
        y: 4

        implicitWidth:  Math.max(220, col.implicitWidth + 32)
        implicitHeight: col.implicitHeight + 24

        color:        Theme.cOnSecondary
        radius:       20
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)

        Column {
            id: col
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                topMargin: 12; bottomMargin: 12
                leftMargin: 16; rightMargin: 16
            }
            spacing: 8

            // ════════════════════════════════════════════════════════════════
            // Section separator
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
            }
            
            // ════════════════════════════════════════════════════════════════
            // SECTION 1 — System Updates
            // ════════════════════════════════════════════════════════════════

            Row {
                spacing: 6
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    text: UpdatesPopupState.hasUpdates ? "󰏖" : "󰏗"
                    color: UpdatesPopupState.hasUpdates ? Theme.cPrimary : Theme.cOnSurfVar
                    font.family:    Config.fontFamily
                    font.pixelSize: Config.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: UpdatesPopupState.hasUpdates ? "Updates Available" : "System Up To Date"
                    color: Theme.cPrimary
                    font.family:    Config.labelFont
                    font.pixelSize: Config.labelFontSize + 1
                    font.weight:    Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
            }

            Text {
                width: parent.width
                visible: UpdatesPopupState.hasUpdates
                height:  UpdatesPopupState.hasUpdates ? implicitHeight : 0
                text:  UpdatesPopupState.text || ""
                color: Theme.cOnSurfVar
                font.family:    Config.labelFont
                font.pixelSize: Config.labelFontSize
                wrapMode: Text.WordWrap
                lineHeight: 1.4
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                width:  parent.width
                height: UpdatesPopupState.hasUpdates ? 36 : 0
                radius: 10
                color: sysUpdateHover.containsMouse
                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                visible: UpdatesPopupState.hasUpdates
                clip: true
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color  { ColorAnimation   { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text:  _sysUpdateProc.running ? "󰑓  Running …" : "󰇚 System Updates"
                    color: Theme.cPrimary
                    font.family:    Config.labelFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: sysUpdateHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    if (!_sysUpdateProc.running) _sysUpdateProc.running = true
                }
            }

            // ════════════════════════════════════════════════════════════════
            // Section separator
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
            }

            // ════════════════════════════════════════════════════════════════
            // SECTION 2 — HyprCandy Plus Updates
            // ════════════════════════════════════════════════════════════════

            Row {
                spacing: 6
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    text: UpdatesPopupState.hcHasUpdates ? "󰏖" : "󰏗"
                    color: UpdatesPopupState.hcHasUpdates ? Theme.cTertiary : Theme.cOnSurfVar
                    font.family:    Config.fontFamily
                    font.pixelSize: Config.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: UpdatesPopupState.hcHasUpdates ? "HC+ Updates Available" : "HC+ Is Up To Date"
                    color: UpdatesPopupState.hcHasUpdates ? Theme.cTertiary : Theme.cPrimary
                    font.family:    Config.labelFont
                    font.pixelSize: Config.labelFontSize + 1
                    font.weight:    Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
                // Re-run button: shown only when HC is "up to date" so the user
                // can force a fresh install even after an abrupt closure.
                Text {
                    id: hcRerunBtn
                    // _hcUpdateProc.running covers the git-clone phase;
                    // _hcScriptRunning covers the detached Candy_Update.sh phase
                    // (including across QS reloads).
                    visible: !UpdatesPopupState.hcHasUpdates
                    text: (_hcUpdateProc.running || _hcScriptRunning) ? "󰑓" : "󰇚"
                    color: hcRerunHover.containsMouse
                        ? Qt.rgba(Theme.cTertiary.r, Theme.cTertiary.g, Theme.cTertiary.b, 0.75)
                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.35)
                    font.family:    Config.fontFamily
                    font.pixelSize: Config.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                    Behavior on color { ColorAnimation { duration: 120 } }
                    MouseArea {
                        id: hcRerunHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape:  Qt.PointingHandCursor
                        onClicked: {
                            if (!_hcUpdateProc.running && !_hcScriptRunning)
                                _hcUpdateProc.running = true
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
            }

            Text {
                width: parent.width
                visible: UpdatesPopupState.hcHasUpdates
                height:  UpdatesPopupState.hcHasUpdates ? implicitHeight : 0
                text:  UpdatesPopupState.hcTooltip || ""
                color: Theme.cOnSurfVar
                font.family:    Config.labelFont
                font.pixelSize: Config.labelFontSize
                wrapMode: Text.WordWrap
                lineHeight: 1.4
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            }

            Rectangle {
                width:  parent.width
                height: UpdatesPopupState.hcHasUpdates ? 36 : 0
                radius: 10
                color: hcUpdateHover.containsMouse
                    ? Qt.rgba(Theme.cTertiary.r, Theme.cTertiary.g, Theme.cTertiary.b, 0.25)
                    : Qt.rgba(Theme.cTertiary.r, Theme.cTertiary.g, Theme.cTertiary.b, 0.12)
                visible: UpdatesPopupState.hcHasUpdates
                clip: true
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color  { ColorAnimation   { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    // Show "Running" during both the git-clone phase and the
                    // detached Candy_Update.sh phase (even after a QS reload).
                    text:  (_hcUpdateProc.running || _hcScriptRunning) ? "󰑓  Running …" : "󰇚 HC+ Updates"
                    color: Theme.cTertiary
                    font.family:    Config.labelFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: hcUpdateHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: {
                        if (!_hcUpdateProc.running && !_hcScriptRunning)
                            _hcUpdateProc.running = true
                    }
                }
            }
        }
    }

    // ── System update process ─────────────────────────────────────────────────
    // Still launches kitty (system-update.sh is interactive / pacman-driven).
    // If you also want system updates to survive QS reloads, apply the same
    // setsid + pgrep pattern used for HC below.
    Process {
        id: _sysUpdateProc
        command: [
            "kitty",
            "--class", "floating-installer",
            "--title", "   System Update",
            "-e", "bash", "-ic",
            Quickshell.env("HOME") + "/.config/hyprcandy/scripts/system-update.sh run"
        ]
        running: false
        onExited: {
            running = false
            UpdatesPopupState.close()
            // Immediate rescan so icon/popup reflect post-update state
            UpdatesPopupState.requestRescan()
        }
    }

    // ── HC update launcher ────────────────────────────────────────────────────
    // Phase 1 (this process): wipe any stale sentinel, git-clone candyinstall,
    // then fork Candy_Update.sh off via pkexec completely detached from QS.
    // This process exits the moment the background job is handed to the OS —
    // the actual update work happens asynchronously under the elevated UID.
    //
    // IMPORTANT: do NOT call _hcStateClearProc or requestRescan here.
    // onExited fires the instant the `&` fork returns, long before
    // Candy_Update.sh has done any work.  The sole cleanup authority is
    // _hcSentinelCheckProc.onExited (code === 0), which only fires once
    // complete.sh has touch'd /tmp/hc-update-complete at the very end.
    Process {
        id: _hcUpdateProc
        command: [
            "bash", "-ic",
            // Remove any stale sentinel so the poller starts fresh.
            "rm -f /tmp/hc-update-complete && " +
            "rm -rf ~/.hyprcandy/candyinstall && " +
            "git clone --depth 1 https://github.com/AstralDesigns/candyinstall.git ~/.hyprcandy/candyinstall && " +
            "cd ~/.hyprcandy/candyinstall && " +
            "chmod +x Candy_Update.sh && " +
            "pkexec bash ~/.hyprcandy/candyinstall/Candy_Update.sh > /tmp/candy-update.log 2>&1 &"
        ]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                // The background job launched successfully.
                // Show "Running …" in the UI immediately and hand off all
                // further lifecycle management to the pgrep poll loop.
                _hcScriptRunning = true
                // _hcPollTimer.running is bound to _hcScriptRunning so it
                // starts automatically — no explicit start() call needed.
            }
            // Non-zero: git clone or chmod failed — nothing to poll.
            // _hcScriptRunning stays false; user can retry.
        }
    }

    // ── Sentinel-file check — does /tmp/hc-update-complete exist? ────────────
    // Exit code 0 → sentinel present → Candy_Update.sh has finished.
    // Non-zero → sentinel absent → update is still in progress (or not started).
    //
    // Fired on Component.onCompleted (covers QS reload mid-update) and by
    // _hcPollTimer on every tick while _hcScriptRunning is true.
    //
    // We do NOT use pgrep because pkexec elevates the script to a different
    // UID, making it invisible to an unprivileged pgrep from the user session.
    Process {
        id: _hcSentinelCheckProc
        command: ["test", "-f", "/tmp/hc-update-complete"]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                // ── Sentinel found: update complete ──────────────────────────
                // Stop the poll loop regardless of whether we were the ones who
                // launched the update (handles stale sentinel on cold boot too).
                _hcScriptRunning = false

                // Optimistically clear the UI state immediately so the popup
                // reflects "up to date" without waiting for the async rescan.
                // The rescan below will confirm and set the tooltip correctly.
                UpdatesPopupState.updateHC(false, "HyprCandy Plus is up to date", false)

                // Clean up both the sentinel and the persisted state file,
                // then rescan so hc-update-check.sh can run a fresh git pull
                // and emit the authoritative JSON result.
                if (!_hcStateClearProc.running)
                    _hcStateClearProc.running = true
            }
            // Sentinel absent — if _hcScriptRunning is true the poll timer
            // will fire again; if false (cold start, nothing running) no-op.
        }
    }

    // ── Poll timer — checks sentinel every 2 s while update is running ────────
    // Bound to _hcScriptRunning so it auto-starts/stops with no manual calls.
    Timer {
        id: _hcPollTimer
        interval: 2000
        repeat:   true
        running:  _hcScriptRunning
        onTriggered: {
            if (!_hcSentinelCheckProc.running)
                _hcSentinelCheckProc.running = true
        }
    }

    // ── HC state-file cleanup (runs once sentinel is detected) ────────────────
    // Removes /tmp/hc-update-complete so it doesn't re-trigger on the next
    // QS load, and removes hc-update-state so hc-update-check.sh runs a
    // live git pull rather than reading stale cached output.
    // On exit, requestRescan() fires hcCheckProc in Updates.qml which calls
    // hc-update-check.sh — if GitHub says "Already up to date" it emits
    // hasUpdates:false and UpdatesPopupState.updateHC locks in the final state.
    Process {
        id: _hcStateClearProc
        command: [
            "bash", "-c",
            "rm -f /tmp/hc-update-complete " +
            Quickshell.env("HOME") + "/.config/hyprcandy/hc-update-state"
        ]
        running: false
        onExited: {
            running = false
            UpdatesPopupState.close()
            // Trigger the authoritative rescan — hc-update-check.sh will run
            // git pull on ~/HCUpdates; "Already up to date" → hasUpdates:false.
            UpdatesPopupState.requestRescan()
        }
    }
}
