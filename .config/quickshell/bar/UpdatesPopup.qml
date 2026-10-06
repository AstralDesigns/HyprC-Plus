import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: win
    // ── Deferred-destroy animation pattern ──────────────────────────────
    property bool _stateVisible: UpdatesPopupState.visible
    Timer { id: _updExitDelay; interval: 220; repeat: false }
    visible: _stateVisible || _updExitDelay.running
    on_StateVisibleChanged: { if (!_stateVisible) _updExitDelay.restart() }
    color: "transparent"

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop) : Config.outerMarginTop) + Config.barHeight + 4
    readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom) : Config.outerMarginBottom) + Config.barHeight + 4
    readonly property real _panelMargin: Config.barMode === "shell" ? Config.popupSideMargin : Config.popupSideMargin * 2

    anchors { top: !_barAtBottom; bottom: _barAtBottom; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
        right:  _panelMargin + 125
    }
    implicitWidth: 320
    exclusionMode: ExclusionMode.Ignore
    implicitHeight: 460

    // ── Tracks whether Candy_Update.sh is alive in the OS, even across QS reloads ──
    property bool _hcScriptRunning: false
    // True while any phase of the HC+ update is active: launcher, script, agent build, state cleanup, recolor, or probe
    readonly property bool _hcBusy: _hcUpdateProc.running || _hcScriptRunning || _hcAgentBuildProc.running || _hcStateClearProc.running || _hcReColorProc.running || _hcSentinelCheckProc.running

    // On every QS load (including reloads mid-update), probe the sentinel files
    // and process table so recovery and state transitions happen seamlessly.
    Component.onCompleted: _hcSentinelCheckProc.running = true

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: UpdatesPopupState.close()
    }

    Rectangle {
        id: popRect
        anchors {
            top: !_barAtBottom ? parent.top : undefined
            bottom: _barAtBottom ? parent.bottom : undefined
            right: parent.right
        }

        width:  Math.max(240, col.implicitWidth + 32)
        height: col.implicitHeight + 24

        color: Theme.blurBackground
        radius:       20
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

        // Animate in/out with opacity + scale
        opacity: win._stateVisible ? 1.0 : 0.0
        scale:   win._stateVisible ? 1.0 : 0.92
        transformOrigin: win._barAtBottom ? Item.BottomRight : Item.TopRight
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
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
                    color: UpdatesPopupState.hasUpdates ? Theme.cOnSurf : Theme.cSurfaceTint
                    font.family:    Config.fontFamily
                    font.pixelSize: Config.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: UpdatesPopupState.hasUpdates ? "Updates Available   " : "OS Is Up To Date    "
                    color: Theme. cOnSurf
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
                text:  UpdatesPopupState.text || ""
                color: Theme.cOnSurfVar
                font.family:    Config.labelFont
                font.pixelSize: Config.labelFontSize
                wrapMode: Text.WordWrap
                lineHeight: 1.4
            }

            Rectangle {
                width:  parent.width
                height: 36
                radius: 10
                color: sysUpdateHover.containsMouse
                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.35)
                    : Qt.rgba(Theme.cWc5.r, Theme.cWc5.g, Theme.cWc5.b, 0.35)
                border.width: 1
        	border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
                visible: UpdatesPopupState.hasUpdates
                clip: true
                Behavior on color  { ColorAnimation   { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    text:  _sysUpdateProc.running ? "󰑓  Running …" : "󰇚 System Updates"
                    color: Theme.cSurfaceTint
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
                    text: (UpdatesPopupState.hcHasUpdates || _hcBusy) ? "󰏖" : "󰏗"
                    color: (UpdatesPopupState.hcHasUpdates || _hcBusy) ? Theme.cOnSurf : Theme.cSurfaceTint
                    font.family:    Config.fontFamily
                    font.pixelSize: Config.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: (UpdatesPopupState.hcHasUpdates || _hcBusy) ? "HC+ Updates Available" : "HC+ Is Up To Date"
                    color: (UpdatesPopupState.hcHasUpdates || _hcBusy) ? Theme. cOnSurf : Theme. cOnSurf
                    font.family:    Config.labelFont
                    font.pixelSize: Config.labelFontSize + 1
                    font.weight:    Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
                // Re-run button: shown only when HC is "up to date" and not currently updating
                Text {
                    id: hcRerunBtn
                    visible: !UpdatesPopupState.hcHasUpdates && !_hcBusy
                    text: _hcBusy ? "󰑓" : "󰇚"
                    color: hcRerunHover.containsMouse
                        ? Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, 0.75)
                        : Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, 0.35)
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
                            if (!_hcBusy)
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
                visible: UpdatesPopupState.hcHasUpdates || _hcBusy
                text: (UpdatesPopupState.hcHasUpdates && UpdatesPopupState.hcTooltip)
                    ? UpdatesPopupState.hcTooltip
                    : (_hcBusy ? "Applying updates and workspace setup…" : "")
                color: Theme.cOnSurfVar
                font.family:    Config.labelFont
                font.pixelSize: Config.labelFontSize
                wrapMode: Text.WordWrap
                lineHeight: 1.4
            }

            Rectangle {
                width:  parent.width
                height: 36
                radius: 10
                color: hcUpdateHover.containsMouse
                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.35)
                    : Qt.rgba(Theme.cWc6.r, Theme.cWc6.g, Theme.cWc6.b, 0.35)
                border.width: 1
        	border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
                visible: UpdatesPopupState.hcHasUpdates || _hcBusy
                clip: true
                Behavior on color  { ColorAnimation   { duration: 120 } }
                Text {
                    anchors.centerIn: parent
                    // Show "Running" whenever any phase of update or workspace setup is active
                    text:  _hcBusy ? "󰑓  Running …" : "󰇚 HC+ Updates"
                    color: Theme.cSurfaceTint
                    font.family:    Config.labelFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: hcUpdateHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked: {
                        if (!_hcBusy)
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
    Process {
        id: _hcUpdateProc
        command: [
            "bash", "-ic",
            "touch \"" + Quickshell.env("HOME") + "/.config/hyprcandy/.hc-update-sentinel\" \"" +
                         Quickshell.env("HOME") + "/.config/hyprcandy/.hc-agent-build-pending\" && " +
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
        onRunningChanged: {
            if (running) {
                _hcScriptRunning = true
                _hcPollTimer.start()
            }
        }
        onExited: (code) => {
            running = false
            _hcScriptRunning = false
            if (code === 0) {
                if (!_hcAgentBuildProc.running)
                    _hcAgentBuildProc.running = true
            }
        }
    }

    // ── Sentinel probe — runs first on Component.onCompleted ─────────────────
    // Checks if an update was initiated and has pending build/cleanup work.
    // If a sentinel exists, pre-arms _hcScriptRunning = true before kicking off
    // the pgrep check. This guarantees that if Candy_Update.sh already finished
    // before or during reload, pgrep exiting non-zero will immediately transition
    // into the agent build and cleanup chain.
    Process {
        id: _hcSentinelCheckProc
        command: [
            "bash", "-c",
            "test -f \"" + Quickshell.env("HOME") + "/.config/hyprcandy/.hc-update-sentinel\" || " +
            "test -f \"" + Quickshell.env("HOME") + "/.config/hyprcandy/.hc-agent-build-pending\""
        ]
        running: false
        onExited: (code) => {
            running = false
            if (code === 0) {
                _hcScriptRunning = true
            }
            if (!_hcPgrepProc.running)
                _hcPgrepProc.running = true
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
                // Only clear state if script was previously running or sentinel was detected
                if (_hcScriptRunning) {
                    _hcScriptRunning = false
                    if (!_hcAgentBuildProc.running)
                        _hcAgentBuildProc.running = true
                }
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

    // ── Agentic workspace builder — runs after HC+ update if workspace isn't built ──
    // Delegates to hc-agent-build.sh which sources nvm/PATH properly so npm
    // and python3 are found in Quickshell's non-interactive process environment.
    // Always triggers _hcStateClearProc on exit regardless of build outcome.
    Process {
        id: _hcAgentBuildProc
        command: [
            "bash", "--login", "-c",
            "exec bash \"" + Quickshell.env("HOME") + "/.hyprcandy/GJS/hyprcandydock/agent-app/hc-agent-build.sh\""
        ]
        running: false
        onExited: {
            running = false
            if (!_hcStateClearProc.running)
                _hcStateClearProc.running = true
        }
    }

    // ── HC state file cleanup process (runs after agent build completes) ─────
    // Removes sentinel/state files and fires notify.sh
    Process {
        id: _hcStateClearProc
        command: [
            "bash", "-c",
            "bash \"" + Quickshell.env("HOME") + "/.config/hypr/scripts/notify.sh\"; " +
            "rm -f \"" + Quickshell.env("HOME") + "/.config/hyprcandy/.hc-update-sentinel\" \"" +
                         Quickshell.env("HOME") + "/.config/hyprcandy/.hc-agent-build-pending\" \"" +
                         Quickshell.env("HOME") + "/.config/hyprcandy/hc-update-state\""
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
            "touch \"" + Quickshell.env("HOME") + "/.config/hyprcandy/.hc-update-sentinel\" \"" +
                         Quickshell.env("HOME") + "/.config/hyprcandy/.hc-agent-build-pending\""
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
