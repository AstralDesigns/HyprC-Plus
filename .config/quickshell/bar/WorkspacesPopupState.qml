pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Singleton {
    id: root

    property bool visible: false
    property int hoveredWorkspaceId: -1
    property var windowList: []

    readonly property var _getClientsProc: Process {
        id: proc
        command: ["hyprctl", "clients", "-j"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.windowList = JSON.parse(this.text)
                } catch (e) {
                    root.windowList = []
                }
            }
        }
    }

    readonly property var _pollTimer: Timer {
        interval: 1000
        running: root.visible
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!proc.running) proc.running = true
    }

    readonly property var _closeTimer: Timer {
        interval: 350
        repeat: false
        onTriggered: {
            root.visible = false
            root.tileTooltipVisible = false
        }
    }

    property real hoveredWsX: -1
    property real hoveredWsWidth: 0

    function hoverWorkspace(wsId, posX, itemWidth) {
        _closeTimer.stop()
        root.hoveredWorkspaceId = wsId
        if (posX !== undefined && posX >= 0) root.hoveredWsX = posX
        if (itemWidth !== undefined && itemWidth > 0) root.hoveredWsWidth = itemWidth
        root.visible = true
        if (!proc.running) proc.running = true
    }

    function leaveWorkspace(wsId) {
        _closeTimer.restart()
    }

    function keepOpen() {
        _closeTimer.stop()
        root.visible = true
    }

    function close() {
        _closeTimer.stop()
        root.visible = false
        root.tileTooltipVisible = false
    }

    function windowsForWorkspace(wsId) {
        if (!root.windowList) return []
        return root.windowList
            .filter(w => w.workspace && w.workspace.id === wsId && w.mapped !== false)
            // Reading order (top-to-bottom, then left-to-right) based on each
            // window's actual on-screen position — matches the real tiling
            // arrangement rather than hyprctl's internal client-list order
            // (roughly creation order).
            .sort((a, b) => {
                const ay = (a.at && a.at[1]) || 0, by = (b.at && b.at[1]) || 0
                if (ay !== by) return ay - by
                const ax = (a.at && a.at[0]) || 0, bx = (b.at && b.at[0]) || 0
                return ax - bx
            })
    }

    // ── Tile tooltip (per-window icon inside the popup) ────────────────────
    // Rendered as its own top-level surface (WorkspaceTileTooltip.qml) so it
    // can freely overflow above/below/around the small WorkspacesPopup window
    // instead of being clipped to it.
    property bool tileTooltipVisible: false
    property string tileTooltipText: ""
    property real   tileTooltipCenterX: 0   // absolute screen x of tile center

    function showTileTooltip(text, centerX) {
        root.tileTooltipText    = text
        root.tileTooltipCenterX = centerX
        root.tileTooltipVisible = true
    }

    function hideTileTooltip() {
        root.tileTooltipVisible = false
    }
}
