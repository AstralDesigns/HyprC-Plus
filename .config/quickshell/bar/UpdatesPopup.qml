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
    readonly property real _barGap:    Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot:   Config.outerMarginBottom + Config.barHeight + 6
    readonly property real _panelMargin: Config.outerMarginSide * 2

    anchors { top: !_barAtBottom; bottom: _barAtBottom; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
        right:  _panelMargin + 125
    }
    implicitWidth: popRect.implicitWidth
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
        anchors.fill: parent
        // Add anchors.rightMargin here to nudge left under the updates module
        y: 3

        implicitWidth:  Math.max(220, col.implicitWidth + 32)
        implicitHeight: col.implicitHeight + 24

        color: Theme.blurBackground
        radius:       20
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

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
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
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
                    text: UpdatesPopupState.hasUpdates ? "Updates Available   " : "OS Is Up To Date    "
                    color: Theme.cPrimary
                    font.family:    Config.labelFont
                    font.pixelSize: Config.labelFontSize + 1
                    font.weight:    Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
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
                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                    : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.50)
                border.width: 1
        	border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
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
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
            }

            // ════════════════════════════════════════════════════════════════
            // SECTION 2 — HyprCandy Plus Updates
            // ════════════════════════════════════════════════════════════════

            Row {
                spacing: 6
                anchors.horizontalCenter: parent.horizontalCenter
                Text {
                    text: UpdatesPopupState.hcHasUpdates ? "󰏖" : "󰏗"
                    color: UpdatesPopupState.hcHasUpdates ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimaryContainer.g, Theme.cPrimaryContainer.b, 1.00) : Theme.cOnSurfVar
                    font.family:    Config.fontFamily
                    font.pixelSize: Config.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: UpdatesPopupState.hcHasUpdates ? "HC+ Updates Available" : "HC+ Is Up To Date"
                    color: UpdatesPopupState.hcHasUpdates ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimaryContainer.g, Theme.cPrimaryContainer.b, 1.00) : Theme.cPrimary
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
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
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
                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimaryContainer.g, Theme.cPrimaryContainer.b, 0.12)
                    : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.50)
                border.width: 1
        	border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
                visible: UpdatesPopupState.hcHasUpdates
                clip: true
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color  { ColorAnimation   { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    // Show "Running" during both the git-clone phase and the
                    // detached Candy_Update.sh phase (even after a QS reload).
                    text:  (_hcUpdateProc.running || _hcScriptRunning) ? "󰑓  Running …" : "󰇚 HC+ Updates"
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimaryContainer.g, Theme.cPrimaryContainer.b, 1.00)
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
            "cd ~/.HCUpdates && " +
            "git pull && " +
            "cd .. && " +
            "git clone --depth 1 https://github.com/AstralDesigns/candyinstall.git ~/.hyprcandy/candyinstall && " +
            "cd ~/.hyprcandy/candyinstall && " +
            "chmod +x Candy_Update.sh && " +
            "pkexec bash ~/.hyprcandy/candyinstall/Candy_Update.sh > /tmp/candy-update.log 2>&1"
        ]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                // Git clone succeeded and the script has been launched.
                // Write a sentinel file before marking running — this survives
                // the QS reload that the update itself triggers, so the
                // post-reload pgrep check can detect a completed update even
                // though _hcScriptRunning resets to false on every reload.
                _hcSentinelProc.running = true
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
        command: ["pgrep", "-f", "candyinstall/Candy_Update"]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                // Still running — keep the "Running …" state alive.
                _hcScriptRunning = true
            } else {
                // Script finished (or was never running on this boot).
                // Check sentinel file rather than _hcScriptRunning — the flag
                // resets on every QS reload but the file survives, so this
                // correctly fires even when the reload happened mid-update.
                _hcScriptRunning = false
                _hcStateClearProc.running = true
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
    // Gates on the sentinel file so cold QS starts (where no update ran)
    // don't spuriously fire notify.sh.
    Process {
        id: _hcStateClearProc
        command: [
            "bash", "-c",
            "s=" + Quickshell.env("HOME") + "/.config/hyprcandy/.hc-update-sentinel; " +
            "[ -f \"$s\" ] || exit 0; " +
            Quickshell.env("HOME") + "/.config/hypr/scripts/notify.sh > /dev/null; " +
            "rm -f \"$s\" " + Quickshell.env("HOME") + "/.config/hyprcandy/hc-update-state"
        ]
        running: false
        onExited: {
            running = false
            UpdatesPopupState.requestRescan()
            if (!_hcReColorProc.running)
                _hcReColorProc.running = true
        }
    }

    // ── Sentinel writer — marks that an HC+ update was launched ──────────────
    // Written before the QS reload so the post-reload pgrep check knows a
    // completed update needs cleanup, even though _hcScriptRunning resets.
    Process {
        id: _hcSentinelProc
        command: [
            "bash", "-c",
            "touch " + Quickshell.env("HOME") + "/.config/hyprcandy/.hc-update-sentinel"
        ]
        running: false
        onExited: running = false
    }

    // ── Post-update color regeneration ───────────────────────────────────────
    // Runs wallpaper_integration.sh as the real user after HC+ update completes.
    // QS is already running in the user session so HOME, WAYLAND_DISPLAY and
    // DBUS_SESSION_BUS_ADDRESS are all correct — no pkexec env juggling needed.
    Process {
        id: _hcReColorProc
        command: [Quickshell.env("HOME") + "/.config/hyprcandy/hooks/wallpaper_integration.sh"]
        running: false
        onExited: running = false
    }
}
