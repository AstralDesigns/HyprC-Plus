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

    // Scale: map monitor height → rowHeight so windows fit the row (rowHeight defined below)
    // Forward reference OK in QML bindings.
    property real scale: root.rowHeight / (monitorLogicalHeight > 0 ? monitorLogicalHeight : 1080)

    // Window preview cell dimensions (scaled from monitor size)
    property real previewMonitorWidth: monitorLogicalWidth * root.scale
    property real previewMonitorHeight: root.rowHeight

    // Layout constants
    property real labelWidth: Config.options.overview.workspaceLabelWidth
    property real stripSpacing: Config.options.overview.windowStripSpacing
    property real rowSpacing: 4
    property real outerPadding: 10

    // How many workspace rows to display
    property int numWorkspaces: Config.options.overview.numWorkspaces

    // Active workspace id on this monitor
    property int activeWorkspaceId: monitor.activeWorkspace?.id ?? 1

    // Target floating panel height: 90% of screen minus the topMargin (40px) and elevation margins
    property real targetPanelHeight: panelWindow.screen.height * 0.90 - 40 - Appearance.sizes.elevationMargin * 2

    // Auto-derive rowHeight so all numWorkspaces rows fit inside targetPanelHeight,
    // clamped between 55px (min readable) and 120px (max before it looks too big)
    property real rowHeight: Math.min(120, Math.max(55,
        (targetPanelHeight - outerPadding * 2 - rowSpacing * (numWorkspaces - 1)) / numWorkspaces
    ))

    // Total content height of all rows (used to know if scrolling is needed)
    property real totalRowsHeight: rowHeight * numWorkspaces + rowSpacing * (numWorkspaces - 1)

    // Panel background height: prefer fitting all rows, but hard-cap at targetPanelHeight
    property real panelContentHeight: Math.min(totalRowsHeight, targetPanelHeight - outerPadding * 2)

    // Total overview width: label + preview strip (wide enough to show ~3 window previews)
    property real stripVisibleWidth: Math.min(previewMonitorWidth * 3.5, panelWindow.screen.width * 0.55)
    property real totalWidth: labelWidth + stripVisibleWidth + outerPadding * 2 + 2 // +2 border

    implicitWidth: totalWidth
    implicitHeight: panelContentHeight + outerPadding * 2

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
            // Sort left-to-right by X position so keyboard nav matches visual order
            return (winA?.at?.[0] ?? 0) - (winB?.at?.[0] ?? 0)
        })
    }

    // Check if a workspace id has any windows
    function workspaceHasWindows(wsId) {
        return HyprlandData.windowList.some(w => w.workspace?.id === wsId)
    }

    // Compute the minimum relative X (in logical px) across all windows in wsId.
    // Windows in scrolling layout can have negative relative X (to the left of the
    // monitor origin). We shift the canvas so the leftmost window starts at x=0.
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

    // Canvas width = full horizontal span of all windows (right edge of rightmost
    // minus left edge of leftmost), at least previewMonitorWidth.
    // Uses per-window srcMonH scale to match OverviewWindow.initX exactly.
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
            // srcMonH matching winCell.winScale calculation
            const monH = (mon?.height ?? root.monitorLogicalHeight)
            const monS = (mon?.scale ?? 1)
            const transform = mon?.transform ?? 0
            const srcMonH = (transform % 2 === 1)
                ? (mon?.width ?? root.monitorLogicalWidth) / monS - monResT - monResB
                : monH / monS - monResT - monResB
            const wScale = root.rowHeight / (srcMonH > 0 ? srcMonH : root.monitorLogicalHeight)
            const relX = (w.at?.[0] ?? 0) - monX - monResL
            // shift by -minRelX so leftmost window lands at x=0
            const scaledX = (relX - minRelX) * wScale
            const scaledW = (w.size?.[0] ?? 0) * wScale
            const right = scaledX + scaledW
            if (right > maxRight) maxRight = right
        }
        return maxRight
    }

    Rectangle {
        id: overviewBackground
        anchors {
            fill: parent
        }
        implicitWidth: root.totalWidth
        // Height is driven by root.panelContentHeight (capped) — not by full column content
        implicitHeight: root.panelContentHeight + root.outerPadding * 2
        radius: Appearance.rounding.large
        color: Appearance.colors.colOverviewBg
        border.width: 0
        // Wheel over the overview content cycles workspaces (inner children
        // consume scroll before it reaches PanelWindow's WheelHandler)
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

        // Vertical scrollable list of workspace rows
        ScrollView {
            id: outerScrollView
            anchors {
                fill: parent
                margins: root.outerPadding
            }
            contentWidth: availableWidth
            contentHeight: workspaceListColumn.implicitHeight
            wheelEnabled: false
            ScrollBar.vertical: ScrollBar {
                policy: workspaceListColumn.implicitHeight > outerScrollView.height
                        ? ScrollBar.AlwaysOn : ScrollBar.AsNeeded
                width: 6
            }
            ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AlwaysOff }

            Column {
                id: workspaceListColumn
                width: outerScrollView.availableWidth
                spacing: root.rowSpacing

                Repeater {
                    id: wsRepeater
                    model: root.numWorkspaces

                    delegate: Item {
                        id: wsRow
                        required property int index
                        property int wsId: index + 1
                        property bool isActive: wsId === root.activeWorkspaceId
                        property bool hasWindows: root.workspaceHasWindows(wsId)
                        property bool isDragTarget: false

                        width: workspaceListColumn.width
                        height: (Config.options.overview.hideEmptyWorkspaces && !hasWindows && !isActive)
                                ? 0 : root.rowHeight
                        visible: height > 0

                        // Full-row drop target — covers label + strip so dropping anywhere on the row works
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

                            // ── Workspace label cell ──────────────────────────────────
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

                            // ── Window preview strip ──────────────────────────────────
                            // A single scaled workspace canvas per row: windows are placed
                            // at their real scaled coordinates so tiled, stacked, and
                            // floating layouts are preserved exactly as on-screen.
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

                                // Flickable so keyboard Left/Right can drive contentX imperatively
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

                                    // When this is the active row, respond to keyboard scroll commands
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

                                    // The canvas: wide enough to hold ALL windows at their
                                    // real scaled positions (scrolling layout windows extend
                                    // far right of the monitor boundary).
                                    Item {
                                        id: wsCanvas
                                        width: root.canvasWidthForWorkspace(wsRow.wsId)
                                        height: root.rowHeight

                                        Repeater {
                                            model: ScriptModel {
                                                values: root.windowsForWorkspace(wsRow.wsId)
                                            }

                                            // Each delegate is an OverviewWindow sitting at its
                                            // real scaled position inside the canvas. winCell is
                                            // a full-canvas-sized transparent container so that
                                            // OverviewWindow (restrictToWorkspace:true) can do
                                            // its own x/y calculation from window coords, and
                                            // the MouseArea covers just the window's rendered rect.
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

                                                // Canvas X offset for this window: shift by -minRelX
                                                // using the same winScale as OverviewWindow.initX
                                                property real winXOffset: -root.canvasMinRelXForWorkspace(wsRow.wsId) * winCell.winScale

                                                // winCell covers the full canvas so OverviewWindow
                                                // can position itself freely inside it
                                                x: 0
                                                y: 0
                                                width: wsCanvas.width
                                                height: root.rowHeight
                                                z: index

                                                property bool hovered: false
                                                property bool pressed: false
                                                property string windowAddress: winData?.address ?? ""
                                                property int sourceWorkspaceId: wsRow.wsId
                                                // True when keyboard cycling has selected this window
                                                property bool keyboardFocused: wsRow.isActive
                                                    && GlobalStates.focusedWinIndex === winCell.index

                                                OverviewWindow {
                                                    id: winPreview
                                                    toplevel: winCell.modelData
                                                    windowData: winCell.winData
                                                    monitorData: winCell.winMonitorData
                                                    scale: winCell.winScale
                                                    // Use full canvas width so windows are never capped
                                                    availableWorkspaceWidth: wsCanvas.width
                                                    availableWorkspaceHeight: root.rowHeight
                                                    widgetMonitorId: root.monitor.id
                                                    hovered: winCell.hovered || winCell.keyboardFocused
                                                    pressed: winCell.pressed
                                                    // Shift by winXOffset so negative-x windows land at x≥0
                                                    xOffset: winCell.winXOffset
                                                    yOffset: 0
                                                    restrictToWorkspace: true

                                                    // Drag source properties (read by DropArea.onDropped)
                                                    property string windowAddress: winCell.winData?.address ?? ""
                                                    property int sourceWorkspaceId: wsRow.wsId
                                                    Drag.active: winCell.pressed && dragArea.drag.active
                                                    Drag.source: winPreview
                                                }

                                                // Keyboard-focus highlight ring + auto-scroll to it
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

                                                    // When this ring becomes visible, scroll the
                                                    // Flickable so the window is fully in view
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

                                                // Invisible item that stays in winCell and serves as
                                                // drag.target so Qt holds the pointer grab globally.
                                                Item {
                                                    id: dragProxy
                                                    x: winPreview.initX
                                                    y: winPreview.initY
                                                    width: winPreview.width
                                                    height: winPreview.height
                                                    visible: false
                                                }

                                                // MouseArea exactly over the rendered window rect
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

                                                    // Offset from cursor to winPreview top-left at press time
                                                    property real pressOffsetX: 0
                                                    property real pressOffsetY: 0

                                                    onEntered: winCell.hovered = true
                                                    onExited:  winCell.hovered = false
                                                    onPressed: (mouse) => {
                                                        winCell.pressed = true
                                                        // mouse.x/y relative to dragArea (which is at initX/initY)
                                                        pressOffsetX = mouse.x
                                                        pressOffsetY = mouse.y
                                                        // hotSpot = click offset within winPreview for DropArea hit-testing
                                                        winPreview.Drag.hotSpot.x = mouse.x
                                                        winPreview.Drag.hotSpot.y = mouse.y
                                                        // Reparent winPreview to overviewBackground to escape clips
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
                                                        // Fire the drop while winPreview is still at its
                                                        // dragged position so DropArea.onDropped can fire
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

                                                // Drop target: dropping another window on this one
                                                // swaps them (same workspace) or moves them (different ws)
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
                                                            // Same workspace: focus src then swap with dst
                                                            Hyprland.dispatch(`focuswindow address:${srcAddr}`)
                                                            Hyprland.dispatch(`swapwindow address:${dstAddr}`)
                                                        } else {
                                                            // Different workspace: silently move src to this ws
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
        }
    }
}
