import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

PanelWindow {
    id: win
    color: "transparent"
    visible: WorkspacesPopupState.visible

    WlrLayershell.namespace: "quickshell"

    readonly property bool _barAtBottom:  Config.barPosition === "bottom"
    readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop) : Config.outerMarginTop) + Config.barHeight + 4
    readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom) : Config.outerMarginBottom) + Config.barHeight + 4
    readonly property real _panelMargin: Config.barMode === "shell" ? Config.shellModuleSideMargin : Config.outerMarginSide

    readonly property real _calcLeft: WorkspacesPopupState.hoveredWsX >= 0
        ? Math.max(_panelMargin, _panelMargin + WorkspacesPopupState.hoveredWsX + (WorkspacesPopupState.hoveredWsWidth / 2) - (implicitWidth / 2))
        : _panelMargin

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
        left:   _calcLeft
    }

    implicitHeight: 32
    implicitWidth:  popupRect.implicitWidth
    exclusionMode: ExclusionMode.Ignore

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: WorkspacesPopupState.close()
    }

    Rectangle {
        id: popupRect
        anchors.fill: parent
        y: 0

        implicitHeight: 32
        implicitWidth:  Math.max(24, wsAppRow.implicitWidth + 14)

        radius: Math.min(22, implicitHeight / 2)
        color: Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

        HoverHandler {
            onHoveredChanged: {
                if (hovered) WorkspacesPopupState.keepOpen()
                else WorkspacesPopupState.leaveWorkspace()
            }
        }

        Row {
            id: wsAppRow
            anchors.centerIn: parent
            spacing: 6

            readonly property var _wsWindows: WorkspacesPopupState.windowsForWorkspace(WorkspacesPopupState.hoveredWorkspaceId)

            Text {
                visible: wsAppRow._wsWindows.length === 0
                text: "󰝾"
                color: Theme.cOnSurfVar
                font.family: Config.fontFamily
                font.pixelSize: 16
            }

            Repeater {
                model: wsAppRow._wsWindows

                delegate: Item {
                    id: tile
                    required property var modelData

                    width:  20
                    height: 20

                    readonly property string _cls:  modelData["initialClass"] || modelData["class"] || ""
                    readonly property string _icon: _cls.toLowerCase()

                    property string _resolvedIcon: ""

                    Process {
                        id: iconResolver
                        property string _buf: ""
                        command: ["python3", Config.barDir + "/tray-icon-resolve.py", tile._icon]
                        running: tile._icon !== ""
                        stdout: SplitParser {
                            splitMarker: "\n"
                            onRead: function(line) { iconResolver._buf += line }
                        }
                        onExited: {
                            const p = _buf.trim()
                            if (p) tile._resolvedIcon = p
                        }
                    }

                    readonly property string _iconSrc: {
                        const r = _resolvedIcon
                        if (r !== "") {
                            if (r.startsWith("file://") || r.startsWith("image://")) return r
                            if (r.startsWith("/")) return "file://" + r
                            return Quickshell.iconPath(r, "application-x-executable")
                        }
                        if (_icon.startsWith("file://") || _icon.startsWith("image://")) return _icon
                        if (_icon.startsWith("/")) return "file://" + _icon
                        return Quickshell.iconPath(_icon, "application-x-executable")
                    }

                    Image {
                        anchors.centerIn: parent
                        source: tile._iconSrc
                        width: 20
                        height: 20
                        smooth: true
                        mipmap: true
                        fillMode: Image.PreserveAspectFit
                        opacity: status === Image.Ready ? 1.0 : 0.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }

                    MouseArea {
                        id: tileHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (tile.modelData.address) {
                                Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + tile.modelData.address + "' })")
                                WorkspacesPopupState.close()
                            }
                        }
                        onEntered: {
                            // Absolute screen x of this tile's center: win's own
                            // resolved left position (_calcLeft) + tile's offset
                            // within win's surface, mirroring the mapToItem(null,...)
                            // idiom Workspaces.qml uses to position WorkspacesPopup itself.
                            const p = tile.mapToItem(null, tile.width / 2, 0)
                            WorkspacesPopupState.showTileTooltip(
                                (tile.modelData.title || tile.modelData.initialTitle || "Unknown")
                                + "\n[" + tile._cls + "]",
                                win._calcLeft + p.x
                            )
                        }
                        onExited: WorkspacesPopupState.hideTileTooltip()
                    }
                }
            }
        }
    }
}
