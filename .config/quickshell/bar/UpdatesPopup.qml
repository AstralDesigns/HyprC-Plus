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

    // ── Tracks whether Candy_Update.sh is alive in the OS, even across QS reloads ──
    property bool _hcScriptRunning: false

    // On every QS load (including reloads mid-update) check immediately whether
    // the update script is already running so the button reflects reality.
    Component.onCompleted: _hcPgrepProc.running = true

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
    // Phase 1 (this process): git clone into ~/.hyprcandy, then launch
    // Candy_Update.sh via setsid so it runs in its own process group —
    // completely detached from QuickShell.  When QS reloads (e.g. because
    // the bar itself was just updated) this process is gone but the script
    // keeps running; _hcPgrepProc picks it back up on Component.onCompleted.
    //
    // pexec inside Candy_Update.sh handles privilege elevation via hyprpolkit
    // so the password prompt appears in the foreground independently of QS.
    Process {
        id: _hcUpdateProc
        command: [
            "bash", "-ic",
            "rm -rf ~/.hyprcandy/candyinstall && " +
            "git clone --depth 1 https://github.com/AstralDesigns/candyinstall.git ~/.hyprcandy/candyinstall && " +
            "cd ~/.hyprcandy/candyinstall && " +
            "chmod +x Candy_Update.sh && " +
            "bash Candy_Update.sh > /tmp/candy-update.log 2>&1 &"
        ]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                // Git clone succeeded and the script has been launched.
                // Mark it running so the UI shows "Running …" immediately,
                // then let the poll timer take over tracking.
                _hcScriptRunning = true
                _hcPollTimer.start()
            }
            // Non-zero: git clone or chmod failed — nothing to poll.
            // _hcScriptRunning stays false; user can retry.
        }
    }

    // ── pgrep probe — detects Candy_Update.sh in the OS process table ─────────
    // Exit code 0 → script is alive; 1 → script has finished.
    // This fires on Component.onCompleted (reload recovery) and on every
    // _hcPollTimer tick while _hcScriptRunning is true.
    Process {
        id: _hcPgrepProc
        command: ["pgrep", "-f", "Candy_Update.sh"]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                // Still running — keep the "Running …" state alive.
                _hcScriptRunning = true
            } else {
                // Script finished (or was never running on this boot).
                // Only run cleanup when we were previously tracking it so
                // a cold QS start doesn't spuriously clear the state file.
                if (_hcScriptRunning) {
                    _hcScriptRunning = false
                    _hcStateClearProc.running = true
                }
                // If _hcScriptRunning was already false (cold start, no
                // prior run detected) do nothing — leave state as-is.
            }
        }
    }

    // ── Poll timer — re-checks pgrep every 3 s while the script is running ────
    // Stops automatically once _hcScriptRunning flips to false.
    Timer {
        id: _hcPollTimer
        interval: 1000
        repeat:   true
        running:  _hcScriptRunning
        onTriggered: {
            // Don't stack concurrent pgrep calls
            if (!_hcPgrepProc.running)
                _hcPgrepProc.running = true
        }
    }

    // ── HC state file cleanup process (runs after script finishes) ────────────
    // Removes ~/.config/hyprcandy/hc-update-state so the next check
    // evaluates fresh rather than reading the now-stale persisted state.
    Process {
        id: _hcStateClearProc
        command: [
            "bash", "-c",
            "rm -f " + Quickshell.env("HOME") + "/.config/hyprcandy/hc-update-state"
        ]
        running: false
        onExited: {
            running = false
            // Rescan — hc-update-check.sh will find no state file and run a
            // fresh git pull which should report up to date.
            UpdatesPopupState.requestRescan()
        }
    }
}
