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
    readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop) : Config.outerMarginTop) + Config.barHeight + 4
    readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom) : Config.outerMarginBottom) + Config.barHeight + 4
    readonly property real _panelMargin:  Config.outerMarginSide * 2 

    anchors { top: !_barAtBottom; bottom: _barAtBottom; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
        right:  _panelMargin + 142
    }
    // _pad drives symmetric padding on all sides, sourced from bar's outerMarginTop
    readonly property real _pad: Config.outerMarginTop
    // Minimum slot = 24px icon + pad on both sides so pill never collapses when empty
    readonly property real _minSlot: 28 + _pad * 2

    implicitHeight: _minSlot
    implicitWidth:  popupRect.implicitWidth
    exclusionMode: ExclusionMode.Ignore

    // Full-surface dismiss — window is transparent so this is invisible
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: SysTrayPopupState.close()
    }

    Rectangle {
        id: popupRect
        anchors.fill: parent
        y: 0

        implicitHeight: win._minSlot
        implicitWidth:  Math.max(win._minSlot, trayRow.implicitWidth + win._pad * 2)

        radius: implicitHeight / 2
        color: Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

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

                    width:  Config.trayIconSz
                    height: Config.trayIconSz

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
                        width:    24
                        height:   24
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
