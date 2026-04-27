import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import ".."

Item {
    id: root

    property var rootWindow

    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  SystemTray.items.values.length > 0 ? trayRow.implicitWidth + Config.moduleHPad * 2 : 0
    implicitHeight: Config.barHeight

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: Config.traySpacing

        Repeater {
            model: SystemTray.items

            delegate: Item {
                id: trayItem
                required property SystemTrayItem modelData

                width:  Config.trayIconSize + 2
                height: Config.trayIconSize + 2

                // ── Icon resolution ────────────────────────────────────────
                // modelData.icon can be:
                //   image://snitray/<id>  — Quickshell-rendered pixmap (webapps, Electron)
                //   /absolute/path.png   — already resolved
                //   bare-icon-name       — needs XDG lookup via resolver script
                //
                // We always show the raw source first (covers image:// and absolute paths
                // instantly), and only fire the resolver for bare names.
                property string _resolvedIcon: ""
                property bool   _needsResolve: {
                    const ic = trayItem.modelData.icon || ""
                    return ic !== "" && !ic.startsWith("image://") &&
                           !ic.startsWith("file://") && !ic.startsWith("/")
                }

                // Resolver process — one per tray item, kept alive
                Process {
                    id: resolverProc
                    property string _result: ""
                    command: ["python3", Config.barDir + "/tray-icon-resolve.py"]
                    running: trayItem._needsResolve
                    stdin: StdinWriter {
                        // Feed the icon name once the process is running
                        property bool _sent: false
                        onAvailableChanged: {
                            if (available && !_sent) {
                                _sent = true
                                write(trayItem.modelData.icon + "\n")
                            }
                        }
                    }
                    stdout: SplitParser {
                        splitMarker: "\n"
                        onRead: function(line) {
                            const p = line.trim()
                            if (p) trayItem._resolvedIcon = p
                        }
                    }
                }

                // Re-resolve whenever the icon name changes
                onModelDataChanged: {
                    _resolvedIcon = ""
                }

                // Effective source: resolved path > raw icon (image:// or absolute) > ""
                readonly property string _iconSource: {
                    if (_resolvedIcon) return "file://" + _resolvedIcon
                    const ic = modelData.icon || ""
                    if (!ic) return ""
                    if (ic.startsWith("image://") || ic.startsWith("file://")) return ic
                    if (ic.startsWith("/")) return "file://" + ic
                    return ""   // waiting for resolver
                }

                Image {
                    anchors.centerIn: parent
                    source: trayItem._iconSource
                    width:  Config.trayIconSize
                    height: Config.trayIconSize
                    smooth: true
                    mipmap: true
                    fillMode: Image.PreserveAspectFit
                    // Fade in when source resolves
                    opacity: status === Image.Ready ? 1.0 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                }

                opacity: itemMouse.containsMouse ? 0.6 : 1.0
                Behavior on opacity { NumberAnimation { duration: 80 } }

                QsMenuAnchor {
                    id: menuAnchor
                    menu: trayItem.modelData.menu
                    anchor.window: root.rootWindow
                    anchor.rect: Qt.rect(
                        trayItem.mapToItem(null, 0, 0).x,
                        trayItem.mapToItem(null, 0, 0).y,
                        trayItem.width,
                        trayItem.height
                    )
                }

                MouseArea {
                    id: itemMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor

                    onClicked: function(mouse) {
                        if (mouse.button === Qt.RightButton && trayItem.modelData.hasMenu) {
                            menuAnchor.open()
                        } else if (mouse.button === Qt.MiddleButton) {
                            trayItem.modelData.secondaryActivate()
                        } else {
                            trayItem.modelData.activate()
                        }
                    }
                }
            }
        }
    }
}
