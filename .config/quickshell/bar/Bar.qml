pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "modules" as Modules

PanelWindow {
    id: bar

    // ── Position helpers ────────────────────────────────────────────────────
    readonly property bool _isHorizontal: Config.barPosition === "top" || Config.barPosition === "bottom"
    readonly property bool _isTop:        Config.barPosition === "top"
    readonly property bool _isBottom:     Config.barPosition === "bottom"
    readonly property bool _isLeft:       Config.barPosition === "left"
    readonly property bool _isRight:      Config.barPosition === "right"

    readonly property bool _shellMode:   Config.barMode === "shell"
    // Shell mode: the edge that actually houses the modules (top or bottom,
    // matching Config.barPosition) is sized to fit the module strip — i.e.
    // barHeight, floored at moduleHeight in case barHeight was set too small
    // — instead of the decorative shellArmThickness used by the other 3
    // edges. Shared by shellFrame (Canvas below) and barBg so they can never
    // disagree on how thick the active edge is.
    readonly property real _shellActiveThickness: Math.max(Config.barHeight, Config.moduleHeight)

    // Per-edge insets for the hollow — single source of truth shared by the
    // shellFrame Canvas (visuals) and the shellMask Region (click-through).
    readonly property real _shellLeftT:   Config.shellArmThickness
    readonly property real _shellRightT:  Config.shellArmThickness
    readonly property real _shellTopT:    Config.shellArmThickness
    readonly property real _shellBottomT: Config.shellArmThickness

    readonly property HyprlandMonitor _monitor: Hyprland.monitorFor(bar.screen)

    // Shell mode: the PanelWindow spans the full monitor so the shell frame
    // Canvas (below) can paint all 4 arms; the module strip (barBg) sits
    // flush inside whichever arm is active.
    anchors {
        top:    _shellMode || _isTop    || (_isLeft || _isRight)
        bottom: _shellMode || _isBottom || (_isLeft || _isRight)
        left:   _shellMode || _isLeft   || (_isTop  || _isBottom)
        right:  _shellMode || _isRight  || (_isTop  || _isBottom)
    }
    margins {
        top:    _shellMode ? 0 : (_isTop    ? Config.outerMarginTop    : 0)
        bottom: _shellMode ? 0 : (_isBottom ? Config.outerMarginBottom : 0)
        left:   _shellMode ? 0 : (_isLeft   ? Config.outerMarginTop    : (_isHorizontal ? Config.outerMarginSide : 0))
        right:  _shellMode ? 0 : (_isRight  ? Config.outerMarginBottom : (_isHorizontal ? Config.outerMarginSide : 0))
    }

    implicitWidth:  _shellMode ? 0 : (_isHorizontal ? 0 : Config.barHeight)
    implicitHeight: _shellMode ? 0 : (_isHorizontal ? Config.barHeight : 0)

    exclusionMode: _shellMode ? ExclusionMode.Ignore : ExclusionMode.Auto
    exclusiveZone: _shellMode
                   ? -1
                   : Config.barHeight + (_isTop ? Config.outerMarginBottom : _isBottom ? Config.outerMarginTop : 0)
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.exclusionMode: _shellMode ? ExclusionMode.Ignore : ExclusionMode.Auto

    readonly property real _shellActiveResHeight: shellCenter.visible
        ? (Config.barHeight + Config.outerMarginBottom)
        : Config.shellArmThickness
    readonly property real _shellActiveResHeightBot: shellCenter.visible
        ? (Config.barHeight + Config.outerMarginTop)
        : Config.shellArmThickness

    // Shell mode edge reservations (provides Hyprland exclusive zones & reserved area for all 4 shell arms)
    PanelWindow {
        id: shellResTop
        visible: bar._shellMode && bar._shellTopT > 0
        screen: bar.screen
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:shell-res-top"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: bar._isTop ? bar._shellActiveResHeight : Config.shellArmThickness
        color: "transparent"
        mask: Region {}
        anchors { top: true; left: true; right: true }
        implicitHeight: bar._isTop ? bar._shellActiveResHeight : Config.shellArmThickness
    }
    PanelWindow {
        id: shellResBottom
        visible: bar._shellMode && bar._shellBottomT > 0
        screen: bar.screen
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:shell-res-bottom"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: bar._isBottom ? bar._shellActiveResHeightBot : Config.shellArmThickness
        color: "transparent"
        mask: Region {}
        anchors { bottom: true; left: true; right: true }
        implicitHeight: bar._isBottom ? bar._shellActiveResHeightBot : Config.shellArmThickness
    }
    PanelWindow {
        id: shellResLeft
        visible: bar._shellMode && bar._shellLeftT > 0
        screen: bar.screen
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:shell-res-left"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: bar._shellLeftT
        color: "transparent"
        mask: Region {}
        anchors { left: true; top: true; bottom: true }
        implicitWidth: bar._shellLeftT
    }
    PanelWindow {
        id: shellResRight
        visible: bar._shellMode && bar._shellRightT > 0
        screen: bar.screen
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "quickshell:shell-res-right"
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: bar._shellRightT
        color: "transparent"
        mask: Region {}
        anchors { right: true; top: true; bottom: true }
        implicitWidth: bar._shellRightT
    }

    // ── Shell mode Left Island (WlrLayer.Top) ────────────────────────────────
    // In shell mode triLeft/triRight live here on WlrLayer.Top instead of
    // inside the Bottom-layer bar PanelWindow, so they appear above all other
    // surfaces and popups can open over app windows without z-fighting.
    PanelWindow {
        id: shellLeftPW
        visible: bar._shellMode && bar._isHorizontal
                 && (!bar._triLeftAhHidden || bar._triLeftPinned)
        screen: bar.screen
        WlrLayershell.layer:          WlrLayer.Top
        WlrLayershell.namespace:       "quickshell:shell-left-island"
        WlrLayershell.exclusionMode:   ExclusionMode.Ignore
        exclusionMode:                 ExclusionMode.Ignore
        exclusiveZone:                 0
        color:                   "transparent"

        anchors { top: bar._isTop; bottom: bar._isBottom; left: true }
        margins {
            top:  bar._isTop    ? (Config.shellArmThickness + Config.outerMarginTop)    : 0
            bottom: bar._isBottom ? (Config.shellArmThickness + Config.outerMarginBottom) : 0
            left: Config.shellModuleSideMargin
        }
        implicitHeight: Config.barHeight
        implicitWidth:  shellLeftIslandRow.implicitWidth
                        + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                        + Config.islandSpacing * 2

        HoverHandler {
            onHoveredChanged: {
                if (!bar._triLeftAhEnabled) return
                if (hovered) {
                    triLeftHideTimer.stop()
                    if (bar._triLeftAhHidden) bar._triLeftAhHidden = false
                } else {
                    if (!bar._triLeftPinned) triLeftHideTimer.restart()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius:     Config.barTopLeftRadius
            topRightRadius:    Config.triLeftTopRightRadius
            bottomLeftRadius:  Config.barBottomLeftRadius
            bottomRightRadius: Config.triLeftBottomRightRadius
            color:         Theme.blurBackground
            border.width:  Config.barBorderWidth
            border.color:  Qt.rgba(Config.barBorderColor.r,
                                   Config.barBorderColor.g,
                                   Config.barBorderColor.b,
                                   Config.barBorderAlpha)
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            Rectangle {
                anchors.fill: parent
                topLeftRadius:     parent.topLeftRadius
                topRightRadius:    parent.topRightRadius
                bottomLeftRadius:  parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
                visible: Config.barRectBgStyle === "gradient"
                opacity: 1.0
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cScrim }
                    GradientStop { position: 0.5; color: Theme.cInversePrimary }
                    GradientStop { position: 1.0; color: Theme.cScrim }
                }
            }

            Row {
                id: shellLeftIslandRow
                anchors {
                    left:           parent.left
                    leftMargin:     Config.islandSpacing + Config.barEdgePaddingLeft
                    verticalCenter: parent.verticalCenter
                }
                spacing: Config.islandSpacing

                Island { bgType: "workspace"; visible_: Config.showWorkspaces; Modules.Workspaces {} }
                Island {
                    bgType: "media"
                    visible_: Config.showMediaPlayer
                    Modules.MediaPlayer {}
                }
                Island {
                    bgType: "leftgroup"
                    visible_: Config.showNotifications || Config.showWallpaper || Config.showOverview
                    Modules.Notifications { visible: Config.showNotifications }
                    Modules.WallpaperBtn  { visible: Config.showWallpaper }
                    Modules.OverviewBtn   { visible: Config.showOverview }
                }
            }
        }
    }

    // ── Shell mode Right Island (WlrLayer.Top) ───────────────────────────────
    PanelWindow {
        id: shellRightPW
        visible: bar._shellMode && bar._isHorizontal
                 && (!bar._triRightAhHidden || bar._triRightPinned)
        screen: bar.screen
        WlrLayershell.layer:          WlrLayer.Top
        WlrLayershell.namespace:       "quickshell:shell-right-island"
        WlrLayershell.exclusionMode:   ExclusionMode.Ignore
        exclusionMode:                 ExclusionMode.Ignore
        exclusiveZone:                 0
        color:                   "transparent"

        anchors { top: bar._isTop; bottom: bar._isBottom; right: true }
        margins {
            top:    bar._isTop    ? (Config.shellArmThickness + Config.outerMarginTop)    : 0
            bottom: bar._isBottom ? (Config.shellArmThickness + Config.outerMarginBottom) : 0
            right:  Config.shellModuleSideMargin
        }
        implicitHeight: Config.barHeight
        implicitWidth:  shellRightIslandRow.implicitWidth
                        + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                        + Config.islandSpacing * 2

        HoverHandler {
            onHoveredChanged: {
                if (!bar._triRightAhEnabled) return
                if (hovered) {
                    triRightHideTimer.stop()
                    if (bar._triRightAhHidden) bar._triRightAhHidden = false
                } else {
                    if (!bar._triRightPinned) triRightHideTimer.restart()
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            topLeftRadius:     Config.triRightTopLeftRadius
            topRightRadius:    Config.barTopRightRadius
            bottomLeftRadius:  Config.triRightBottomLeftRadius
            bottomRightRadius: Config.barBottomRightRadius
            color:         Theme.blurBackground
            border.width:  Config.barBorderWidth
            border.color:  Qt.rgba(Config.barBorderColor.r,
                                   Config.barBorderColor.g,
                                   Config.barBorderColor.b,
                                   Config.barBorderAlpha)
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            Rectangle {
                anchors.fill: parent
                topLeftRadius:     parent.topLeftRadius
                topRightRadius:    parent.topRightRadius
                bottomLeftRadius:  parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
                visible: Config.barRectBgStyle === "gradient"
                opacity: 1.0
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cScrim }
                    GradientStop { position: 0.5; color: Theme.cInversePrimary }
                    GradientStop { position: 1.0; color: Theme.cScrim }
                }
            }

            Row {
                id: shellRightIslandRow
                anchors {
                    right:          parent.right
                    rightMargin:    Config.islandSpacing + Config.barEdgePaddingRight
                    verticalCenter: parent.verticalCenter
                }
                spacing: Config.islandSpacing
                layoutDirection: Qt.RightToLeft

                Island { bgType: "startmenu"; Modules.PowerButton {} }
                Island {
                    bgType: "weatherbat"
                    visible_: Config.showBattery || Config.showWeather
                    Modules.Weather { visible: Config.showWeather }
                    Modules.Battery { visible: Config.showBattery }
                }
                Island {
                    bgType: "rightgroup"
                    visible_: Config.showUpdates || Config.showPowerProfiles || Config.showIdleInhibitor || Config.showTray
                    Modules.Updates       { visible: Config.showUpdates }
                    Modules.IdleInhibitor { visible: Config.showIdleInhibitor }
                    Modules.PowerProfiles { visible: Config.showPowerProfiles }
                    Modules.SystemTray { visible: Config.showTray; rootWindow: shellRightPW }
                }
                Island { bgType: "activewindow"; visible_: Config.showWindow; Modules.ActiveWindow {} }
            }
        }
    }

    // Shell mode spans the whole monitor, but only the arms and active modules should actually
    // be "there" as far as other layer-shell surfaces / windows / input are concerned.
    mask: bar._shellMode ? shellMask : null
    Region {
        id: shellMask
        x: 0
        y: 0
        width:  bar.width
        height: bar.height

        // Hollow cutout — area inside the 4 shell arms
        Region {
            x:      bar._shellLeftT
            y:      bar._shellTopT
            width:  bar.width  - bar._shellLeftT - bar._shellRightT
            height: bar.height - bar._shellTopT  - bar._shellBottomT
            intersection: Intersection.Subtract
        }

        // Add back input region for Left Island when visible
        Region {
            x:      shellLeftPW.x
            y:      shellLeftPW.y
            width:  shellLeftPW.visible ? shellLeftPW.width : 0
            height: shellLeftPW.visible ? shellLeftPW.height : 0
        }

        // Add back input region for Shell Center Protrusion when visible
        Region {
            x:      shellCenter.x
            y:      shellCenter.y
            width:  shellCenter.visible ? shellCenter.width : 0
            height: shellCenter.visible ? shellCenter.height : 0
        }

        // Add back input region for Right Island when visible
        Region {
            x:      shellRightPW.x
            y:      shellRightPW.y
            width:  shellRightPW.visible ? shellRightPW.width : 0
            height: shellRightPW.visible ? shellRightPW.height : 0
        }
    }

    // ── Auto-hide — reads ~/.config/hyprcandy/hyprcandy-bar.conf ───────────
    //
    // When [bar] autohide=true:
    //   • A HoverHandler on this PanelWindow tracks pointer presence.
    //   • While the pointer is ON the bar the hide timer is stopped/reset.
    //   • When the pointer LEAVES the hide timer starts; on expiry the bar
    //     hides (visible = false) and the thin hotspot PanelWindow appears.
    //   • The hotspot is a 2 px strip at the same edge, WlrLayer.Top,
    //     exclusiveZone -1 (no screen reservation). Its HoverHandler fires
    //     on pointer entry and restores the bar.
    //   • Fullscreen guard: if the focused window on this monitor is
    //     fullscreen the bar stays hidden and the hotspot stays invisible
    //     too (nothing should pull focus away from a fullscreen app).

    // ── Bar auto-hide — driven directly by Config.barAutoHide ─────────────
    //  Config.qml is the source of truth.  The CC writes Config.barAutoHide
    //  and Config.barAutoHideDelay; no file-watching or bash processes needed.
    //  Config._settings persists the values across Quickshell restarts.
    property bool _ahEnabled:  false
    property int  _ahDelaySec: 5
    property bool _ahHidden:   false

    // Guard: bar stays visible while any panel is open.
    readonly property bool anyPanelOpen: ControlCenterState.visible
                                       || NotificationsState.historyVisible
                                       || StartMenuState.menuVisible
                                       || TrayMenuState.visible
                                       || SysTrayPopupState.visible
                                       || UpdatesPopupState.visible
                                       || ClockPopupState.visible
                                       || WeatherPopupState.visible
                                       || SystemMonitorPopupState.visible
                                       || CalendarPopupState.visible

    // Tri AH: only pin the segment that owns the open popup. CC pins all three.
    readonly property bool _triLeftPinned: NotificationsState.historyVisible
    readonly property bool _triRightPinned: StartMenuState.menuVisible
                                          || TrayMenuState.visible
                                          || SysTrayPopupState.visible
                                          || UpdatesPopupState.visible
                                          || WeatherPopupState.visible
                                          || SystemMonitorPopupState.visible
    readonly property bool _triCenterPinned: ControlCenterState.visible
                                           || ClockPopupState.visible
                                           || CalendarPopupState.visible

    function _syncTriAhPins() {
        if (bar._triLeftPinned) {
            triLeftHideTimer.stop()
        } else if (bar._triLeftAhEnabled && !bar._triLeftAhHidden && !triLeftHover.hovered) {
            triLeftHideTimer.restart()
        }
        if (bar._triCenterPinned) {
            triCenterHideTimer.stop()
        } else if (bar._triCenterAhEnabled && !bar._triCenterAhHidden && !triCenterHover.hovered) {
            triCenterHideTimer.restart()
        }
        if (bar._triRightPinned) {
            triRightHideTimer.stop()
        } else if (bar._triRightAhEnabled && !bar._triRightAhHidden && !triRightHover.hovered) {
            triRightHideTimer.restart()
        }
        updateBarVisibility()
    }

    on_TriLeftPinnedChanged:   _syncTriAhPins()
    on_TriRightPinnedChanged:  _syncTriAhPins()
    on_TriCenterPinnedChanged: _syncTriAhPins()

    onAnyPanelOpenChanged: {
        if (bar._ahEnabled) {
            if (bar.anyPanelOpen) {
                _ahHideTimer.stop()
                if (bar._ahHidden) { bar._ahHidden = false; bar.visible = true }
            } else {
                _ahHideTimer.restart()
            }
        }
        // Shell module AH: pin modules while any panel is open
        if (bar._shellModAhEnabled) {
            if (bar.anyPanelOpen) {
                _shellModHideTimer.stop()
                if (bar._shellModHidden) bar._shellModHidden = false
            } else {
                _shellModHideTimer.restart()
            }
        }
        _syncTriAhPins()
    }

    // Sync from Config on startup and react to live changes from CC
    Connections {
        target: Config
        function onBarModeChanged() {
            bar._ahEnabled = Config.barAutoHide && Config.barMode !== "tri"
            if (!bar._ahEnabled) {
                _ahHideTimer.stop()
                if (bar._ahHidden) { bar._ahHidden = false }
            } else {
                if (!bar._ahHidden && !bar.anyPanelOpen) _ahHideTimer.restart()
            }
            // Shell module AH: only active in shell mode
            bar._shellModAhEnabled = Config.shellModuleAutoHide && Config.barMode === "shell"
            if (!bar._shellModAhEnabled) {
                _shellModHideTimer.stop()
                bar._shellModHidden = false
            } else {
                if (!bar._shellModHidden && !bar.anyPanelOpen) _shellModHideTimer.restart()
            }
            updateBarVisibility()
        }
        function onBarAutoHideChanged() {
            bar._ahEnabled = Config.barAutoHide && Config.barMode !== "tri"
            if (bar._ahEnabled) {
                if (!bar._ahHidden && !bar.anyPanelOpen) _ahHideTimer.restart()
            } else {
                _ahHideTimer.stop()
                if (bar._ahHidden) { bar._ahHidden = false }
            }
            updateBarVisibility()
        }
        function onBarAutoHideDelayChanged() {
            bar._ahDelaySec = Config.barAutoHideDelay
        }
        function onShellModuleAutoHideChanged() {
            bar._shellModAhEnabled = Config.shellModuleAutoHide && Config.barMode === "shell"
            if (bar._shellModAhEnabled) {
                if (!bar._shellModHidden && !bar.anyPanelOpen) _shellModHideTimer.restart()
            } else {
                _shellModHideTimer.stop()
                bar._shellModHidden = false
            }
        }
        function onShellModuleAutoHideDelayChanged() {
            bar._shellModDelaySec = Config.shellModuleAutoHideDelay
        }
    }
    Component.onCompleted: {
        bar._ahEnabled  = Config.barAutoHide && Config.barMode !== "tri"
        bar._ahDelaySec = Config.barAutoHideDelay
        if (bar._ahEnabled) _ahHideTimer.restart()
        bar._shellModAhEnabled = Config.shellModuleAutoHide && Config.barMode === "shell"
        bar._shellModDelaySec  = Config.shellModuleAutoHideDelay
        if (bar._shellModAhEnabled) _shellModHideTimer.restart()
        barStateTimer.start()
        updateBarVisibility()
    }

    on_AhHiddenChanged: updateBarVisibility()

    function updateBarVisibility() {
        if (Config.barMode === "tri") {
            const leftVisible   = !Config.triLeftAutoHide   || !_triLeftAhHidden   || _triLeftPinned
            const centerVisible = !Config.triCenterAutoHide || !_triCenterAhHidden || _triCenterPinned
            const rightVisible  = !Config.triRightAutoHide  || !_triRightAhHidden  || _triRightPinned
            bar.visible = leftVisible || centerVisible || rightVisible
        } else if (Config.barMode === "shell") {
            bar.visible = true
        } else {
            bar.visible = !bar._ahHidden
        }
    }

    // ── Tri & Shell Left Auto-Hide ──
    property bool _triLeftAhEnabled: Config.triLeftAutoHide && (Config.barMode === "tri" || Config.barMode === "shell")
    property int  _triLeftAhDelaySec: Config.triLeftAutoHideDelay
    property bool _triLeftAhHidden: false

    on_TriLeftAhHiddenChanged: updateBarVisibility()

    on_TriLeftAhEnabledChanged: {
        if (_triLeftAhEnabled) {
            if (!_triLeftAhHidden && !bar._triLeftPinned) triLeftHideTimer.restart()
        } else {
            triLeftHideTimer.stop()
            _triLeftAhHidden = false
        }
    }
    on_TriLeftAhDelaySecChanged: {
        if (_triLeftAhEnabled && !_triLeftAhHidden && !bar._triLeftPinned) triLeftHideTimer.restart()
    }

    Timer {
        id: triLeftHideTimer
        interval: bar._triLeftAhDelaySec * 1000
        repeat: false
        onTriggered: {
            const mon = bar._monitor
            if (mon && mon.activeWindow && mon.activeWindow.fullscreen) return
            bar._triLeftAhHidden = true
        }
    }

    // ── Tri & Shell Center Auto-Hide ──
    property bool _triCenterAhEnabled: Config.triCenterAutoHide && (Config.barMode === "tri" || Config.barMode === "shell")
    property int  _triCenterAhDelaySec: Config.triCenterAutoHideDelay
    property bool _triCenterAhHidden: false

    on_TriCenterAhHiddenChanged: {
        updateBarVisibility()
        if (Config.barMode === "shell") shellFrame.requestPaint()
    }

    on_TriCenterAhEnabledChanged: {
        if (_triCenterAhEnabled) {
            if (!_triCenterAhHidden && !bar._triCenterPinned) triCenterHideTimer.restart()
        } else {
            triCenterHideTimer.stop()
            _triCenterAhHidden = false
        }
    }
    on_TriCenterAhDelaySecChanged: {
        if (_triCenterAhEnabled && !_triCenterAhHidden && !bar._triCenterPinned) triCenterHideTimer.restart()
    }

    Timer {
        id: triCenterHideTimer
        interval: bar._triCenterAhDelaySec * 1000
        repeat: false
        onTriggered: {
            const mon = bar._monitor
            if (mon && mon.activeWindow && mon.activeWindow.fullscreen) return
            bar._triCenterAhHidden = true
        }
    }

    // ── Tri & Shell Right Auto-Hide ──
    property bool _triRightAhEnabled: Config.triRightAutoHide && (Config.barMode === "tri" || Config.barMode === "shell")
    property int  _triRightAhDelaySec: Config.triRightAutoHideDelay
    property bool _triRightAhHidden: false

    on_TriRightAhHiddenChanged: updateBarVisibility()

    on_TriRightAhEnabledChanged: {
        if (_triRightAhEnabled) {
            if (!_triRightAhHidden && !bar._triRightPinned) triRightHideTimer.restart()
        } else {
            triRightHideTimer.stop()
            _triRightAhHidden = false
        }
    }
    on_TriRightAhDelaySecChanged: {
        if (_triRightAhEnabled && !_triRightAhHidden && !bar._triRightPinned) triRightHideTimer.restart()
    }

    Timer {
        id: triRightHideTimer
        interval: bar._triRightAhDelaySec * 1000
        repeat: false
        onTriggered: {
            const mon = bar._monitor
            if (mon && mon.activeWindow && mon.activeWindow.fullscreen) return
            bar._triRightAhHidden = true
        }
    }

    // ── Shell-module Auto-Hide ──
    // In shell mode only: the module strip (barBg) fades out via opacity.
    // The PanelWindow itself stays visible so the shell-frame arms remain.
    property bool _shellModAhEnabled: false
    property int  _shellModDelaySec:  5
    property bool _shellModHidden:    false

    on_ShellModHiddenChanged: {
        // Animate opacity on barBg and barLayout directly.
        // Both objects are declared below but QML forward-refs inside the same Item are fine.
        barBg.opacity     = bar._shellModHidden ? 0.0 : 1.0
        barLayout.opacity = bar._shellModHidden ? 0.0 : 1.0
    }

    on_ShellModAhEnabledChanged: {
        if (!bar._shellModAhEnabled) {
            _shellModHideTimer.stop()
            bar._shellModHidden = false
        } else {
            if (!bar._shellModHidden && !bar.anyPanelOpen) _shellModHideTimer.restart()
        }
    }

    Timer {
        id: _shellModHideTimer
        interval: bar._shellModDelaySec * 1000
        repeat: false
        running: false
        onTriggered: {
            if (!bar._shellModAhEnabled) return
            const mon = bar._monitor
            if (mon && mon.activeWindow && mon.activeWindow.fullscreen) return
            bar._shellModHidden = true
        }
    }

    // Hide timer — fires after the pointer has been outside the bar
    // for _ahDelaySec seconds.
    Timer {
        id: _ahHideTimer
        interval:  bar._ahDelaySec * 1000
        repeat:    false
        running:   false
        onTriggered: {
            // Do not hide if the focused window on this monitor is fullscreen
            const mon = bar._monitor
            if (mon && mon.activeWindow && mon.activeWindow.fullscreen) return
            bar._ahHidden = true
            bar.visible   = false
        }
    }

    // HoverHandler on the bar itself.
    // onHoveredChanged fires synchronously when the pointer enters or leaves.
    HoverHandler {
        id: _barHover
        onHoveredChanged: {
            if (!bar._ahEnabled) return
            if (hovered) {
                // Pointer entered — cancel pending hide, ensure bar visible
                _ahHideTimer.stop()
                if (bar._ahHidden) {
                    bar._ahHidden = false
                    bar.visible   = true
                }
            } else {
                // Pointer left — start the hide countdown only when no panels are open
                if (!bar.anyPanelOpen) _ahHideTimer.restart()
            }
        }
    }

    // Hotspot window — 2 px strip anchored to the same screen edge as the
    // bar, always on WlrLayer.Top, zero exclusive zone.  Only visible when
    // the bar is auto-hidden AND the focused window is not fullscreen.
    PanelWindow {
        id: _ahHotspot

        readonly property bool _fullscreen: {
            const mon = bar._monitor
            return !!(mon && mon.activeWindow && mon.activeWindow.fullscreen)
        }

        visible: bar._ahEnabled && bar._ahHidden && !_fullscreen

        WlrLayershell.layer:     WlrLayer.Top
        WlrLayershell.namespace: "quickshell:bar-autohide-hotspot"
        exclusionMode:           ExclusionMode.Ignore
        exclusiveZone:           0
        color:                   "transparent"

        // Mirror the bar's edge anchoring exactly
        anchors {
            top:    bar._isTop    || (bar._isLeft || bar._isRight)
            bottom: bar._isBottom || (bar._isLeft || bar._isRight)
            left:   bar._isLeft   || (bar._isTop  || bar._isBottom)
            right:  bar._isRight  || (bar._isTop  || bar._isBottom)
        }

        // 2 px thick in the perpendicular axis, full-width along the edge
        implicitWidth:  bar._isHorizontal ? 0 : 2
        implicitHeight: bar._isHorizontal ? 2 : 0

        HoverHandler {
            onHoveredChanged: {
                if (hovered && bar._ahEnabled) {
                    bar._ahHidden = false
                    bar.visible   = true
                    _ahHideTimer.stop()
                }
            }
        }
    }

    // ── Bar state file ──────────────────────────────────────────────────
    // Written to ~/.config/hyprcandy/qs_bar_state.json at startup and on
    // geometry changes so startmenu/notifications can track bar geometry.
    // Passing dest+content as argv eliminates bash/JSON quoting issues.
    // Mirrors startmenu brightnessctl pattern: command is a binding that reads
    // _dest/_json properties; setting them before running=true is the reliable pattern.
    Process {
        id: barStateProc
        property string _dest: Config.home + "/.config/hyprcandy/qs_bar_state.json"
        property string _json: ""
        command: ["python3", "-c",
                  "import sys; open(sys.argv[1],'w').write(sys.argv[2])",
                  barStateProc._dest,
                  barStateProc._json]
    }
    Timer {
        id: barStateTimer
        interval: 300; repeat: false
        onTriggered: bar._doWriteBarState()
    }

    function _writeBarState() { barStateTimer.restart() }

    function _doWriteBarState() {
        if (barStateProc.running) return
        barStateProc._json = JSON.stringify({
            position:          Config.barPosition,
            barHeight:         Config.barHeight,
            exclusiveZone:     Config.barHeight + Config.outerMarginTop + Config.outerMarginBottom,
            outerMarginTop:    Config.outerMarginTop,
            outerMarginBottom: Config.outerMarginBottom,
            outerMarginSide:   Config.outerMarginSide
        })
        barStateProc.running = true
    }

    Connections {
        target: Config
        function onBarPositionChanged()      { bar._writeBarState() }
        function onBarHeightChanged()        { bar._writeBarState() }
        function onOuterMarginTopChanged()   { bar._writeBarState() }
        function onOuterMarginBottomChanged(){ bar._writeBarState() }
        function onOuterMarginSideChanged()  { bar._writeBarState() }
    }

    // ── Bar background ──────────────────────────────────────────────────────
    // Always transparent — background drawn by barBg Rectangle below.
    color: "transparent"

    // ── Shell mode frame ─────────────────────────────────────────────────────
    // "shell" is a bar STYLE, same as "bar"/"island"/"tri" — not a second
    // window. This used to be a separate ShellLayer.qml PanelWindow, which
    // meant it needed its own WlrLayershell.layer/exclusionMode kept in sync
    // by hand, and its stacking relative to the modules was up to the
    // compositor (two same-layer surfaces). Now it's a plain Canvas inside
    // THIS PanelWindow, so it always shares this window's layer, exclusionMode,
    // and exclusiveZone with zero chance of drift, and — because it's declared
    // before barBg/barLayout below — it always paints behind the modules.
    //
    // It draws a picture-frame border around the whole monitor. The edge
    // that houses the modules (top or bottom, matching Config.barPosition)
    // is inset by bar._shellActiveThickness (barHeight/moduleHeight) so the
    // hollow starts right below/above the module strip; the other 3 edges
    // (the two sides, and whichever of top/bottom ISN'T active) are inset
    // by the purely decorative Config.shellArmThickness instead.
    Canvas {
        id: shellFrame
        anchors.fill: parent
        visible: bar._shellMode
        z: -1

        readonly property real  _leftT:   bar._shellLeftT
        readonly property real  _rightT:  bar._shellRightT
        readonly property real  _topT:    bar._shellTopT
        readonly property real  _bottomT: bar._shellBottomT
        readonly property int   _ri:     Config.shellInnerRadius
        readonly property int   _bw:     Config.barBorderWidth
        readonly property color _fill:   Theme.blurBackground
        readonly property color _border: Qt.rgba(Config.barBorderColor.r,
                                                  Config.barBorderColor.g,
                                                  Config.barBorderColor.b,
                                                  Config.barBorderAlpha)

        onWidthChanged:    requestPaint()
        onHeightChanged:   requestPaint()
        on_LeftTChanged:   requestPaint()
        on_RightTChanged:  requestPaint()
        on_TopTChanged:    requestPaint()
        on_BottomTChanged: requestPaint()
        on_RiChanged:      requestPaint()
        on_BwChanged:      requestPaint()
        on_FillChanged:    requestPaint()
        on_BorderChanged:  requestPaint()
        onVisibleChanged:  if (visible) requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            const W  = width
            const H  = height
            const ri = _ri
            const bw = _bw

            // ── Pass 1: fill — outer rect minus rounded inner (hollow) rect ──
            ctx.fillStyle = _fill.toString()
            ctx.beginPath()
            ctx.rect(0, 0, W, H)
            _shellHollowPath(ctx, W, H, ri, false)
            ctx.closePath()
            ctx.fillRule = "evenodd"
            ctx.fill()

            // ── Pass 2: inner-edge border only ──
            if (bw > 0) {
                ctx.strokeStyle = _border.toString()
                ctx.lineWidth   = bw
                ctx.lineJoin    = "round"
                ctx.beginPath()
                _shellHollowPath(ctx, W, H, ri, true)
                ctx.stroke()
            }

        }

        function _shellHollowPath(ctx, W, H, r, cw) {
            const armT = Config.shellArmThickness
            r = Math.min(r, (W - 2 * armT) / 2, (H - 2 * armT) / 2)

            const centerActive = (!bar._triCenterAhHidden || bar._triCenterPinned) && (Config.showClock || Config.showDate || Config.showCava || Config.showDistro)
            const centerH = centerActive ? Math.max(Config.barHeight, Config.moduleHeight) : armT
            const cWidth = centerActive ? (shellCenterRow.implicitWidth + Config.barEdgePaddingLeft + Config.barEdgePaddingRight + Config.islandSpacing * 2) : 0
            const cX1 = (W - cWidth) / 2
            const cX2 = (W + cWidth) / 2

            const isTop = bar._isTop
            const isBot = bar._isBottom

            if (cw) {
                ctx.moveTo(armT + r, armT)
                if (isTop && centerH > armT && cWidth > 0) {
                    ctx.lineTo(cX1 - r, armT)
                    ctx.arcTo(cX1, armT, cX1, armT + r, r)
                    ctx.lineTo(cX1, centerH - r)
                    ctx.arcTo(cX1, centerH, cX1 + r, centerH, r)
                    ctx.lineTo(cX2 - r, centerH)
                    ctx.arcTo(cX2, centerH, cX2, centerH - r, r)
                    ctx.lineTo(cX2, armT + r)
                    ctx.arcTo(cX2, armT, cX2 + r, armT, r)
                    ctx.lineTo(W - armT - r, armT)
                } else {
                    ctx.lineTo(W - armT - r, armT)
                }
                ctx.arcTo(W - armT, armT, W - armT, armT + r, r)
                ctx.lineTo(W - armT, H - armT - r)
                ctx.arcTo(W - armT, H - armT, W - armT - r, H - armT, r)

                if (isBot && centerH > armT && cWidth > 0) {
                    const botTabY = H - centerH
                    const botArmY = H - armT
                    ctx.lineTo(cX2 + r, botArmY)
                    ctx.arcTo(cX2, botArmY, cX2, botArmY - r, r)
                    ctx.lineTo(cX2, botTabY + r)
                    ctx.arcTo(cX2, botTabY, cX2 - r, botTabY, r)
                    ctx.lineTo(cX1 + r, botTabY)
                    ctx.arcTo(cX1, botTabY, cX1, botTabY + r, r)
                    ctx.lineTo(cX1, botArmY - r)
                    ctx.arcTo(cX1, botArmY, cX1 - r, botArmY, r)
                    ctx.lineTo(armT + r, botArmY)
                } else {
                    ctx.lineTo(armT + r, H - armT)
                }
                ctx.arcTo(armT, H - armT, armT, H - armT - r, r)
                ctx.lineTo(armT, armT + r)
                ctx.arcTo(armT, armT, armT + r, armT, r)
            } else {
                ctx.moveTo(armT + r, armT)
                ctx.arcTo(armT, armT, armT, armT + r, r)
                ctx.lineTo(armT, H - armT - r)
                ctx.arcTo(armT, H - armT, armT + r, H - armT, r)

                if (isBot && centerH > armT && cWidth > 0) {
                    const botTabY = H - centerH
                    const botArmY = H - armT
                    ctx.lineTo(cX1 - r, botArmY)
                    ctx.arcTo(cX1, botArmY, cX1, botArmY - r, r)
                    ctx.lineTo(cX1, botTabY + r)
                    ctx.arcTo(cX1, botTabY, cX1 + r, botTabY, r)
                    ctx.lineTo(cX2 - r, botTabY)
                    ctx.arcTo(cX2, botTabY, cX2, botTabY + r, r)
                    ctx.lineTo(cX2, botArmY - r)
                    ctx.arcTo(cX2, botArmY, cX2 + r, botArmY, r)
                    ctx.lineTo(W - armT - r, botArmY)
                } else {
                    ctx.lineTo(W - armT - r, H - armT)
                }
                ctx.arcTo(W - armT, H - armT, W - armT, H - armT - r, r)
                ctx.lineTo(W - armT, armT + r)
                ctx.arcTo(W - armT, armT, W - armT - r, armT, r)

                if (isTop && centerH > armT && cWidth > 0) {
                    ctx.lineTo(cX2 + r, armT)
                    ctx.arcTo(cX2, armT, cX2, armT + r, r)
                    ctx.lineTo(cX2, centerH - r)
                    ctx.arcTo(cX2, centerH, cX2 - r, centerH, r)
                    ctx.lineTo(cX1 + r, centerH)
                    ctx.arcTo(cX1, centerH, cX1, centerH - r, r)
                    ctx.lineTo(cX1, armT + r)
                    ctx.arcTo(cX1, armT, cX1 - r, armT, r)
                    ctx.lineTo(armT + r, armT)
                } else {
                    ctx.lineTo(armT + r, armT)
                }
            }
        }
    }

    // Bar background rectangle.
    // "bar" mode   → blurBackground fill + border (pair with Hyprland blur layerrule)
    // "island" mode → transparent; islands carry their own gradient fill + border
    // "shell" mode  → transparent, sized to bar._shellActiveThickness (fits the
    //                 modules) and flush against the active screen edge
    //                 (top/bottom) — modules live inside that edge's band
    //                 itself, not as a separate bar inset past it. The other
    //                 3 edges of the frame stay at the decorative
    //                 Config.shellArmThickness (see shellFrame above).
    //                 shellFrame already paints the arm's fill/border; each
    //                 module keeps its own island pill background on top.
    //                 No left/right/center split — every module (leftGroup +
    //                 center group + rightGroup below) lives in this one strip.
    Rectangle {
        id: barBg
        readonly property bool _shellHorizontal: bar._shellMode && bar._isHorizontal
        readonly property bool _shellVertical:   bar._shellMode && !bar._isHorizontal
        anchors {
            left:  _shellHorizontal ? parent.left : (_shellVertical ? (bar._isLeft ? parent.left : undefined) : parent.left)
            right: _shellHorizontal ? parent.right : (_shellVertical ? (bar._isRight ? parent.right : undefined) : parent.right)
            top:    _shellHorizontal ? undefined : parent.top
            bottom: _shellHorizontal ? undefined : parent.bottom
            leftMargin:  bar._isHorizontal ? (bar._shellMode ? Config.shellModuleSideMargin : Config.outerMarginSide) : 0
            rightMargin: bar._isHorizontal ? (bar._shellMode ? Config.shellModuleSideMargin : Config.outerMarginSide) : 0
            topMargin:    0
            bottomMargin: 0
        }
        x: _shellVertical ? (bar._isRight ? (parent.width - width) : 0) : 0
        y: _shellHorizontal ? (bar._isBottom ? (parent.height - height) : 0) : 0

        // Shell mode only anchors one edge, so height/width must be explicit —
        // matches bar._shellActiveThickness so modules sit exactly within the
        // active edge's band (see shellFrame's per-edge insets above).
        height: _shellHorizontal ? bar._shellActiveThickness : undefined
        width:  _shellVertical   ? bar._shellActiveThickness : undefined
        color:        Config.barMode === "bar" ? Theme.blurBackground : "transparent"
        border.color: Config.barMode === "bar"
            ? Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)
            : "transparent"
        border.width: Config.barMode === "bar" ? Config.barBorderWidth : 0
        // tri mode uses its own three sub-bar rectangles; barBg is invisible
        visible: Config.barMode !== "tri"
        topLeftRadius:     Config.barTopLeftRadius
        topRightRadius:    Config.barTopRightRadius
        bottomLeftRadius:  Config.barBottomLeftRadius
        bottomRightRadius: Config.barBottomRightRadius
        Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
        Behavior on opacity { NumberAnimation { duration: 250 } }

        // Shell-module auto-hide: reveal modules on hover, restart timer on leave
        HoverHandler {
            enabled: bar._shellModAhEnabled
            onHoveredChanged: {
                if (hovered) {
                    _shellModHideTimer.stop()
                    if (bar._shellModHidden) bar._shellModHidden = false
                } else {
                    if (!bar.anyPanelOpen) _shellModHideTimer.restart()
                }
            }
        }

        // Gradient child — only visible when barRectBgStyle === "gradient" in bar mode
        Rectangle {
            anchors.fill: parent
            topLeftRadius:     parent.topLeftRadius
            topRightRadius:    parent.topRightRadius
            bottomLeftRadius:  parent.bottomLeftRadius
            bottomRightRadius: parent.bottomRightRadius
            visible: Config.barMode === "bar" && Config.barRectBgStyle === "gradient"
            opacity: 1.0
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.cScrim }
                GradientStop { position: 0.5; color: Theme.cInversePrimary }
                GradientStop { position: 1.0; color: Theme.cScrim }
            }
            Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }
        }
    }

    // ── Island component ─────────────────────────────────────────────────────
    //  Pill-shaped group container. moduleHeight floats islands inside barHeight:
    //    if moduleHeight < barHeight → natural top/bottom gap within the panel strip.
    //  bgOverride: -1 = use Config opacity settings; ≥0 = force specific opacity.
    component Island: Item {
        id: isl
        default property alias content: innerRow.data
        property bool   visible_:  true
        property real   bgOverride: -1
        property string bgType: ""
        visible: visible_ && innerRow.implicitWidth > 0

        implicitWidth:  innerRow.implicitWidth
        implicitHeight: Config.moduleHeight

        readonly property color _effectiveBgColor: {
            switch (bgType) {
                case "workspace":    return Config.wsBgColor
                case "grouped":      return Config.groupedBgColor
                case "leftgroup":    return Config.groupedBgColor
                case "rightgroup":   return Config.groupedBgColor
                case "ungrouped":    return Config.ungroupedBgColor
                case "clockdate":    return Config.ungroupedBgColor
                case "weatherbat":   return Config.ungroupedBgColor
                case "startmenu":    return Config.startMenuBgColor
                case "media":        return Config.mediaBgColor
                case "cava":         return Config.cavaBgColor
                case "distro":       return Config.distroBgColor
                case "tray":         return Config.trayBgColor
                case "activewindow": return Config.activeWindowBgColor
                default:             return Theme.cOnSecondary
            }
        }

        readonly property real _effectiveBgOpacity: {
            switch (bgType) {
                case "workspace":    return Config.wsBgOpacity
                case "grouped":      return Config.groupedBgOpacity
                case "leftgroup":    return Config.leftGroupBgOpacity
                case "rightgroup":   return Config.rightGroupBgOpacity
                case "ungrouped":    return Config.ungroupedBgOpacity
                case "clockdate":    return Config.clockDateBgOpacity
                case "weatherbat":   return Config.weatherBatBgOpacity
                case "startmenu":    return Config.startMenuBgOpacity
                case "media":        return Config.mediaBgOpacity
                case "cava":         return Config.cavaBgOpacity
                case "distro":       return Config.distroBgOpacity
                case "tray":         return Config.trayBgOpacity
                case "activewindow": return Config.activeWindowBgOpacity
                default:             return bgOverride > -0.5 ? bgOverride
                    : (Config.barMode === "bar" ? Config.islandBgOpacityBar : Config.islandBgOpacityIsland)
            }
        }

        readonly property real _bgOpacity: _effectiveBgOpacity

        Rectangle {
            id: islFill
            anchors.fill: parent
            radius: Config.islandRadius
            color: "transparent"
            clip: true
            z: 0

            Rectangle {
                anchors.fill: parent; radius: parent.radius
                visible: Config.islandBgStyle === "flat"
                color: Qt.rgba(isl._effectiveBgColor.r, isl._effectiveBgColor.g,
                               isl._effectiveBgColor.b, isl._bgOpacity)
                Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
            }
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                visible: Config.islandBgStyle === "gradient"
                opacity: isl._bgOpacity
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cInversePrimary }
                    GradientStop { position: 0.35; color: Theme.cOnSecondary }
                    GradientStop { position: 0.7; color: Theme.cOnSecondary }
                    GradientStop { position: 1.0; color: Theme.cInversePrimary }
                }
                Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Config.islandRadius
            color: "transparent"
            border.width: Config.islandBorder
            border.color: Qt.rgba(Config.islandBorderColor.r, Config.islandBorderColor.g,
                                  Config.islandBorderColor.b, Config.islandBorderAlpha)
            z: 1
        }

        Row {
            id: innerRow
            anchors.centerIn: parent
            spacing: Config.groupedSpacing
            z: 2
        }
    }

    // ── Root layout ─────────────────────────────────────────────────────────
    Item {
        id: barLayout
        anchors {
            left:   barBg.left
            right:  barBg.right
            top:    barBg.top
            bottom: barBg.bottom
        }
        Behavior on opacity { NumberAnimation { duration: 250 } }
        readonly property int _minGap: 4
        property bool _mediaActive: MediaPlayerState.active
        readonly property real _leftEdge:   Config.islandSpacing + Config.barEdgePaddingLeft
        readonly property real _rightEdge:  Config.islandSpacing + Config.barEdgePaddingRight
        readonly property real _centerX:    width / 2
        readonly property real _leftMaxRight: _centerX - _minGap
        readonly property real _rightMinLeft: _centerX + _minGap
        readonly property real mediaMaxWidth: {
            const leftRowNaturalW = leftGroup.implicitWidth
            const leftRowX = _leftEdge
            const leftRowRight = leftRowX + leftRowNaturalW
            if (leftRowRight <= _leftMaxRight) return -1
            const budget = _leftMaxRight - leftRowX
            return Math.max(0, budget)
        }
        readonly property real rightMaxWidth: {
            const rightRowNaturalW = rightGroup.implicitWidth
            const rightRowX = width - _rightEdge - rightRowNaturalW
            if (rightRowX >= _rightMinLeft) return -1
            const budget = width - _rightEdge - _rightMinLeft
            return Math.max(0, budget)
        }

        // ── LEFT GROUP ─────────────────────────────────────────────────────────
        Row {
            id: leftGroup
            visible: bar._isHorizontal && Config.barMode !== "tri" && Config.barMode !== "shell"
            anchors {
                left: parent.left
                leftMargin: Config.islandSpacing + Config.barEdgePaddingLeft
                verticalCenter: parent.verticalCenter
            }
            spacing: Config.islandSpacing

            Island { bgType: "workspace"; visible_: Config.showWorkspaces; Modules.Workspaces {} }

            Island {
                bgType: "media"
                visible_: Config.showMediaPlayer
                Modules.MediaPlayer {
                    id: mp1
                    mediaMaxW: barLayout.mediaMaxWidth
                    property bool mediaActive: MediaPlayerState.active
                }
            }
            
            Island {
                bgType: "leftgroup"
                visible_: Config.showNotifications || Config.showWallpaper || Config.showOverview
                Modules.Notifications { visible: Config.showNotifications }
                Modules.WallpaperBtn  { visible: Config.showWallpaper }
                Modules.OverviewBtn   { visible: Config.showOverview }
            }
        }

        // ── CENTER GROUP ───────────────────────────────────────────────────────
        Row {
            visible: bar._isHorizontal && Config.barMode !== "tri" && Config.barMode !== "shell"
            anchors.centerIn: parent
            spacing: Config.islandSpacing

            Island { bgType: "cava";     visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaLeft; side: "left" } }
            Island { bgType: "clockdate"; visible_: Config.showClock; Modules.Clock {} }
            Island {
                bgType: "distro"
                visible_: Config.showDistro
                bgOverride: Config.ccTransparentBg ? 0.0 : -1
                Modules.ControlCenter {}
            }
            Island { bgType: "clockdate"; visible_: Config.showDate;  Modules.DateDisplay {} }
            Island { bgType: "cava";     visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaRight; side: "right" } }
        }

        // ── RIGHT GROUP ────────────────────────────────────────────────────────
        // ── RIGHT GROUP ────────────────────────────────────────────────────────
        Row {
            id: rightGroup
            visible: bar._isHorizontal && Config.barMode !== "tri" && Config.barMode !== "shell"
            anchors {
                right: parent.right
                rightMargin: Config.islandSpacing + Config.barEdgePaddingRight
                verticalCenter: parent.verticalCenter
            }
            spacing: Config.islandSpacing
            layoutDirection: Qt.RightToLeft
            Island { bgType: "startmenu"; Modules.PowerButton {} }
            Island {
                bgType: "weatherbat"
                visible_: Config.showBattery || Config.showWeather
                Modules.Weather { visible: Config.showWeather }
                Modules.Battery { visible: Config.showBattery }
            }

            Island {
                bgType: "rightgroup"
                visible_: Config.showUpdates || Config.showPowerProfiles || Config.showIdleInhibitor || Config.showTray
                Modules.Updates       { visible: Config.showUpdates }
                Modules.IdleInhibitor { visible: Config.showIdleInhibitor }
                Modules.PowerProfiles { visible: Config.showPowerProfiles }
                Modules.SystemTray { visible: Config.showTray; rootWindow: bar }
            }
            Island { bgType: "activewindow"; visible_: Config.showWindow; Modules.ActiveWindow {} }
        }

        // ── TRI LEFT BAR (tri mode only — shell mode uses shellLeftPW below) ──
        Rectangle {
            id: triLeft
            visible: bar._isHorizontal && Config.barMode === "tri"
                     && (!bar._triLeftAhHidden || bar._triLeftPinned)
            anchors {
                left:           parent.left
                leftMargin:     Config.barMode === "shell" ? Config.shellModuleSideMargin : Config.outerMarginSide
                top:            Config.barMode === "shell" ? (bar._isTop ? parent.top : undefined) : undefined
                bottom:         Config.barMode === "shell" ? (bar._isBottom ? parent.bottom : undefined) : undefined
                topMargin:      Config.barMode === "shell" ? (bar._isTop ? (Config.shellArmThickness + Config.outerMarginTop) : 0) : 0
                bottomMargin:   Config.barMode === "shell" ? (bar._isBottom ? (Config.shellArmThickness + Config.outerMarginBottom) : 0) : 0
                verticalCenter: Config.barMode === "shell" ? undefined : parent.verticalCenter
            }
            height:       Config.barHeight
            implicitWidth: triLeftRow.implicitWidth
                           + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                           + Config.islandSpacing * 2
            topLeftRadius:     Config.barTopLeftRadius
            topRightRadius:    Config.triLeftTopRightRadius
            bottomLeftRadius:  Config.barBottomLeftRadius
            bottomRightRadius: Config.triLeftBottomRightRadius
            color:         Theme.blurBackground
            border.width:  Config.barBorderWidth
            border.color:  Qt.rgba(Config.barBorderColor.r,
                                   Config.barBorderColor.g,
                                   Config.barBorderColor.b,
                                   Config.barBorderAlpha)
            clip: false
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            HoverHandler {
                id: triLeftHover
                onHoveredChanged: {
                    if (!bar._triLeftAhEnabled) return
                    if (hovered) {
                        triLeftHideTimer.stop()
                        if (bar._triLeftAhHidden) {
                            bar._triLeftAhHidden = false
                        }
                    } else {
                        if (!bar._triLeftPinned) triLeftHideTimer.restart()
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                topLeftRadius:     parent.topLeftRadius
                topRightRadius:    parent.topRightRadius
                bottomLeftRadius:  parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
                visible: Config.barRectBgStyle === "gradient"
                opacity: 1.0
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cScrim }
                    GradientStop { position: 0.5; color: Theme.cInversePrimary }
                    GradientStop { position: 1.0; color: Theme.cScrim }
                }
                Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }
            }

            Row {
                id: triLeftRow
                anchors {
                    left:           parent.left
                    leftMargin:     Config.islandSpacing + Config.barEdgePaddingLeft
                    verticalCenter: parent.verticalCenter
                }
                spacing: Config.islandSpacing

                Island { bgType: "workspace"; visible_: Config.showWorkspaces; Modules.Workspaces {} }
                Island {
                    bgType: "media"
                    visible_: Config.showMediaPlayer
                    Modules.MediaPlayer {
                        id: mp2
                        mediaMaxW: {
                            const gap = 4
                            const leftRight = triLeft.x + triLeft.width
                            const centerLeft = Config.barMode === "shell" ? shellCenter.x : triCenter.x
                            const available = centerLeft - leftRight - gap
                            if (available >= 0) return -1
                            return Math.max(0, triLeft.width + available - (Config.barEdgePaddingLeft + Config.barEdgePaddingRight + Config.islandSpacing * 2))
                        }
                    }
                }
                Island {
                    bgType: "leftgroup"
                    visible_: Config.showNotifications || Config.showWallpaper || Config.showOverview
                    Modules.Notifications { visible: Config.showNotifications }
                    Modules.WallpaperBtn  { visible: Config.showWallpaper }
                    Modules.OverviewBtn   { visible: Config.showOverview }
                }
            }
        }

        // ── SHELL CENTER MODULES ───────────────────────────────────────────
        Item {
            id: shellCenter
            visible: bar._isHorizontal && Config.barMode === "shell"
                     && (!bar._triCenterAhHidden || bar._triCenterPinned)
            anchors {
                horizontalCenter: parent.horizontalCenter
                top:    bar._isTop ? parent.top : undefined
                bottom: bar._isBottom ? parent.bottom : undefined
            }
            height: Math.max(Config.barHeight, Config.moduleHeight)
            implicitWidth: shellCenterRow.implicitWidth
                           + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                           + Config.islandSpacing * 2

            HoverHandler {
                onHoveredChanged: {
                    if (!bar._triCenterAhEnabled) return
                    if (hovered) {
                        triCenterHideTimer.stop()
                        if (bar._triCenterAhHidden) bar._triCenterAhHidden = false
                    } else {
                        if (!bar._triCenterPinned) triCenterHideTimer.restart()
                    }
                }
            }

            Row {
                id: shellCenterRow
                anchors.centerIn: parent
                spacing: Config.islandSpacing
                onImplicitWidthChanged: shellFrame.requestPaint()

                Island { bgType: "cava";      visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaLeftS; side: "left" } }
                Island { bgType: "clockdate"; visible_: Config.showClock; Modules.Clock {} }
                Island {
                    bgType: "distro"
                    visible_: Config.showDistro
                    bgOverride: Config.ccTransparentBg ? 0.0 : -1
                    Modules.ControlCenter {}
                }
                Island { bgType: "clockdate"; visible_: Config.showDate;  Modules.DateDisplay {} }
                Island { bgType: "cava";      visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaRightS; side: "right" } }
            }
        }

        // ── TRI CENTER BAR ─────────────────────────────────────────────────
        Rectangle {
            id: triCenter
            visible: bar._isHorizontal && Config.barMode === "tri"
                     && (!bar._triCenterAhHidden || bar._triCenterPinned)
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter:   parent.verticalCenter
            }
            height: Config.barHeight
            implicitWidth: triCenterRow.implicitWidth
                           + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                           + Config.islandSpacing * 2
            topLeftRadius:     Config.triCenterTopLeftRadius
            topRightRadius:    Config.triCenterTopRightRadius
            bottomLeftRadius:  Config.triCenterBottomLeftRadius
            bottomRightRadius: Config.triCenterBottomRightRadius
            color:        Theme.blurBackground
            border.width: Config.barBorderWidth
            border.color: Qt.rgba(Config.barBorderColor.r,
                                   Config.barBorderColor.g,
                                   Config.barBorderColor.b,
                                   Config.barBorderAlpha)
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            HoverHandler {
                id: triCenterHover
                onHoveredChanged: {
                    if (!bar._triCenterAhEnabled) return
                    if (hovered) {
                        triCenterHideTimer.stop()
                        if (bar._triCenterAhHidden) {
                            bar._triCenterAhHidden = false
                        }
                    } else {
                        if (!bar._triCenterPinned) triCenterHideTimer.restart()
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                topLeftRadius:     parent.topLeftRadius
                topRightRadius:    parent.topRightRadius
                bottomLeftRadius:  parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
                visible: Config.barRectBgStyle === "gradient"
                opacity: 1.0
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cScrim }
                    GradientStop { position: 0.5; color: Theme.cInversePrimary }
                    GradientStop { position: 1.0; color: Theme.cScrim }
                }
                Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }
            }

            Row {
                id: triCenterRow
                anchors {
                    left:           parent.left
                    leftMargin:     Config.islandSpacing + Config.barEdgePaddingLeft
                    verticalCenter: parent.verticalCenter
                }
                spacing: Config.islandSpacing

                Island { bgType: "cava";      visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaLeftV; side: "left" } }
                Island { bgType: "clockdate"; visible_: Config.showClock; Modules.Clock {} }
                Island {
                    bgType: "distro"
                    visible_: Config.showDistro
                    bgOverride: Config.ccTransparentBg ? 0.0 : -1
                    Modules.ControlCenter {}
                }
                Island { bgType: "clockdate"; visible_: Config.showDate;  Modules.DateDisplay {} }
                Island { bgType: "cava";      visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaRightV; side: "right" } }
            }
        }

        // ── TRI RIGHT BAR (tri mode only — shell mode uses shellRightPW below) ──
        Rectangle {
            id: triRight
            visible: bar._isHorizontal && Config.barMode === "tri"
                     && (!bar._triRightAhHidden || bar._triRightPinned)
            anchors {
                right:          parent.right
                rightMargin:    Config.barMode === "shell" ? Config.shellModuleSideMargin : Config.outerMarginSide
                top:            Config.barMode === "shell" ? (bar._isTop ? parent.top : undefined) : undefined
                bottom:         Config.barMode === "shell" ? (bar._isBottom ? parent.bottom : undefined) : undefined
                topMargin:      Config.barMode === "shell" ? (bar._isTop ? (Config.shellArmThickness + Config.outerMarginTop) : 0) : 0
                bottomMargin:   Config.barMode === "shell" ? (bar._isBottom ? (Config.shellArmThickness + Config.outerMarginBottom) : 0) : 0
                verticalCenter: Config.barMode === "shell" ? undefined : parent.verticalCenter
            }
            height:       Config.barHeight
            implicitWidth: triRightRow.implicitWidth
                           + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                           + Config.islandSpacing * 2
            topLeftRadius:     Config.triRightTopLeftRadius
            topRightRadius:    Config.barTopRightRadius
            bottomLeftRadius:  Config.triRightBottomLeftRadius
            bottomRightRadius: Config.barBottomRightRadius
            color:         Theme.blurBackground
            border.width:  Config.barBorderWidth
            border.color:  Qt.rgba(Config.barBorderColor.r,
                                   Config.barBorderColor.g,
                                   Config.barBorderColor.b,
                                   Config.barBorderAlpha)
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            HoverHandler {
                id: triRightHover
                onHoveredChanged: {
                    if (!bar._triRightAhEnabled) return
                    if (hovered) {
                        triRightHideTimer.stop()
                        if (bar._triRightAhHidden) {
                            bar._triRightAhHidden = false
                        }
                    } else {
                        if (!bar._triRightPinned) triRightHideTimer.restart()
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                topLeftRadius:     parent.topLeftRadius
                topRightRadius:    parent.topRightRadius
                bottomLeftRadius:  parent.bottomLeftRadius
                bottomRightRadius: parent.bottomRightRadius
                visible: Config.barRectBgStyle === "gradient"
                opacity: 1.0
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cScrim }
                    GradientStop { position: 0.5; color: Theme.cInversePrimary }
                    GradientStop { position: 1.0; color: Theme.cScrim }
                }
                Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }
            }

            Row {
                id: triRightRow
                anchors {
                    right:          parent.right
                    rightMargin:    Config.islandSpacing + Config.barEdgePaddingRight
                    verticalCenter: parent.verticalCenter
                }
                spacing: Config.islandSpacing
                layoutDirection: Qt.RightToLeft

                Island { bgType: "startmenu"; Modules.PowerButton {} }
                Island {
                    bgType: "weatherbat"
                    visible_: Config.showBattery || Config.showWeather
                    Modules.Weather { visible: Config.showWeather }
                    Modules.Battery { visible: Config.showBattery }
                }

                Island {
                    bgType: "rightgroup"
                    visible_: Config.showUpdates || Config.showPowerProfiles || Config.showIdleInhibitor || Config.showTray
                    Modules.Updates       { visible: Config.showUpdates }
                    Modules.IdleInhibitor { visible: Config.showIdleInhibitor }
                    Modules.PowerProfiles { visible: Config.showPowerProfiles }
                    Modules.SystemTray { visible: Config.showTray; rootWindow: bar }
                }
                Island { bgType: "activewindow"; visible_: Config.showWindow; Modules.ActiveWindow {} }
            }
        }

    // ── Hotspots for individual tri & shell panels ──
    PanelWindow {
        id: triLeftHotspot
        readonly property bool _fullscreen: {
            const mon = bar._monitor
            return !!(mon && mon.activeWindow && mon.activeWindow.fullscreen)
        }
        visible: (Config.barMode === "tri" || Config.barMode === "shell") && bar._triLeftAhEnabled && bar._triLeftAhHidden && !_fullscreen

        WlrLayershell.layer:     WlrLayer.Top
        WlrLayershell.namespace: "quickshell:tri-left-autohide-hotspot"
        exclusionMode:           ExclusionMode.Ignore
        exclusiveZone:           0
        color:                   "transparent"

        anchors {
            top:    bar._isTop
            bottom: bar._isBottom
            left:   true
        }
        margins {
            left: Config.barMode === "shell" ? Config.shellModuleSideMargin : barLayout.mapToItem(null, triLeft.x, 0).x
        }
        implicitWidth:  Config.barMode === "shell" ? shellLeftPW.implicitWidth : triLeft.width
        implicitHeight: Config.barMode === "shell" ? Math.max(4, Config.shellArmThickness) : 4

        HoverHandler {
            onHoveredChanged: {
                if (hovered && bar._triLeftAhEnabled) {
                    bar._triLeftAhHidden = false
                    triLeftHideTimer.stop()
                }
            }
        }
    }

    PanelWindow {
        id: triCenterHotspot
        readonly property bool _fullscreen: {
            const mon = bar._monitor
            return !!(mon && mon.activeWindow && mon.activeWindow.fullscreen)
        }
        visible: (Config.barMode === "tri" || Config.barMode === "shell") && bar._triCenterAhEnabled && bar._triCenterAhHidden && !_fullscreen

        WlrLayershell.layer:     WlrLayer.Top
        WlrLayershell.namespace: "quickshell:tri-center-autohide-hotspot"
        exclusionMode:           ExclusionMode.Ignore
        exclusiveZone:           0
        color:                   "transparent"

        anchors {
            top:    bar._isTop
            bottom: bar._isBottom
            left:   true
        }
        margins {
            left: barLayout.mapToItem(null, Config.barMode === "shell" ? shellCenter.x : triCenter.x, 0).x
        }
        implicitWidth:  Config.barMode === "shell" ? shellCenter.width : triCenter.width
        implicitHeight: Config.barMode === "shell" ? Math.max(4, Config.shellArmThickness) : 4

        HoverHandler {
            onHoveredChanged: {
                if (hovered && bar._triCenterAhEnabled) {
                    bar._triCenterAhHidden = false
                    triCenterHideTimer.stop()
                }
            }
        }
    }

    PanelWindow {
        id: triRightHotspot
        readonly property bool _fullscreen: {
            const mon = bar._monitor
            return !!(mon && mon.activeWindow && mon.activeWindow.fullscreen)
        }
        visible: (Config.barMode === "tri" || Config.barMode === "shell") && bar._triRightAhEnabled && bar._triRightAhHidden && !_fullscreen

        WlrLayershell.layer:     WlrLayer.Top
        WlrLayershell.namespace: "quickshell:tri-right-autohide-hotspot"
        exclusionMode:           ExclusionMode.Ignore
        exclusiveZone:           0
        color:                   "transparent"

        anchors {
            top:    bar._isTop
            bottom: bar._isBottom
            left:   true
        }
        margins {
            left: Config.barMode === "shell" ? (bar.width - Config.shellModuleSideMargin - shellRightPW.implicitWidth) : barLayout.mapToItem(null, triRight.x, 0).x
        }
        implicitWidth:  Config.barMode === "shell" ? shellRightPW.implicitWidth : triRight.width
        implicitHeight: Config.barMode === "shell" ? Math.max(4, Config.shellArmThickness) : 4

        HoverHandler {
            onHoveredChanged: {
                if (hovered && bar._triRightAhEnabled) {
                    bar._triRightAhHidden = false
                    triRightHideTimer.stop()
                }
            }
        }
    }

        // ── VERTICAL BAR ──────────────────────────────────────────────────
        Column {
            visible: !bar._isHorizontal
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top; bottom: parent.bottom
            }
            spacing: Config.islandSpacing
            padding: Config.outerMarginEdge

            Island { visible_: Config.showWorkspaces; Modules.Workspaces { vertical: true } }
            Item { implicitWidth: 1; implicitHeight: Config.islandSpacing * 2 }
            Island { visible_: Config.showClock; Modules.Clock {} }
            Item { implicitWidth: 1; implicitHeight: Config.islandSpacing * 2 }
            Island { bgType: "startmenu"; Modules.PowerButton {} }
        }
    }
}
