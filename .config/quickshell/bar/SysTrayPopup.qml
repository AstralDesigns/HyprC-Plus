import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.SystemTray

PanelWindow {
    id: win
    color: "transparent"
    visible: SysTrayPopupState.visible

    WlrLayershell.namespace: "quickshell:systraypopup"

    readonly property bool _barAtBottom:  Config.barPosition === "bottom"
    readonly property real _barGap:       Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot:    Config.outerMarginBottom + Config.barHeight + 6
    readonly property real _panelMargin:  Config.outerMarginSide * 2

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }
    exclusionMode: ExclusionMode.Ignore
    implicitHeight: popupRect.implicitHeight + 4

    // Full-surface dismiss — window is transparent so this is invisible
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: SysTrayPopupState.close()
    }

    Rectangle {
        id: popupRect

        x: Math.max(0, Math.min(
               SysTrayPopupState.anchorX - implicitWidth + 18,
               win.width - implicitWidth))
        y: 0

        implicitHeight: Config.barHeight
        implicitWidth:  Math.max(Config.barHeight,
                                 trayRow.implicitWidth + Config.trayItemPadH * 2)

        radius: Config.barMode === "island" ? Config.islandRadius : Config.barRadius
        color:  Theme.cPanelBg
        border.width: 2
        border.color : Qt.rgba(Theme.cOnPrimaryFixedVariant.r,
                               Theme.cOnPrimaryFixedVariant.g,
                               Theme.cOnPrimaryFixedVariant.b,
                               1.00)

        Row {
            id: trayRow
            anchors.centerIn: parent
            spacing: Config.trayItemSpacing

            Repeater {
                model: SystemTray.items

                delegate: Item {
                    id: slot
                    required property SystemTrayItem modelData
                    required property int index

                    width:  Config.trayIconSz + Config.trayItemPadH * 2
                    height: Config.trayIconSz + Config.trayItemPadV * 2

                    readonly property string _src: {
                        const ic = slot.modelData.icon || ""
                        if (!ic) return ""
                        if (ic.startsWith("image://") || ic.startsWith("file://")) return ic
                        if (ic.startsWith("/")) return "file://" + ic
                        return ""
                    }

                    Image {
                        anchors.centerIn: parent
                        source:   slot._src
                        width:    Config.trayIconSz
                        height:   Config.trayIconSz
                        smooth:   true
                        mipmap:   true
                        fillMode: Image.PreserveAspectFit
                        opacity:  status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    opacity: slotMouse.containsMouse ? 0.6 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 80 } }

                    QsMenuAnchor {
                        id: menuAnchor
                        menu: slot.modelData.menu
                        anchor.window: win

                        readonly property real _slotSurfaceX:
                            popupRect.x + slot.mapToItem(popupRect, 0, 0).x
                        readonly property rect _anchorRect: Qt.rect(
                            _slotSurfaceX,
                            win._barAtBottom
                                ? popupRect.y + 3
                                : popupRect.y + popupRect.implicitHeight + 3,
                            slot.width,
                            win._barAtBottom
                                ? win.implicitHeight - popupRect.y - 3
                                : 1
                        )
                        anchor.rect: _anchorRect
                    }

                    MouseArea {
                        id: slotMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor

                        onClicked: function(mouse) {
                            if (mouse.button === Qt.RightButton && slot.modelData.hasMenu) {
                                menuAnchor.open()
                            } else if (mouse.button === Qt.MiddleButton) {
                                slot.modelData.secondaryActivate()
                            } else {
                                slot.modelData.activate()
                            }
                        }
                    }
                }
            }
        }
    }
}
