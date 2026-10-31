import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../services"
import "."

Scope {
    id: overviewScope
    Variants {
        id: overviewVariants
        model: Quickshell.screens
        PanelWindow {
            id: root
            required property var modelData
            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            screen: modelData
            visible: GlobalStates.overviewOpen

            WlrLayershell.namespace: "quickshell:overview"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            color: "transparent"

            // True fullscreen: ignore the reserved exclusive zones (bar + shell-res
            // edges) so this edge-anchored surface spans the whole monitor (mimic
            // StartMenuPopup). columnLayout is centered on the surface below.
            exclusionMode: ExclusionMode.Ignore

            // Full-surface click-away + no fall-through. The old
            // `mask: Region { item: columnLayout }` clipped the surface's INPUT
            // region to the columns, so the mouse fell through the empty
            // (transparent) area to the windows below — it looked like the
            // fullscreen backdrop wasn't there. With the mask gone the whole
            // surface captures input, and this z:-1 MouseArea (under the columns)
            // closes the overview on a click anywhere outside them, replacing the
            // dismiss that used to rely on the fall-through.
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: GlobalStates.overviewOpen = false
            }

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            HyprlandFocusGrab {
                id: grab
                windows: [root]
                property bool canBeActive: root.monitorIsFocused
                active: false
                onCleared: () => {
                    if (!active)
                        GlobalStates.overviewOpen = false;
                }
            }

            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen) {
                        GlobalStates.resetStripScroll();
                        GlobalStates.resetWinFocus();
                        delayedGrabTimer.start();
                    }
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Config.options.hacks.arbitraryRaceConditionDelay
                repeat: false
                onTriggered: {
                    if (!grab.canBeActive)
                        return;
                    grab.active = GlobalStates.overviewOpen;
                }
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight

            Item {
                id: keyHandler
                anchors.fill: parent
                visible: GlobalStates.overviewOpen
                focus: GlobalStates.overviewOpen

                Keys.onPressed: event => {
                    const currentId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
                    const numWs = Config.options.overview.numWorkspaces;
                    const widget = overviewLoader.item;
                    const wins = widget ? widget.windowsForWorkspace(currentId) : [];
                    const winCount = wins.length;

                    // Enter: close overview first (releases keyboard/focus grab), then
                    // dispatch focuswindow — same order as mouse click which works correctly.
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        const idx = GlobalStates.focusedWinIndex;
                        if (idx >= 0 && idx < winCount) {
                            const addr = `0x${wins[idx].HyprlandToplevel.address}`;
                            const wd = widget.windowByAddress[addr];
                            if (wd) {
                                const targetAddr = wd.address;
                                // Close overview first so it releases Wayland focus/grab
                                GlobalStates.overviewOpen = false;
                                // Then dispatch focus after overview has closed
                                Qt.callLater(() => {
                                    Hyprland.dispatch(`hl.dsp.focus({ window = 'address:${targetAddr}' })`);
                                });
                            } else {
                                GlobalStates.overviewOpen = false;
                            }
                        } else {
                            GlobalStates.overviewOpen = false;
                        }
                        event.accepted = true;
                        return;
                    }

                    // Escape: close
                    if (event.key === Qt.Key_Escape) {
                        GlobalStates.overviewOpen = false;
                        event.accepted = true;
                        return;
                    }

                    let targetId = null;

                    // Up/K — previous workspace, reset win focus
                    if (event.key === Qt.Key_Up || event.key === Qt.Key_K) {
                        targetId = currentId - 1;
                        if (targetId < 1) targetId = numWs;
                        GlobalStates.resetStripScroll();
                        GlobalStates.resetWinFocus();
                    // Down/J — next workspace, reset win focus
                    } else if (event.key === Qt.Key_Down || event.key === Qt.Key_J) {
                        targetId = currentId + 1;
                        if (targetId > numWs) targetId = 1;
                        GlobalStates.resetStripScroll();
                        GlobalStates.resetWinFocus();
                    // Left/H — cycle to previous window in active workspace
                    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        if (winCount > 0) {
                            const cur = GlobalStates.focusedWinIndex;
                            GlobalStates.focusedWinIndex = cur <= 0 ? winCount - 1 : cur - 1;
                        }
                        event.accepted = true;
                        return;
                    // Right/L — cycle to next window in active workspace
                    } else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        if (winCount > 0) {
                            const cur = GlobalStates.focusedWinIndex;
                            GlobalStates.focusedWinIndex = cur < 0 ? 0 : (cur + 1) % winCount;
                        }
                        event.accepted = true;
                        return;
                    // Number keys 1-9 jump directly to workspace N
                    } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
                        targetId = event.key - Qt.Key_0;
                        if (targetId > numWs) targetId = null;
                        GlobalStates.resetStripScroll();
                        GlobalStates.resetWinFocus();
                    // 0 jumps to workspace 10
                    } else if (event.key === Qt.Key_0) {
                        if (numWs >= 10) targetId = 10;
                        GlobalStates.resetStripScroll();
                        GlobalStates.resetWinFocus();
                    }

                    if (targetId !== null) {
                        Hyprland.dispatch("hl.dsp.focus({ workspace = " + targetId + " })");
                        event.accepted = true;
                    }
                }
            }

            // Mouse wheel anywhere on panel navigates workspaces
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: event => {
                    const currentId = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1;
                    const numWs = Config.options.overview.numWorkspaces;
                    let targetId;
                    if (event.angleDelta.y > 0) {
                        targetId = currentId - 1;
                        if (targetId < 1) targetId = numWs;
                    } else {
                        targetId = currentId + 1;
                        if (targetId > numWs) targetId = 1;
                    }
                    GlobalStates.resetWinFocus();
                    GlobalStates.resetStripScroll();
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + targetId + " })");
                }
            }

            ColumnLayout {
                id: columnLayout
                visible: GlobalStates.overviewOpen
                anchors {
                    centerIn: parent
                }

                Loader {
                    id: overviewLoader
                    active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                    sourceComponent: OverviewWidget {
                        panelWindow: root
                        visible: true
                    }
                }
            }
        }
    }
    
    IpcHandler {
        target: "overview"

        function toggle() {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close() {
            GlobalStates.overviewOpen = false;
        }
        function open() {
            GlobalStates.overviewOpen = true;
        }
    }
}
