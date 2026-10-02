import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "."

// ═══════════════════════════════════════════════════════════════════════════
//  TrashDialog.qml — "Empty Trash?" confirm dialog (GJS hyprcandydock parity).
//
//  Floating centered overlay surface. Empties trash through the Nautilus
//  DBus FileOperations2 service (exact GJS path), falling back to
//  `gio trash --empty`. Caller drives visibility via the `visible` property
//  and listens for `dismissed()` (any close path).
// ═══════════════════════════════════════════════════════════════════════════

PanelWindow {
    id: dlg

    signal dismissed()

    color: "transparent"
    WlrLayershell.namespace: "hyprcandy-trash-dialog"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0

    anchors { top: true; left: true }
    margins {
        left: Math.round((dlg.screen.width - dlg.width) / 2)
        top: Math.round((dlg.screen.height - dlg.height) / 2)
    }
    implicitWidth: 340
    implicitHeight: 176

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Theme.blurBackground
        border.width: 1
        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                              Theme.cPrimary.b, 0.25)

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -14
            width: parent.width - 32
            spacing: 6

            Text {
                width: parent.width
                text: "Empty the Trash?"
                font.pixelSize: 14
                font.bold: true
                color: Theme.cPrimary
                horizontalAlignment: Text.AlignHCenter
            }
            Text {
                width: parent.width
                text: TrashState.count + " item" + (TrashState.count === 1 ? "" : "s")
                      + " will be deleted permanently."
                font.pixelSize: 11
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                               Theme.cPrimary.b, 0.7)
                horizontalAlignment: Text.AlignHCenter
            }
        }

        Row {
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                margins: 18
            }
            spacing: 12

            Rectangle {
                width: cancelMa.implicitWidth + 28
                height: 34
                radius: 17
                color: cancelMa.containsMouse
                       ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                       : "transparent"
                border.width: 1
                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                      Theme.cPrimary.b, 0.3)
                Behavior on color { ColorAnimation { duration: 80 } }
                Text {
                    id: cancelMa
                    anchors.centerIn: parent
                    text: "Cancel"
                    font.pixelSize: 12
                    color: Theme.cPrimary
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: dlg.dismissed()
                }
            }

            Rectangle {
                width: emptyLabel.implicitWidth + 28
                height: 34
                radius: 17
                color: emptyMa.containsMouse
                       ? Qt.rgba(0.88, 0.30, 0.30, 1.0)
                       : Qt.rgba(0.82, 0.24, 0.24, 0.85)
                Behavior on color { ColorAnimation { duration: 80 } }
                Text {
                    id: emptyLabel
                    anchors.centerIn: parent
                    text: "\u{F01B4}  Empty Trash"
                    font.family: Theme.fontFamily
                    font.pixelSize: 12
                    color: "white"
                }
                MouseArea {
                    id: emptyMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        emptyProc.running = false
                        emptyProc.running = true
                    }
                }
            }
        }
    }

    // Nautilus DBus first (matches GJS: passes parent-window + skip-confirm
    // flags), gio as the no-nautilus fallback. Refresh the count either way.
    Process {
        id: emptyProc
        command: ["bash", "-c",
            "gdbus call --session --dest org.gnome.Nautilus " +
            "--object-path /org/gnome/Nautilus/FileOperations2 " +
            "--method org.gnome.Nautilus.FileOperations2.EmptyTrash false '{}' " +
            "2>/dev/null || gio trash --empty"]
        onExited: function(failed, exitCode) {
            TrashState.refresh()
            dlg.dismissed()
        }
    }

    // Escape dismisses while the dialog holds keyboard focus.
    Item {
        anchors.fill: parent
        focus: visible
        Keys.onEscapePressed: dlg.dismissed()
    }
}
