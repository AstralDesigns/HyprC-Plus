import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: win
    color: "transparent"

    anchors { top: true; left: true; right: true }
    margins.top: Config.barHeight + Config.outerMarginTop + Config.outerMarginBottom + 3
    exclusionMode: ExclusionMode.Ignore
    implicitHeight: popRect.implicitHeight + 8

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

        implicitWidth:  Math.max(200, col.implicitWidth + 32)
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

            // ── Header ─────────────────────────────────────────────────
            Row {
                spacing: 6
                anchors.horizontalCenter: parent.horizontalCenter

                Text {
                    text: UpdatesPopupState.hasUpdates ? "" : "󰸟"
                    color: UpdatesPopupState.hasUpdates ? Theme.cPrimary : Theme.cOnSurfVar
                    font.family: Config.fontFamily
                    font.pixelSize: Config.fontSize + 2
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: UpdatesPopupState.hasUpdates ? "Updates available" : "System up to date"
                    color: Theme.cPrimary
                    font.family: Config.labelFont
                    font.pixelSize: Config.labelFontSize + 1
                    font.weight: Font.Medium
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            // ── Divider ────────────────────────────────────────────────
            Rectangle {
                width: parent.width; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
            }

            // ── Package list / status text ──────────────────────────────
            Text {
                width: parent.width
                text: UpdatesPopupState.text || "System is up to date"
                color: Theme.cOnSurfVar
                font.family: Config.labelFont
                font.pixelSize: Config.labelFontSize
                wrapMode: Text.WordWrap
                lineHeight: 1.4
            }

            // ── Update button (only visible when updates available) ─────
            Rectangle {
                width: parent.width
                height: UpdatesPopupState.hasUpdates ? 36 : 0
                radius: 10
                color: updateHover.containsMouse
                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                visible: UpdatesPopupState.hasUpdates
                Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "󰑓  Apply Updates"
                    color: Theme.cPrimary
                    font.family: Config.labelFont
                    font.pixelSize: 13
                    font.weight: Font.SemiBold
                }

                MouseArea {
                    id: updateHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        UpdatesPopupState.close()
                        _updateRunProc.running = true
                    }
                }
            }
        }
    }

    // Process to run updates - shared with Updates module
    Process {
        id: _updateRunProc
        command: [Config.home + "/.config/waybar/scripts/system-update.sh", "up"]
        running: false
    }
}
