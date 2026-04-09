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

    Component.onCompleted: barStateTimer.start()

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
        //  bgType selects which Tab 6 · Background color/opacity to use.
        //  ""            → uses Theme.cOnSecondary (legacy default)
        //  "workspace"   → Config.wsBgColor / wsBgOpacity
        //  "grouped"     → Config.groupedBgColor / groupedBgOpacity
        //  "ungrouped"   → Config.ungroupedBgColor / ungroupedBgOpacity
        //  "media"       → Config.mediaBgColor / mediaBgOpacity
        //  "cava"        → Config.cavaBgColor / cavaBgOpacity
        //  "distro"      → Config.distroBgColor / distroBgOpacity
        //  "activewindow"→ Config.activeWindowBgColor / activeWindowBgOpacity
        property string bgType: ""
        visible: visible_ && innerRow.implicitWidth > 0

        implicitWidth:  innerRow.implicitWidth
        implicitHeight: Config.moduleHeight

        // Resolve effective bg color from bgType (fallback to cOnSecondary)
        readonly property color _effectiveBgColor: {
            switch (bgType) {
                case "workspace":    return Config.wsBgColor
                case "grouped":      return Config.groupedBgColor
                case "ungrouped":    return Config.ungroupedBgColor
                case "startmenu":    return Config.startMenuBgColor
                case "media":        return Config.mediaBgColor
                case "cava":         return Config.cavaBgColor
                case "distro":       return Config.distroBgColor
                case "tray":         return Config.trayBgColor
                case "activewindow": return Config.activeWindowBgColor
                default:             return Theme.cOnSecondary
            }
        }

        // Resolve effective bg opacity (-1 = fall through to global)
        readonly property real _effectiveBgOpacity: {
            let raw = -1
            switch (bgType) {
                case "workspace":    raw = Config.wsBgOpacity; break
                case "grouped":      raw = Config.groupedBgOpacity; break
                case "ungrouped":    raw = Config.ungroupedBgOpacity; break
                case "startmenu":    raw = Config.startMenuBgOpacity; break
                case "media":        raw = Config.mediaBgOpacity; break
                case "cava":         raw = Config.cavaBgOpacity; break
                case "distro":       raw = Config.distroBgOpacity; break
                case "tray":         raw = Config.trayBgOpacity; break
                case "activewindow": raw = Config.activeWindowBgOpacity; break
            }
            if (raw > -0.5) return raw   // 0.0 = truly transparent; only -1 sentinel falls through
            return bgOverride > -0.5 ? bgOverride
                : (Config.barMode === "bar" ? Config.islandBgOpacityBar : Config.islandBgOpacityIsland)
        }

        readonly property real _bgOpacity: _effectiveBgOpacity

        // Pill border + background fill
        Rectangle {
            anchors.fill: parent
            radius: Config.islandRadius
            color: "transparent"
            border.width: Config.islandBorder
            border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b,
                                  Config.islandBorderAlpha)
            clip: true

            // Flat fill — shown when islandBgStyle is "flat" (default bar-mode look)
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                visible: Config.islandBgStyle === "flat"
                color: Qt.rgba(isl._effectiveBgColor.r, isl._effectiveBgColor.g,
                               isl._effectiveBgColor.b, isl._bgOpacity)
                Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
            }
            // Gradient fill — shown when islandBgStyle is "gradient" (island-mode look)
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
            // No extra padding — each module already includes modPadH in its own implicitWidth
        }
    }

    // ── Rofi process (shared, declared at bar level) ─────────────────────────
    Process {
        id: rofiProc
        command: [Config.hyprScripts + "/rofi-menus.sh"]
        running: false
    }

    // ── Root layout ─────────────────────────────────────────────────────────
    //  Horizontal: RowLayout with left-group | expanding spacers | center | spacers | right-group
    //  outerMarginSide shrinks the whole panel → spacers compress → sections move together.
    Item {
        id: barLayout
        // Anchor to barBg so all rows are positioned relative to the visible
        // bar rectangle (already inset by outerMarginSide), not the raw PanelWindow.
        anchors {
            left:   barBg.left
            right:  barBg.right
            top:    barBg.top
            bottom: barBg.bottom
        }
        // ── Respected spacing: 4 px gap between left/center/right rects ──────
        //  Computes how much space the left row may use before it would overlap
        //  the center row by less than 4 px. The media-info text shrinks into
        //  that budget via the mediaMaxWidth property passed to MediaPlayer.
        readonly property int _minGap: 4
        // Tracks whether any MediaPlayer is active (Playing or Paused)
        // Used by cava auto-hide logic.
        property bool _mediaActive: MediaPlayerState.active
        // Left group natural width (without media text — just controls + disc)
        // Right group natural width
        // Available width for left group = center.x - leftEdge - minGap
        readonly property real _leftEdge:   Config.islandSpacing + Config.barEdgePaddingLeft
        readonly property real _rightEdge:  Config.islandSpacing + Config.barEdgePaddingRight
        // Center row x position (horizontalCenter of barLayout)
        readonly property real _centerX:    width / 2
        // Max x the left row's right edge can reach
        readonly property real _leftMaxRight: _centerX - _minGap
        // Max x the right row's left edge can start
        readonly property real _rightMinLeft: _centerX + _minGap
        // Exposed to MediaPlayer via property; MediaPlayer caps its implicitWidth
        // to this value so the text shrinks before overlapping the center.
        // -1 means unconstrained.
        readonly property real mediaMaxWidth: {
            const leftRowNaturalW = leftGroup.implicitWidth
            const leftRowX = _leftEdge
            const leftRowRight = leftRowX + leftRowNaturalW
            if (leftRowRight <= _leftMaxRight) return -1
            // How much to trim: leftRowNaturalW - (leftMaxRight - leftRowX)
            const budget = _leftMaxRight - leftRowX
            return Math.max(0, budget)
        }
        // Same logic for right group
        readonly property real rightMaxWidth: {
            const rightRowNaturalW = rightGroup.implicitWidth
            const rightRowX = width - _rightEdge - rightRowNaturalW
            if (rightRowX >= _rightMinLeft) return -1
            const budget = width - _rightEdge - _rightMinLeft
            return Math.max(0, budget)
        }

        // ════════════════════════ HORIZONTAL BAR ═══════════════════════════
        // Three absolutely-positioned rows:
        //   LEFT  — anchored to left  + outerMarginSide (= same edge gap as right)
        //   RIGHT — anchored to right + outerMarginSide
        //   CENTER— anchored to horizontalCenter of parent (always truly centered)
        // As outerMarginSide grows, left/right rows move inward; center stays put.
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

            Island { bgType: "workspace"; Modules.Workspaces {} }

            Island {
                bgType: "grouped"
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
                    // Shrink media info when left group would overlap center
                    mediaMaxW: barLayout.mediaMaxWidth
                    property bool mediaActive: _active
                }
            }
        }

        // ── CENTER GROUP (always truly centered) ───────────────────────────────────────────
        Row {
            visible: bar._isHorizontal && Config.barMode !== "tri"
            anchors.centerIn: parent
            spacing: Config.islandSpacing

            Island { bgType: "cava";     visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaLeft; side: "left" } }
            Island { bgType: "ungrouped"; Modules.Clock {} }
            Island {
                bgType: "distro"
                visible_: Config.showDistro
                bgOverride: Config.ccTransparentBg ? 0.0 : (Config.distroBgOpacity >= 0 ? Config.distroBgOpacity : -1)
                Modules.ControlCenter {}
            }
            Island { bgType: "ungrouped"; Modules.DateDisplay {} }
            Island { bgType: "cava";     visible_: Config.showCava && (!Config.cavaAutoHide || barLayout._mediaActive); Modules.Cava { id: cavaRight; side: "right" } }
        }
        // ── RIGHT GROUP ────────────────────────────────────────────────────────────
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
            Island { bgType: "ungrouped"; visible_: Config.showBattery;  Modules.Battery {} }
            Island { bgType: "ungrouped"; visible_: Config.showWeather;  Modules.Weather {} }

            Island {
                bgType: "grouped"
                visible_: Config.showUpdates || Config.showPowerProfiles || Config.showIdleInhibitor || Config.showRofi
                Modules.Updates       { visible: Config.showUpdates }
                Modules.IdleInhibitor { visible: Config.showIdleInhibitor }
                Modules.PowerProfiles { visible: Config.showPowerProfiles }
                Item {
                    visible: Config.showRofi
                    implicitWidth: _rofiIcon.implicitWidth + Config.modPadH * 2
                    implicitHeight: Config.moduleHeight
                    Text {
                        id: _rofiIcon; anchors.centerIn: parent
                        text: ""; color: Config.glyphColor
                        font.family: Config.fontFamily; font.pixelSize: Config.fontSize
                    }
                    ToolTip.visible: false; ToolTip.text: ""; ToolTip.delay: 500
                    opacity: _rofiMa.containsMouse ? 0.7 : 1.0
                    Behavior on opacity { NumberAnimation { duration: 150 } }
                    MouseArea { id: _rofiMa; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!rofiProc.running) rofiProc.running = true }
                }
            }

            Island {
                bgType: "tray"
                visible_: Config.showTray
                Modules.SystemTray {
                    rootWindow: bar
                    // Shrink tray when right group would overlap center
                    trayMaxW: barLayout.rightMaxWidth
                }
            }
            Island { bgType: "activewindow"; visible_: Config.showWindow; Modules.ActiveWindow {} }
        }
        // ════════════════════════ TRI-ISLANDS MODEE ════════════════════════
        // Three separate bar-background rectangles, one per group (left / center /
        // right). Each rect uses the same barBg styling (blurBackground fill +
        // border + barRadius) so the three bars share a unified look while being
        // physically separated. Spacing between them uses outerMarginSide so they
        // sit the same distance apart as islands do in island mode.
        //
        // The left bar is left-anchored, the right bar is right-anchored, and the
        // center bar is centered — exactly mirroring the normal island layout but
        // each group now has its own enclosing bar background.
        //
        // Internal module layout is unchanged: same Island pills inside each bar.

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

                Island { bgType: "workspace"; Modules.Workspaces {} }
                Island {
                    bgType: "grouped"
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
                        // Tri-mode: shrink media if left bar approaches center bar
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
                Island { bgType: "ungrouped"; Modules.Clock {} }
                Island {
                    bgType: "distro"
                    visible_: Config.showDistro
                    bgOverride: Config.ccTransparentBg ? 0.0 : (Config.distroBgOpacity >= 0 ? Config.distroBgOpacity : -1)
                    Modules.ControlCenter {}
                }
                Island { bgType: "ungrouped"; Modules.DateDisplay {} }
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
                Island { bgType: "ungrouped"; visible_: Config.showBattery;  Modules.Battery {} }
                Island { bgType: "ungrouped"; visible_: Config.showWeather;  Modules.Weather {} }

                Island {
                    bgType: "grouped"
                    visible_: Config.showUpdates || Config.showPowerProfiles || Config.showIdleInhibitor || Config.showRofi
                    Modules.Updates       { visible: Config.showUpdates }
                    Modules.IdleInhibitor { visible: Config.showIdleInhibitor }
                    Modules.PowerProfiles { visible: Config.showPowerProfiles }
                    Item {
                        visible: Config.showRofi
                        implicitWidth: _triRofiIcon.implicitWidth + Config.modPadH * 2
                        implicitHeight: Config.moduleHeight
                        Text {
                            id: _triRofiIcon; anchors.centerIn: parent
                            text: ""; color: Config.glyphColor
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
                }

                Island {
                    bgType: "tray"
                    visible_: Config.showTray
                    Modules.SystemTray {
                        rootWindow: bar
                        // Tri-mode: shrink tray if right bar approaches center bar
                        trayMaxW: {
                            const gap = 4
                            const centerRight = triCenter.x + triCenter.width
                            const rightLeft = triRight.x
                            const available = rightLeft - centerRight - gap
                            if (available >= 0) return -1
                            return Math.max(0, triRight.width + available - (Config.barEdgePaddingLeft + Config.barEdgePaddingRight + Config.islandSpacing * 2))
                        }
                    }
                }
                Island { bgType: "activewindow"; visible_: Config.showWindow; Modules.ActiveWindow {} }
            }
        }
        // ════════════════════════ VERTICAL BAR ════════════════════════════
        // Vertical bars use Column layout with the same islands rotated
        Column {
            visible: !bar._isHorizontal
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top; bottom: parent.bottom
            }
            spacing: Config.islandSpacing
            padding: Config.outerMarginEdge

            // Top group: workspaces stacked
            Island {
                Modules.Workspaces { vertical: true }
            }

            // Spacer
            Item { implicitWidth: 1; implicitHeight: Config.islandSpacing * 2 }

            // Center: clock
            Island { Modules.Clock {} }

            // Spacer
            Item { implicitWidth: 1; implicitHeight: Config.islandSpacing * 2 }

            // Bottom group: tray + power
            Island { bgType: "tray"; visible_: Config.showTray; Modules.SystemTray { rootWindow: bar } }
            Island { bgType: "startmenu"; Modules.PowerButton {} }
        }
    }
}
