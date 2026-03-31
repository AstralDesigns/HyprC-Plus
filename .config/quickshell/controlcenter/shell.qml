import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// ═══════════════════════════════════════════════════════════════════════════
//  shell.qml — Main entry point for the Quickshell control center.
//  A layer-shell overlay panel toggled via IPC (qs ipc -c controlcenter).
// ═══════════════════════════════════════════════════════════════════════════

ShellRoot {
    id: root

    // ── IPC handler for toggling ─────────────────────────────────────────
    IpcHandler {
        target: "controlcenter"

        function toggleVisibility() {
            ControlCenterState.toggle()
        }
    }

    // ── The layer-shell panel window ─────────────────────────────────────
    PanelWindow {
        id: ccWindow

        visible: ControlCenterState.visible

        // Layer shell configuration
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "controlcenter"

        // Anchor to right side, vertically centered
        anchors {
            right: true
            top: true
            bottom: true
        }

        margins {
            right: 8
            top: 8
            bottom: 8
        }

        width: CCConfig.ccWidth
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"

        // ── Background with blur-style look ──────────────────────────────
        Rectangle {
            id: background
            anchors.fill: parent
            radius: CCConfig.ccRadius
            color: Qt.rgba(
                CCTheme.cBackground.r,
                CCTheme.cBackground.g,
                CCTheme.cBackground.b,
                CCConfig.bgAlpha
            )
            border.width: 1
            border.color: Qt.rgba(
                CCTheme.cPrimary.r,
                CCTheme.cPrimary.g,
                CCTheme.cPrimary.b,
                0.15
            )

            // ── Main content layout ──────────────────────────────────────
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 2

                // ── User profile section ─────────────────────────────────
                UserProfile {
                    Layout.fillWidth: true
                    visible: ControlCenterState.activeTab !== "imagepicker"
                }

                // ── Image picker (replaces everything when active) ───────
                ImagePicker {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: ControlCenterState.activeTab === "imagepicker"
                }

                // ── Tab bar ──────────────────────────────────────────────
                Flow {
                    id: tabBar
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    spacing: 3
                    visible: ControlCenterState.activeTab !== "imagepicker"

                    Repeater {
                        model: [
                            { id: "hyprland", icon: "\uf31b", label: "Hyprland" },
                            { id: "themes",   icon: "\udb84\udd0e", label: "Themes" },
                            { id: "dock",     icon: "\udb80\ude92", label: "Dock" },
                            { id: "menus",    icon: "\udb80\udcc5", label: "Menus" },
                            { id: "sddm",     icon: "\udb80\udd0b", label: "SDDM" },
                            { id: "bar",      icon: "\udb81\udd8d", label: "Bar" }
                        ]

                        Rectangle {
                            required property var modelData
                            width: tabLbl.implicitWidth + 16
                            height: 24
                            radius: 8
                            color: ControlCenterState.activeTab === modelData.id
                                ? Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.18)
                                : tabMa.containsMouse
                                    ? Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.08)
                                    : "transparent"
                            border.width: ControlCenterState.activeTab === modelData.id ? 1 : 0
                            border.color: CCTheme.cPrimaryFixedDim

                            Text {
                                id: tabLbl
                                anchors.centerIn: parent
                                text: modelData.icon + " " + modelData.label
                                color: ControlCenterState.activeTab === modelData.id
                                    ? CCTheme.cPrimary
                                    : Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.6)
                                font.family: CCConfig.labelFont
                                font.pixelSize: 10
                                font.weight: ControlCenterState.activeTab === modelData.id ? Font.Bold : Font.Normal
                            }

                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ControlCenterState.switchTab(modelData.id)
                            }
                        }
                    }
                }

                // ── Separator ────────────────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.1)
                    visible: ControlCenterState.activeTab !== "imagepicker" && ControlCenterState.activeTab !== ""
                }

                // ── Scrollable tab content area ──────────────────────────
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: tabContent.implicitHeight
                    clip: true
                    visible: ControlCenterState.activeTab !== "imagepicker"
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 3000

                    ColumnLayout {
                        id: tabContent
                        width: parent.width
                        spacing: 0

                        // Welcome / collapsed state
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 20
                            visible: ControlCenterState.activeTab === ""
                            text: "Select a tab above"
                            color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.4)
                            font.family: CCConfig.labelFont
                            font.pixelSize: 12
                        }

                        // Tab content loaders
                        Loader {
                            Layout.fillWidth: true
                            active: ControlCenterState.activeTab === "hyprland"
                            source: "tabs/HyprlandTab.qml"
                        }

                        Loader {
                            Layout.fillWidth: true
                            active: ControlCenterState.activeTab === "themes"
                            source: "tabs/ThemesTab.qml"
                        }

                        Loader {
                            Layout.fillWidth: true
                            active: ControlCenterState.activeTab === "dock"
                            source: "tabs/DockTab.qml"
                        }

                        Loader {
                            Layout.fillWidth: true
                            active: ControlCenterState.activeTab === "menus"
                            source: "tabs/MenusTab.qml"
                        }

                        Loader {
                            Layout.fillWidth: true
                            active: ControlCenterState.activeTab === "sddm"
                            source: "tabs/SDDMTab.qml"
                        }

                        Loader {
                            Layout.fillWidth: true
                            active: ControlCenterState.activeTab === "bar"
                            source: "tabs/BarTab.qml"
                        }
                    }
                }

                // ── Close button at the bottom ───────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 28
                    radius: 8
                    color: closeMa.containsMouse
                        ? Qt.rgba(CCTheme.cErr.r, CCTheme.cErr.g, CCTheme.cErr.b, 0.15)
                        : Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.06)
                    visible: ControlCenterState.activeTab !== "imagepicker"

                    Text {
                        anchors.centerIn: parent
                        text: "\uf00d  Close"
                        color: closeMa.containsMouse ? CCTheme.cErr : CCTheme.cPrimary
                        font.family: CCConfig.labelFont
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: closeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: ControlCenterState.close()
                    }
                }
            }
        }
    }
}
