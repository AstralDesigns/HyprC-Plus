import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.DBusMenu

// Styled tray context menu popup.
// Appears as a layer-shell Overlay strip just below the top bar.
// Content is positioned at TrayMenuState.anchorX horizontally.
PanelWindow {
    id: win
    color: "transparent"

    // ── QsMenuOpener: provides .children (UntypedObjectModel of QsMenuEntry) ───
    QsMenuOpener {
        id: menuOpener
        menu: TrayMenuState.menu
    }

    // ── Layer shell config ─────────────────────────────────────────────────
    // Horizontal strip anchored to the top of the screen, appearing below the bar.
    anchors { top: true; left: true; right: true }
    margins.top: Config.barHeight + Config.outerMarginTop + Config.outerMarginBottom + 3

    exclusionMode: ExclusionMode.Ignore

    implicitHeight: menuRect.implicitHeight + 8

    // ── Dismiss on click outside ───────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: TrayMenuState.close()
    }

    // ── Popup rectangle ────────────────────────────────────────────────────
    Rectangle {
        id: menuRect

        // Clamp so the menu stays on-screen horizontally.
        // Use win.width (real PanelWindow width = screen width) not implicitWidth (=0).
        x: Math.min(
               Math.max(0, TrayMenuState.anchorX),
               Math.max(0, win.width - implicitWidth - 8)
           )
        y: 4

        implicitWidth:  Math.max(160, menuCol.implicitWidth + 24)
        implicitHeight: menuCol.implicitHeight + 20

        color:        Theme.cOnSecondary
        radius:       20
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)

        // ── Menu items ───────────────────────────────────────────────────
        Column {
            id: menuCol
            anchors {
                fill:         parent
                topMargin:    10
                bottomMargin: 10
                leftMargin:   12
                rightMargin:  12
            }
            spacing: 2

            // QsMenuOpener.children is UntypedObjectModel of QsMenuEntry.
            // QsMenuEntry properties: text, isSeparator, enabled, hasChildren,
            // icon, checkState, buttonType.  sendTriggered() fires the DBus event.
            Repeater {
                model: menuOpener.children

                delegate: Item {
                    id: entryRoot
                    required property var modelData
                    required property int index

                    implicitWidth: modelData.isSeparator
                        ? 60
                        : (itemLabel.implicitWidth + 16
                           + (modelData.hasChildren ? 24 : 0))
                    height: modelData.isSeparator ? 9 : 30

                    // ── Separator ───────────────────────────────────────────────────
                    Rectangle {
                        visible:          entryRoot.modelData.isSeparator
                        anchors.centerIn: parent
                        width:  parent.width - 8
                        height: 1
                        color:  Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                        Theme.cPrimary.b, 0.8)
                    }

                    // ── Menu item ───────────────────────────────────────────────────
                    Rectangle {
                        id: itemBg
                        visible:      !entryRoot.modelData.isSeparator
                        anchors.fill: parent
                        radius:       8
                        opacity:      entryRoot.modelData.enabled ? 1.0 : 0.4
                        color:        itemHover.containsMouse
                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                      Theme.cPrimary.b, 0.12)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 80 } }

                        Text {
                            id: itemLabel
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left:        parent.left
                            anchors.leftMargin:  8
                            anchors.right:       arrowTxt.visible ? arrowTxt.left : parent.right
                            anchors.rightMargin: 4
                            text:           entryRoot.modelData.text
                            color:          Theme.cPrimary
                            font.family:    Config.labelFont
                            font.pixelSize: Config.labelFontSize
                            elide:          Text.ElideRight
                        }

                        Text {
                            id: arrowTxt
                            visible:               entryRoot.modelData.hasChildren ?? false
                            anchors.right:         parent.right
                            anchors.rightMargin:   8
                            anchors.verticalCenter: parent.verticalCenter
                            text:           "›"
                            color:          Theme.cOnSurfVar
                            font.pixelSize: Config.labelFontSize + 2
                        }

                        MouseArea {
                            id: itemHover
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled:      entryRoot.modelData.enabled
                            onClicked: {
                                // triggered() emits the QsMenuEntry signal from QML;
                                // connected C++ slots then dispatch the DBus Event.
                                // sendTriggered() is isMethodConstant=true (non-JS-invokable).
                                entryRoot.modelData.triggered()
                                Qt.callLater(function() { TrayMenuState.close() })
                            }
                        }
                    }
                }
            }
        }
    }
}
