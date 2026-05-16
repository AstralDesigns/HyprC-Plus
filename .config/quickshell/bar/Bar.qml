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

    readonly property HyprlandMonitor _monitor: Hyprland.monitorFor(bar.screen)

    anchors {
        top:    _isTop    || (_isLeft || _isRight)
        bottom: _isBottom || (_isLeft || _isRight)
        left:   _isLeft   || (_isTop  || _isBottom)
        right:  _isRight  || (_isTop  || _isBottom)
    }
    margins {
        top:    _isTop    ? Config.outerMarginTop    : 0
        bottom: _isBottom ? Config.outerMarginBottom : 0
        left:   _isLeft   ? Config.outerMarginTop    : (_isHorizontal ? Config.outerMarginSide : 0)
        right:  _isRight  ? Config.outerMarginBottom : (_isHorizontal ? Config.outerMarginSide : 0)
    }

    implicitWidth:  _isHorizontal ? 0 : Config.barHeight
    implicitHeight: _isHorizontal ? Config.barHeight : 0

    exclusionMode: ExclusionMode.Normal
    exclusiveZone: Config.barHeight + (_isTop ? Config.outerMarginBottom : _isBottom ? Config.outerMarginTop : 0)
    WlrLayershell.layer: WlrLayer.Bottom

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

    // Guard: bar stays visible while any panel (CC, notifications, start-menu, tray menu) is open.
    readonly property bool anyPanelOpen: ControlCenterState.visible
                                       || NotificationsState.historyVisible
                                       || StartMenuState.menuVisible
                                       || TrayMenuState.visible
                                       || SysTrayPopupState.visible
                                       || UpdatesPopupState.visible

    onAnyPanelOpenChanged: {
        if (!bar._ahEnabled) return
        if (bar.anyPanelOpen) {
            _ahHideTimer.stop()
            if (bar._ahHidden) { bar._ahHidden = false; bar.visible = true }
        } else {
            _ahHideTimer.restart()
        }
    }

    // Sync from Config on startup and react to live changes from CC
    Connections {
        target: Config
        function onBarAutoHideChanged() {
            bar._ahEnabled = Config.barAutoHide
            if (bar._ahEnabled) {
                if (!bar._ahHidden && !bar.anyPanelOpen) _ahHideTimer.restart()
            } else {
                _ahHideTimer.stop()
                if (bar._ahHidden) { bar._ahHidden = false; bar.visible = true }
            }
        }
        function onBarAutoHideDelayChanged() {
            bar._ahDelaySec = Config.barAutoHideDelay
        }
    }
    Component.onCompleted: {
        bar._ahEnabled  = Config.barAutoHide
        bar._ahDelaySec = Config.barAutoHideDelay
        if (bar._ahEnabled) _ahHideTimer.restart()
        barStateTimer.start()
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

    // Bar background rectangle.
    // "bar" mode  → blurBackground fill + border (pair with Hyprland blur layerrule)
    // "island" mode → transparent; islands carry their own gradient fill + border
    Rectangle {
        id: barBg
        anchors {
            fill: parent
            leftMargin:  bar._isHorizontal ? Config.outerMarginSide : 0
            rightMargin: bar._isHorizontal ? Config.outerMarginSide : 0
        }
        color:        Config.barMode === "bar" ? Theme.blurBackground : "transparent"
        border.color: Config.barMode === "bar"
            ? Qt.rgba(Theme.cOnPrimaryFixedVariant.r, Theme.cOnPrimaryFixedVariant.g,
                      Theme.cOnPrimaryFixedVariant.b, Config.barBorderAlpha)
            : "transparent"
        border.width: Config.barMode === "bar" ? Config.barBorderWidth : 0
        // tri mode uses its own three sub-bar rectangles; barBg is invisible
        visible: Config.barMode !== "tri"
        radius:       Config.barRadius
        Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

        // Gradient child — only visible when barRectBgStyle === "gradient" in bar mode
        Rectangle {
            anchors.fill: parent; radius: parent.radius
            visible: Config.barMode === "bar" && Config.barRectBgStyle === "gradient"
            opacity: Config.islandBgOpacityIsland
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.cInversePrimary }
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
            anchors.fill: parent
            radius: Config.islandRadius
            color: "transparent"
            border.width: Config.islandBorder
            border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b,
                                  Config.islandBorderAlpha)
            clip: true

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
                    GradientStop { position: 1.0; color: Theme.cScrim }
                }
                Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }
            }
        }

        Row {
            id: innerRow
            anchors.centerIn: parent
            spacing: Config.groupedSpacing
        }
    }

    // ── Rofi process (shared, declared at bar level) ─────────────────────────
    Process {
        id: rofiProc
        command: [Config.hyprScripts + "/rofi-menus.sh"]
        running: false
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
            visible: bar._isHorizontal && Config.barMode !== "tri"
            anchors {
                left: parent.left
                leftMargin: Config.islandSpacing + Config.barEdgePaddingLeft
                verticalCenter: parent.verticalCenter
            }
            spacing: Config.islandSpacing

            Island { bgType: "workspace"; visible_: Config.showWorkspaces; Modules.Workspaces {} }

            Island {
                bgType: "leftgroup"
                visible_: Config.showNotifications || Config.showWallpaper || Config.showOverview
                Modules.Notifications { visible: Config.showNotifications }
                Modules.WallpaperBtn  { visible: Config.showWallpaper }
                Modules.OverviewBtn   { visible: Config.showOverview }
            }

            Island {
                bgType: "media"
                visible_: Config.showMediaPlayer
                Modules.MediaPlayer {
                    id: mp1
                    mediaMaxW: barLayout.mediaMaxWidth
                    property bool mediaActive: MediaPlayerState.active
                }
            }
        }

        // ── CENTER GROUP ───────────────────────────────────────────────────────
        Row {
            visible: bar._isHorizontal && Config.barMode !== "tri"
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
        Row {
            id: rightGroup
            visible: bar._isHorizontal && Config.barMode !== "tri"
            anchors {
                right: parent.right
                rightMargin: Config.islandSpacing + Config.barEdgePaddingRight
                verticalCenter: parent.verticalCenter
            }
            spacing: Config.islandSpacing
            layoutDirection: Qt.RightToLeft
            Island { bgType: "startmenu"; Modules.PowerButton {} }
            Island { bgType: "weatherbat"; visible_: Config.showBattery;  Modules.Battery {} }
            Island { bgType: "weatherbat"; visible_: Config.showWeather;  Modules.Weather {} }

            Island {
                bgType: "rightgroup"
                visible_: Config.showUpdates || Config.showPowerProfiles || Config.showIdleInhibitor || Config.showRofi || Config.showTray
                Modules.Updates       { visible: Config.showUpdates }
                Modules.IdleInhibitor { visible: Config.showIdleInhibitor }
                Modules.PowerProfiles { visible: Config.showPowerProfiles }
                Item {
                    visible: Config.showRofi
                    implicitWidth: _rofiIcon.implicitWidth + Config.modPadH * 2
                    implicitHeight: Config.moduleHeight
                    Text {
                        id: _rofiIcon; anchors.centerIn: parent
                        text: "󰓐"; color: Config.glyphColor
                        font.family: Config.fontFamily; font.pixelSize: Config.fontSize
                    }
                    ToolTip.visible: false; ToolTip.text: ""; ToolTip.delay: 500
                    opacity: _rofiMa.containsMouse ? 0.7 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    MouseArea { id: _rofiMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!rofiProc.running) rofiProc.running = true }
                }
                Modules.SystemTray { visible: Config.showTray; rootWindow: bar }
            }
            Island { bgType: "activewindow"; visible_: Config.showWindow; Modules.ActiveWindow {} }
        }

        // ── TRI LEFT BAR ──────────────────────────────────────────────────
        Rectangle {
            id: triLeft
            visible: bar._isHorizontal && Config.barMode === "tri"
            anchors {
                left:           parent.left
                leftMargin:     Config.outerMarginSide
                verticalCenter: parent.verticalCenter
            }
            height:       Config.barHeight
            implicitWidth: triLeftRow.implicitWidth
                           + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                           + Config.islandSpacing * 2
            radius:        Config.barRadius
            color:         Theme.blurBackground
            border.width:  Config.barBorderWidth
            border.color:  Qt.rgba(Theme.cOnPrimaryFixedVariant.r,
                                   Theme.cOnPrimaryFixedVariant.g,
                                   Theme.cOnPrimaryFixedVariant.b,
                                   Config.barBorderAlpha)
            clip: false
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            Rectangle {
                anchors.fill: parent; radius: parent.radius
                visible: Config.barRectBgStyle === "gradient"
                opacity: Config.islandBgOpacityIsland
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cInversePrimary }
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
                    bgType: "leftgroup"
                    visible_: Config.showNotifications || Config.showWallpaper || Config.showOverview
                    Modules.Notifications { visible: Config.showNotifications }
                    Modules.WallpaperBtn  { visible: Config.showWallpaper }
                    Modules.OverviewBtn   { visible: Config.showOverview }
                }
                Island {
                    bgType: "media"
                    visible_: Config.showMediaPlayer
                    Modules.MediaPlayer {
                        id: mp2
                        mediaMaxW: {
                            const gap = 4
                            const leftRight = triLeft.x + triLeft.width
                            const centerLeft = triCenter.x
                            const available = centerLeft - leftRight - gap
                            if (available >= 0) return -1
                            return Math.max(0, triLeft.width + available - (Config.barEdgePaddingLeft + Config.barEdgePaddingRight + Config.islandSpacing * 2))
                        }
                    }
                }
            }
        }

        // ── TRI CENTER BAR ─────────────────────────────────────────────────
        Rectangle {
            id: triCenter
            visible: bar._isHorizontal && Config.barMode === "tri"
            anchors {
                horizontalCenter: parent.horizontalCenter
                verticalCenter:   parent.verticalCenter
            }
            height:       Config.barHeight
            implicitWidth: triCenterRow.implicitWidth
                           + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                           + Config.islandSpacing * 2
            radius:        Config.barRadius
            color:         Theme.blurBackground
            border.width:  Config.barBorderWidth
            border.color:  Qt.rgba(Theme.cOnPrimaryFixedVariant.r,
                                   Theme.cOnPrimaryFixedVariant.g,
                                   Theme.cOnPrimaryFixedVariant.b,
                                   Config.barBorderAlpha)
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            Rectangle {
                anchors.fill: parent; radius: parent.radius
                visible: Config.barRectBgStyle === "gradient"
                opacity: Config.islandBgOpacityIsland
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cInversePrimary }
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

        // ── TRI RIGHT BAR ──────────────────────────────────────────────────
        Rectangle {
            id: triRight
            visible: bar._isHorizontal && Config.barMode === "tri"
            anchors {
                right:          parent.right
                rightMargin:    Config.outerMarginSide
                verticalCenter: parent.verticalCenter
            }
            height:       Config.barHeight
            implicitWidth: triRightRow.implicitWidth
                           + Config.barEdgePaddingLeft + Config.barEdgePaddingRight
                           + Config.islandSpacing * 2
            radius:        Config.barRadius
            color:         Theme.blurBackground
            border.width:  Config.barBorderWidth
            border.color:  Qt.rgba(Theme.cOnPrimaryFixedVariant.r,
                                   Theme.cOnPrimaryFixedVariant.g,
                                   Theme.cOnPrimaryFixedVariant.b,
                                   Config.barBorderAlpha)
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }

            Rectangle {
                anchors.fill: parent; radius: parent.radius
                visible: Config.barRectBgStyle === "gradient"
                opacity: Config.islandBgOpacityIsland
                gradient: Gradient {
                    orientation: Gradient.Vertical
                    GradientStop { position: 0.0; color: Theme.cInversePrimary }
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
                Island { bgType: "weatherbat"; visible_: Config.showBattery;  Modules.Battery {} }
                Island { bgType: "weatherbat"; visible_: Config.showWeather;  Modules.Weather {} }

                Island {
                    bgType: "rightgroup"
                    visible_: Config.showUpdates || Config.showPowerProfiles || Config.showIdleInhibitor || Config.showRofi || Config.showTray
                    Modules.Updates       { visible: Config.showUpdates }
                    Modules.IdleInhibitor { visible: Config.showIdleInhibitor }
                    Modules.PowerProfiles { visible: Config.showPowerProfiles }
                    Item {
                        visible: Config.showRofi
                        implicitWidth: _triRofiIcon.implicitWidth + Config.modPadH * 2
                        implicitHeight: Config.moduleHeight
                        Text {
                            id: _triRofiIcon; anchors.centerIn: parent
                            text: "󰓐"; color: Config.glyphColor
                            font.family: Config.fontFamily; font.pixelSize: Config.fontSize
                        }
                        ToolTip.visible: false; ToolTip.text: ""; ToolTip.delay: 500
                        opacity: _triRofiMa.containsMouse ? 0.7 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                        MouseArea {
                            id: _triRofiMa; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!rofiProc.running) rofiProc.running = true
                        }
                    }
                    Modules.SystemTray { visible: Config.showTray; rootWindow: bar }
                }
                Island { bgType: "activewindow"; visible_: Config.showWindow; Modules.ActiveWindow {} }
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
