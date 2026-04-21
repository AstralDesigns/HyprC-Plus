import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: win
    visible: UpdatesPopupState.visible
    color: "transparent"

    anchors { top: true; left: true; right: true }
    margins.top: Config.barHeight + Config.outerMarginTop + Config.outerMarginBottom + 3
    exclusionMode: ExclusionMode.Ignore
    implicitHeight: popRect.implicitHeight + 8

    // ── Rescan sentinel path (shared with Updates.qml) ────────────────────────
    readonly property string _rescanSentinel: Quickshell.env("HOME") + "/.config/hyprcandy/qs-rescan-updates"

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
            // SECTION 1 — System Updates
            // ════════════════════════════════════════════════════════════════

            // ── Sys Header ──────────────────────────────────────────────────
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

            // ── Sys divider ──────────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
            }

            // ── Sys tooltip text (hidden when up-to-date) ────────────────────
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

            // ── Sys apply button ─────────────────────────────────────────────
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
            // Separator between sections
            // ════════════════════════════════════════════════════════════════
            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.5)
            }

            // ════════════════════════════════════════════════════════════════
            // SECTION 2 — HyprCandy Plus Updates
            // ════════════════════════════════════════════════════════════════

            // ── HC Header ───────────────────────────────────────────────────
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
                    text: UpdatesPopupState.hcHasUpdates ? "HC+ Updates Available" : "HCPlus Is Up To Date"
                    color: UpdatesPopupState.hcHasUpdates ? Theme.cTertiary : Theme.cOnSurfVar
                    font.family:    Config.labelFont
                    font.pixelSize: Config.labelFontSize + 1
                    font.weight:    Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── HC divider ───────────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
            }

            // ── HC tooltip text (hidden when up-to-date) ─────────────────────
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

            // ── HC apply button ──────────────────────────────────────────────
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
                    text:  _hcUpdateProc.running ? "󰑓  Running …" : "󰇚 HC+ Updates"
                    color: Theme.cTertiary
                    font.family:    Config.labelFont
                    font.pixelSize: 13
                }
                MouseArea {
                    id: hcUpdateHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    if (!_hcUpdateProc.running) _hcUpdateProc.running = true
                }
            }
        }
    }

    // ── System update process ─────────────────────────────────────────────────
    // Launched directly inside the popup as a kitty floating-installer window.
    // The script calls signal_qs_rescan (touches the sentinel) when the user
    // picks 'n' for reboot, which Updates.qml picks up within 2 s.
    // The kitty window closes itself naturally when the script exits.
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
        }
    }

    // ── HyprCandy Plus update process ────────────────────────────────────────
    // Launches Candy_Update.sh in an independent kitty floating-installer window.
    // When the user picks 'n' at the logout prompt, Candy_Update.sh touches the
    // rescan sentinel AND exits — which causes kitty to close.  However, if for
    // any reason the window stays alive we also pkill it here so it doesn't hang
    // around after the update flow completes.
    //
    // The state file (~/.config/hyprcandy/hc-update-state.json) is the persistent
    // "updates pending" record written by hc-update-check.sh.  It is intentionally
    // never overwritten by a clean scan — only deleted here, when the user actually
    // runs the update.  Deleting it is what allows the next scan's "Already up to
    // date" result to be surfaced as genuinely up-to-date in the UI.
    Process {
        id: _hcUpdateProc
        command: [
            "kitty",
            "--class", "floating-installer",
            "--title", "   HC+ Update",
            "-e", "bash", "-ic",
            "rm -rf ~/candyinstall && git clone --depth 1 https://github.com/AstralDesigns/candyinstall.git ~/candyinstall && cd ~/candyinstall && chmod +x Candy_Update.sh && bash Candy_Update.sh"
        ]
        running: false
        onExited: {
            running = false
            // Delete the persistent HC+ update state file so the next scan's
            // "Already up to date" result is no longer shadowed by the old
            // pending-update record.
            _hcStateCleanup.running = true
            // Kill any lingering floating-installer kitty windows.
            _hcKittyCleanup.running = true
            // Don't auto-close popup — user may want to check sys section too
        }
    }

    // Delete the HC+ update state file — run when the user completes the update.
    // Until this file is absent, clean scans will re-surface the pending state.
    Process {
        id: _hcStateCleanup
        command: ["rm", "-f", Quickshell.env("HOME") + "/.config/hyprcandy/hc-update-state.json"]
        running: false
    }

    // pkill all kitty instances whose WM_CLASS is floating-installer that are
    // still alive after the HC+ update process has fully exited.
    Process {
        id: _hcKittyCleanup
        command: ["pkill", "--exact", "--full", "floating-installer"]
        running: false
    }
}
