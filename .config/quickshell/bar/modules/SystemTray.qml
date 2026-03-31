import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import ".."

Item {
    id: root

    property var rootWindow

    Layout.alignment: Qt.AlignVCenter
    // Always full width when icons present; Island hides the whole thing when implicitWidth == 0
    implicitWidth:  SystemTray.items.values.length > 0
                        ? trayRow.implicitWidth + Config.trayItemPadH * 2
                        : 0
    implicitHeight: Config.moduleHeight

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: Config.trayItemSpacing

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property SystemTrayItem modelData

                width:  Config.trayIconSz + Config.trayItemPadH * 2
                height: Config.trayIconSz + Config.trayItemPadV * 2

                Image {
                    anchors.centerIn: parent
                    source: trayItem.modelData.icon
                    width:  Config.trayIconSz
                    height: Config.trayIconSz
                    smooth: true
                    fillMode: Image.PreserveAspectFit
                }

                opacity: itemMouse.containsMouse ? 0.6 : 1.0
                Behavior on opacity { NumberAnimation { duration: 80 } }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton && trayItem.modelData.hasMenu) {
                            // mapToItem(null,...) gives coords relative to the PanelWindow root,
                            // which equals screen-x for a left+right anchored window.
                            const pt = trayItem.mapToItem(null, 0, 0)
                            TrayMenuState.open(trayItem.modelData.menu, pt.x)
                        } else if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate()
                        } else if (mouse.button === Qt.LeftButton) {
                            trayItem.modelData.activate()
                        }
                    }
                }
            }
        }
    }
}
