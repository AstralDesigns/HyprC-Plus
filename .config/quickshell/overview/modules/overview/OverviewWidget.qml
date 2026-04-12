import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "../../common"
import "../../common/functions"
import "../../common/widgets"
import "../../services"
import "."

Item {
    id: root
    required property var panelWindow
    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(panelWindow.screen)
    property bool monitorIsFocused: (Hyprland.focusedMonitor?.name == monitor.name)
    property var windowByAddress: HyprlandData.windowByAddress
    property var monitorData: HyprlandData.monitors.find(m => m.id === root.monitor?.id)

    // Physical monitor dimensions in logical pixels (accounting for transform/rotation)
    property real monitorLogicalWidth: (monitorData?.transform % 2 === 1) ?
        (monitor.height / monitor.scale) : (monitor.width / monitor.scale)
    property real monitorLogicalHeight: (monitorData?.transform % 2 === 1) ?
        (monitor.width / monitor.scale) : (monitor.height / monitor.scale)

    // ── Layout constants ──────────────────────────────────────
    property real labelWidth: Config.options.overview.workspaceLabelWidth
    property real stripSpacing: Config.options.overview.windowStripSpacing
    property real rowSpacing: 4
    property real outerPadding: 10
    // Gap between the left (1-5) and right (6-10) columns
    property real columnGap: 8

    // Total workspaces and how many rows per column (ceiling for odd counts)
    property int numWorkspaces: Config.options.overview.numWorkspaces
    property int colRows: Math.ceil(numWorkspaces / 2)   // 5 for 10 workspaces

    // Active workspace id on this monitor
    property int activeWorkspaceId: monitor.activeWorkspace?.id ?? 1

    // Target floating panel height: 90% of screen minus topMargin and elevation margins
    property real targetPanelHeight: panelWindow.screen.height * 0.90 - 40 - Appearance.sizes.elevationMargin * 2

    // Auto-derive rowHeight so all colRows rows (per column) fit inside targetPanelHeight.
    // With 5 rows instead of 10, rows are roughly 2× taller.
    // Clamped between 55px (min readable) and 220px (raised to allow the taller rows).
    property real rowHeight: Math.min(220, Math.max(55,
        (targetPanelHeight - outerPadding * 2 - rowSpacing * (colRows - 1)) / colRows
    ))

    // Scale: map monitor height → rowHeight (used by OverviewWindow for window previews)
    property real scale: root.rowHeight / (monitorLogicalHeight > 0 ? monitorLogicalHeight : 1080)

    // Window preview cell dimensions (scaled from monitor size)
    property real previewMonitorWidth: monitorLogicalWidth * root.scale
    property real previewMonitorHeight: root.rowHeight

    // Total content height of one column (both columns are the same height)
    property real totalRowsHeight: rowHeight * colRows + rowSpacing * (colRows - 1)

    // Panel background height: prefer fitting all rows, hard-cap at targetPanelHeight
    property real panelContentHeight: Math.min(totalRowsHeight, targetPanelHeight - outerPadding * 2)

    // Total widget budget: how wide the whole overview should be.
    // Capped at 92% of screen so outer rounded corners always stay on-screen.
    // The second term mirrors the original single-column formula scaled to 2 columns,
    // so on large screens the widget doesn't balloon beyond a useful size.
    property real totalBudgetWidth: Math.min(
        panelWindow.screen.width * 0.92,
        labelWidth * 2 + columnGap + outerPadding * 2 + 2
            + Math.min(previewMonitorWidth * 3.5, panelWindow.screen.width * 0.44) * 2
    )

    // Per-column strip width: back-solve from the total budget.
    // Structural overhead = 2 labels + column gap + outer padding + border.
    // Floor at one monitor-width so the strip is always meaningful.
    property real stripVisibleWidth: Math.max(
        previewMonitorWidth,
        (totalBudgetWidth - labelWidth * 2 - columnGap - outerPadding * 2 - 2) / 2
    )

    // Single-column width (label + strip), reused by both left and right columns
    property real columnWidth: labelWidth + stripVisibleWidth

    // Total widget width flows naturally from the column widths (≈ totalBudgetWidth)
    property real totalWidth: columnWidth * 2 + columnGap + outerPadding * 2 + 2

    implicitWidth: totalWidth
    implicitHeight: panelContentHeight + outerPadding * 2

    // ── Helper functions (unchanged) ──────────────────────────

    // Returns windows for a given workspace id, sorted by stacking order
    function windowsForWorkspace(wsId) {
        return ToplevelManager.toplevels.values.filter(toplevel => {
            const addr = `0x${toplevel.HyprlandToplevel.address}`
            const win = windowByAddress[addr]
            return win?.workspace?.id === wsId
        }).sort((a, b) => {
            const addrA = `0x${a.HyprlandToplevel.address}`
            const addrB = `0x${b.HyprlandToplevel.address}`
            const winA = windowByAddress[addrA]
            const winB = windowByAddress[addrB]
            if (winA?.pinned !== winB?.pinned) return winA?.pinned ? 1 : -1
            if (winA?.floating !== winB?.floating) return winA?.floating ? 1 : -1
            return (winA?.at?.[0] ?? 0) - (winB?.at?.[0] ?? 0)
        })
    }

    // Check if a workspace id has any windows
    function workspaceHasWindows(wsId) {
        return HyprlandData.windowList.some(w => w.workspace?.id === wsId)
    }

    // Minimum relative X across all windows in wsId (scrolling layout support)
    function canvasMinRelXForWorkspace(wsId) {
        const wins = HyprlandData.windowList.filter(w => w.workspace?.id === wsId)
        if (wins.length === 0) return 0
        let minRelX = 0
        for (const w of wins) {
            const monId = w.monitor ?? -1
            const mon = HyprlandData.monitors.find(m => m.id === monId)
            const monX = mon?.x ?? 0
            const monResL = mon?.reserved?.[0] ?? 0
            const relX = (w.at?.[0] ?? 0) - monX - monResL
            if (relX < minRelX) minRelX = relX
        }
        return minRelX
    }

    // Canvas width = full horizontal span of all windows at scaled coords
    function canvasWidthForWorkspace(wsId) {
        const wins = HyprlandData.windowList.filter(w => w.workspace?.id === wsId)
        if (wins.length === 0) return root.previewMonitorWidth
        const minRelX = canvasMinRelXForWorkspace(wsId)
        let maxRight = root.previewMonitorWidth
        for (const w of wins) {
            const monId = w.monitor ?? -1
            const mon = HyprlandData.monitors.find(m => m.id === monId)
            const monX = mon?.x ?? 0
            const monResL = mon?.reserved?.[0] ?? 0
            const monResT = mon?.reserved?.[1] ?? 0
            const monResB = mon?.reserved?.[3] ?? 0
            const monH = (mon?.height ?? root.monitorLogicalHeight)
            const monS = (mon?.scale ?? 1)
            const transform = mon?.transform ?? 0
            const srcMonH = (transform % 2 === 1)
                ? (mon?.width ?? root.monitorLogicalWidth) / monS - monResT - monResB
                : monH / monS - monResT - monResB
            const wScale = root.rowHeight / (srcMonH > 0 ? srcMonH : root.monitorLogicalHeight)
            const relX = (w.at?.[0] ?? 0) - monX - monResL
            const scaledX = (relX - minRelX) * wScale
            const scaledW = (w.size?.[0] ?? 0) * wScale
            const right = scaledX + scaledW
            if (right > maxRight) maxRight = right
        }
        return maxRight
    }

    // ── Background + content ──────────────────────────────────

    Rectangle {
        id: overviewBackground
        anchors.fill: parent
        implicitWidth: root.totalWidth
        implicitHeight: root.panelContentHeight + root.outerPadding * 2
        radius: Appearance.rounding.large
        color: Appearance.colors.colOverviewBg
        border.width: 0

        // Wheel over the overview cycles workspaces
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
                Hyprland.dispatch("workspace " + targetId);
            }
        }

        // ── Two-column scrollable container ───────────────────
        ScrollView {
            id: outerScrollView
            anchors {
                fill: parent
                margins: root.outerPadding
            }
            contentWidth: availableWidth
            // Drive height from the taller column (both should be equal, but safe for
            // hideEmptyWorkspaces cases where one column may collapse rows to 0)
            contentHeight: Math.max(leftCol.implicitHeight, rightCol.implicitHeight)
            wheelEnabled: false
            ScrollBar.vertical: ScrollBar {
                policy: Math.max(leftCol.implicitHeight, rightCol.implicitHeight) > outerScrollView.height
                        ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                width: 6
            }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

            // Side-by-side columns
            RowLayout {
                id: columnsRow
                width: outerScrollView.availableWidth
                height: Math.max(leftCol.implicitHeight, rightCol.implicitHeight)
                spacing: root.columnGap

                // ── LEFT column: workspaces 1 … colRows ──────
                Column {
                    id: leftCol
                    Layout.fillHeight: true
                    // Each column takes exactly half the available width minus half the gap
                    Layout.preferredWidth: (outerScrollView.availableWidth - root.columnGap) / 2
                    spacing: root.rowSpacing

                    Repeater {
                        id: leftRepeater
                        model: root.colRows  // 5

                        delegate: wsRowDelegate
                    }
                }

                // ── RIGHT column: workspaces colRows+1 … numWorkspaces ──
                Column {
                    id: rightCol
                    Layout.fillHeight: true
                    Layout.preferredWidth: (outerScrollView.availableWidth - root.columnGap) / 2
                    spacing: root.rowSpacing

                    Repeater {
                        id: rightRepeater
                        // Remaining workspaces (handles odd numWorkspaces gracefully)
                        model: root.numWorkspaces - root.colRows  // 5

                        // wsId offset: right column starts at colRows+1
                        delegate: wsRowDelegate
                    }
                }
            }
        }
    }

    // ── Workspace row delegate ────────────────────────────────
    // Shared by both left and right Repeaters.
    // When used in leftRepeater:  wsId = index + 1
    // When used in rightRepeater: wsId = index + root.colRows + 1
    Component {
        id: wsRowDelegate

        Item {
            id: wsRow
            required property int index

            // Determine which Repeater owns this delegate via parent chain, then compute wsId.
            // parent of a Repeater delegate = the Column; parent.parent = the Repeater.
            // We check which Repeater objectName this belongs to.
            readonly property bool isRightColumn: parent === rightCol
            property int wsId: isRightColumn ? (index + root.colRows + 1) : (index + 1)

            property bool isActive: wsId === root.activeWorkspaceId
            property bool hasWindows: root.workspaceHasWindows(wsId)
            property bool isDragTarget: false

            // Use the column's actual width so strips fill their column exactly
            width: parent.width
            height: (Config.options.overview.hideEmptyWorkspaces && !hasWindows && !isActive)
                    ? 0 : root.rowHeight
            visible: height > 0

            // Full-row drop target (label + strip)
            DropArea {
                anchors.fill: parent
                onEntered: wsRow.isDragTarget = true
                onExited:  wsRow.isDragTarget = false
                onDropped: drop => {
                    wsRow.isDragTarget = false
                    const addr = drop.source?.windowAddress
                    if (addr && drop.source?.sourceWorkspaceId !== wsRow.wsId) {
                        Hyprland.dispatch(`movetoworkspacesilent ${wsRow.wsId},address:${addr}`)
                    }
                }
            }

            // Row background
            Rectangle {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: wsRow.isActive
                       ? Appearance.colors.colOverviewRowBg
                       : wsRow.isDragTarget
                         ? ColorUtils.transparentize(Appearance.colors.colOverviewRowBg, 0.7)
                         : Appearance.colors.colOverviewBg
                border.width: wsRow.isActive ? 2 : (wsRow.isDragTarget ? 1 : 0)
                border.color: wsRow.isActive
                              ? Appearance.colors.colOverviewText
                              : ColorUtils.transparentize(Appearance.colors.colOverviewText, 0.7)

                Behavior on color {
                    ColorAnimation { duration: 120 }
                }
                Behavior on border.color {
                    ColorAnimation { duration: 120 }
                }
            }

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── Workspace label cell ──────────────────────
                Rectangle {
                    id: labelCell
                    Layout.preferredWidth: root.labelWidth
                    Layout.fillHeight: true
                    color: "transparent"
                    radius: Appearance.rounding.small

                    // Active accent stripe on left edge
                    Rectangle {
                        visible: wsRow.isActive
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                            topMargin: 8
                            bottomMargin: 8
                        }
                        width: 3
                        radius: 2
                        color: Appearance.colors.colOverviewText
                    }

                    StyledText {
                        anchors.centerIn: parent
                        text: wsRow.wsId
                        font {
                            pixelSize: Appearance.font.pixelSize.normal
                            weight: wsRow.isActive ? Font.DemiBold : Font.Normal
                            family: Appearance.font.family.expressive
                        }
                        color: Appearance.colors.colOverviewText
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            GlobalStates.overviewOpen = false
                            Hyprland.dispatch(`workspace ${wsRow.wsId}`)
                        }
                    }
                }

                // Thin divider
                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 10
                    Layout.bottomMargin: 10
                    color: ColorUtils.transparentize(Appearance.colors.colOverviewText, 0.85)
                }

                // ── Window preview strip ──────────────────────
                Item {
                    id: stripContainer
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    // Empty workspace hint
                    StyledText {
                        anchors.centerIn: parent
                        visible: !wsRow.hasWindows
                        text: wsRow.isActive ? "active · empty" : "empty"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ColorUtils.transparentize(Appearance.colors.colOverviewText, 0.55)
                    }

                    // Flickable for horizontal scrolling inside the strip
                    Flickable {
                        id: stripFlick
                        anchors.fill: parent
                        clip: true
                        contentWidth: wsCanvas.width
                        contentHeight: height
                        interactive: true
                        flickableDirection: Flickable.HorizontalFlick
                        boundsMovement: Flickable.StopAtBounds
                        ScrollBar.horizontal: ScrollBar {
                            policy: wsCanvas.width > stripFlick.width
                                    ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                            height: 4
                        }

                        // Respond to keyboard scroll commands when this is the active row
                        Connections {
                            target: GlobalStates
                            function onActiveWindowStripScrollXChanged() {
                                if (!wsRow.isActive) return;
                                const clamped = Math.max(0, Math.min(
                                    GlobalStates.activeWindowStripScrollX,
                                    Math.max(0, wsCanvas.width - stripFlick.width)
                                ));
                                stripFlick.contentX = clamped;
                            }
                        }

                        // Canvas: wide enough for all windows at their real scaled positions
                        Item {
                            id: wsCanvas
                            width: root.canvasWidthForWorkspace(wsRow.wsId)
                            height: root.rowHeight

                            Repeater {
                                model: ScriptModel {
                                    values: root.windowsForWorkspace(wsRow.wsId)
                                }

                                delegate: Item {
                                    id: winCell
                                    required property var modelData
                                    required property int index

                                    property var address: `0x${modelData.HyprlandToplevel.address}`
                                    property var winData: root.windowByAddress[address]
                                    property int winMonitorId: winData?.monitor ?? -1
                                    property var winMonitorData: HyprlandData.monitors.find(m => m.id === winMonitorId)

                                    // Source monitor height for this window
                                    property real srcMonH: {
                                        const md = winMonitorData
                                        if (!md) return root.monitorLogicalHeight
                                        return (md.transform % 2 === 1)
                                            ? (md.width  / md.scale) - (md.reserved?.[1] ?? 0) - (md.reserved?.[3] ?? 0)
                                            : (md.height / md.scale) - (md.reserved?.[1] ?? 0) - (md.reserved?.[3] ?? 0)
                                    }
                                    property real winScale: root.rowHeight / (srcMonH > 0 ? srcMonH : root.monitorLogicalHeight)

                                    // Canvas X offset: shift by -minRelX (scrolling layout support)
                                    property real winXOffset: -root.canvasMinRelXForWorkspace(wsRow.wsId) * winCell.winScale

                                    x: 0
                                    y: 0
                                    width: wsCanvas.width
                                    height: root.rowHeight
                                    z: index

                                    property bool hovered: false
                                    property bool pressed: false
                                    property string windowAddress: winData?.address ?? ""
                                    property int sourceWorkspaceId: wsRow.wsId
                                    property bool keyboardFocused: wsRow.isActive
                                        && GlobalStates.focusedWinIndex === winCell.index

                                    OverviewWindow {
                                        id: winPreview
                                        toplevel: winCell.modelData
                                        windowData: winCell.winData
                                        monitorData: winCell.winMonitorData
                                        scale: winCell.winScale
                                        availableWorkspaceWidth: wsCanvas.width
                                        availableWorkspaceHeight: root.rowHeight
                                        widgetMonitorId: root.monitor.id
                                        hovered: winCell.hovered || winCell.keyboardFocused
                                        pressed: winCell.pressed
                                        xOffset: winCell.winXOffset
                                        yOffset: 0
                                        restrictToWorkspace: true

                                        property string windowAddress: winCell.winData?.address ?? ""
                                        property int sourceWorkspaceId: wsRow.wsId
                                        Drag.active: winCell.pressed && dragArea.drag.active
                                        Drag.source: winPreview
                                    }

                                    // Keyboard-focus highlight ring + auto-scroll
                                    Rectangle {
                                        visible: winCell.keyboardFocused
                                        x: winPreview.x - 2
                                        y: winPreview.y - 2
                                        width: winPreview.width + 4
                                        height: winPreview.height + 4
                                        radius: Appearance.rounding.windowRounding * winCell.winScale + 2
                                        color: "transparent"
                                        border.color: Appearance.colors.colSecondary
                                        border.width: 2
                                        z: winCell.z + 100

                                        onVisibleChanged: {
                                            if (!visible) return
                                            const wx = winPreview.x
                                            const wr = winPreview.x + winPreview.width
                                            const vl = stripFlick.contentX
                                            const vr = vl + stripFlick.width
                                            if (wx < vl) {
                                                stripFlick.contentX = Math.max(0, wx - 4)
                                            } else if (wr > vr) {
                                                stripFlick.contentX = Math.min(
                                                    wsCanvas.width - stripFlick.width,
                                                    wr - stripFlick.width + 4)
                                            }
                                        }
                                    }

                                    // Invisible drag proxy (holds pointer grab globally)
                                    Item {
                                        id: dragProxy
                                        x: winPreview.initX
                                        y: winPreview.initY
                                        width: winPreview.width
                                        height: winPreview.height
                                        visible: false
                                    }

                                    // MouseArea over the rendered window rect
                                    MouseArea {
                                        id: dragArea
                                        x: winPreview.initX
                                        y: winPreview.initY
                                        width: winPreview.width
                                        height: winPreview.height
                                        hoverEnabled: true
                                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                        drag.target: dragProxy
                                        drag.axis: Drag.XAndYAxis
                                        drag.threshold: 8

                                        property real pressOffsetX: 0
                                        property real pressOffsetY: 0

                                        onEntered: winCell.hovered = true
                                        onExited:  winCell.hovered = false
                                        onPressed: (mouse) => {
                                            winCell.pressed = true
                                            pressOffsetX = mouse.x
                                            pressOffsetY = mouse.y
                                            winPreview.Drag.hotSpot.x = mouse.x
                                            winPreview.Drag.hotSpot.y = mouse.y
                                            const p = winPreview.mapToItem(overviewBackground, 0, 0)
                                            winPreview.parent = overviewBackground
                                            winPreview.x = p.x
                                            winPreview.y = p.y
                                            winPreview.z = 99999
                                        }
                                        onPositionChanged: (mouse) => {
                                            if (!winCell.pressed || winPreview.parent !== overviewBackground) return
                                            const p = dragArea.mapToItem(overviewBackground, mouse.x, mouse.y)
                                            winPreview.x = p.x - pressOffsetX
                                            winPreview.y = p.y - pressOffsetY
                                        }
                                        onReleased: (mouse) => {
                                            winPreview.Drag.drop()
                                            winCell.pressed = false
                                            dragProxy.x = winPreview.initX
                                            dragProxy.y = winPreview.initY
                                            winPreview.parent = winCell
                                            winPreview.z = 0
                                            winPreview.x = winPreview.initX
                                            winPreview.y = winPreview.initY
                                        }
                                        onClicked: event => {
                                            if (!winCell.winData) return
                                            if (event.button === Qt.LeftButton) {
                                                GlobalStates.overviewOpen = false
                                                Hyprland.dispatch(`focuswindow address:${winCell.winData.address}`)
                                                event.accepted = true
                                            } else if (event.button === Qt.MiddleButton) {
                                                Hyprland.dispatch(`closewindow address:${winCell.winData.address}`)
                                                event.accepted = true
                                            }
                                        }

                                        StyledToolTip {
                                            extraVisibleCondition: false
                                            alternativeVisibleCondition: dragArea.containsMouse
                                            text: `${winCell.winData?.title ?? "Unknown"}\n[${winCell.winData?.class ?? "unknown"}]${winCell.winData?.xwayland ? " [XWayland]" : ""}`
                                        }
                                    }

                                    // Drop target: swap (same ws) or move (different ws)
                                    DropArea {
                                        x: winPreview.initX
                                        y: winPreview.initY
                                        width: winPreview.width
                                        height: winPreview.height
                                        onDropped: drop => {
                                            const srcAddr = drop.source?.windowAddress
                                            const dstAddr = winCell.windowAddress
                                            if (!srcAddr || srcAddr === dstAddr) return
                                            const srcWs = drop.source?.sourceWorkspaceId
                                            if (srcWs === wsRow.wsId) {
                                                Hyprland.dispatch(`focuswindow address:${srcAddr}`)
                                                Hyprland.dispatch(`swapwindow address:${dstAddr}`)
                                            } else {
                                                Hyprland.dispatch(`movetoworkspacesilent ${wsRow.wsId},address:${srcAddr}`)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
