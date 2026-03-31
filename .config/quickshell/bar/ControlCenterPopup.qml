pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  Control Center — replaces the GJS candy-utils.js control center.
//  Transparent 0.4 alpha background, side-menu tabs, live Config adjustment.
//  Tabs: Bar, Hyprland, Themes, Dock, Menus, SDDM
// ═══════════════════════════════════════════════════════════════════════════
PanelWindow {
    id: ccWin

    anchors {
        top: true
        left: Config.barPosition === "left"
        right: Config.barPosition !== "left"
    }
    margins {
        top: Config.barHeight + Config.outerMarginTop + Config.outerMarginBottom + 6
        left: Config.barPosition === "left" ? Config.barHeight + 6 : 0
        right: Config.barPosition === "left" ? 0 : 6
    }

    implicitWidth: 370
    implicitHeight: 680

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-controlcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    color: "transparent"

    // Close on Escape
    Item {
        focus: true
        Keys.onEscapePressed: ControlCenterState.close()
    }

    // ── Main background ────────────────────────────────────────────────────
    Rectangle {
        id: ccBg
        anchors.fill: parent
        radius: 16
        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                       Theme.cOnSecondary.b, 0.4)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g,
                              Theme.cOutVar.b, 0.3)
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 4

            // ── Tab bar (horizontal) ─────────────────────────────────────
            Row {
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                spacing: 2

                Repeater {
                    model: [
                        { label: "󱟛 Bar",       tab: "bar" },
                        { label: " Hyprland", tab: "hyprland" },
                        { label: "󰔎 Themes",    tab: "themes" },
                        { label: "󰞒 Dock",      tab: "dock" },
                        { label: "󰮫 Menus",     tab: "menus" },
                        { label: "󰍂 SDDM",     tab: "sddm" }
                    ]

                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        width: (ccBg.width - 16 - 10) / 6
                        height: 30
                        radius: 8
                        color: tabStack.currentIndex === index
                            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                      Theme.cInversePrimary.b, 0.7)
                            : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                      Theme.cInversePrimary.b, 0.2)
                        border.width: tabStack.currentIndex === index ? 1 : 0
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                              Theme.cPrimary.b, 0.5)

                        Text {
                            anchors.centerIn: parent
                            text: modelData.label
                            color: Theme.cPrimary
                            font.family: Config.fontFamily
                            font.pixelSize: 11
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: tabStack.currentIndex = index
                        }

                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                }
            }

            // ── Tab content ─────────────────────────────────────────────
            StackLayout {
                id: tabStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: 0

                // TAB 0: Bar
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: barCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: barCol
                        width: parent.width
                        spacing: 6

                        // ── General ──────────────────────────────────────
                        CCHeading { text: "General" }

                        CCToggleRow {
                            label: "Mode"
                            value: Config.barMode === "island"
                            onText: "Island 󰇘"
                            offText: "Bar 󱟛"
                            onToggled: function(v) { Config.barMode = v ? "island" : "bar" }
                        }

                        CCToggleRow {
                            label: "Position"
                            value: Config.barPosition === "bottom"
                            onText: "Bottom 󰅀"
                            offText: "Top 󰅃"
                            onToggled: function(v) { Config.barPosition = v ? "bottom" : "top" }
                        }

                        CCSliderRow {
                            label: "Bar Height"
                            from: 20; to: 60; stepSize: 1
                            value: Config.barHeight
                            onMoved: function(v) { Config.barHeight = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Module Height"
                            from: 14; to: 50; stepSize: 1
                            value: Config.moduleHeight
                            onMoved: function(v) { Config.moduleHeight = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Side Margin"
                            from: 0; to: 40; stepSize: 1
                            value: Config.outerMarginSide
                            onMoved: function(v) { Config.outerMarginSide = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Top Margin"
                            from: 0; to: 20; stepSize: 1
                            value: Config.outerMarginTop
                            onMoved: function(v) { Config.outerMarginTop = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Bottom Margin"
                            from: 0; to: 20; stepSize: 1
                            value: Config.outerMarginBottom
                            onMoved: function(v) { Config.outerMarginBottom = Math.round(v) }
                        }

                        // ── Radii & Borders ──────────────────────────────
                        CCHeading { text: "Radii & Borders" }

                        CCSliderRow {
                            label: "Bar Radius"
                            from: 0; to: 40; stepSize: 1
                            value: Config.barRadius
                            onMoved: function(v) { Config.barRadius = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Island Radius"
                            from: 0; to: 40; stepSize: 1
                            value: Config.islandRadius
                            onMoved: function(v) { Config.islandRadius = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Bar Border"
                            from: 0; to: 6; stepSize: 1
                            value: Config.barBorderWidth
                            onMoved: function(v) { Config.barBorderWidth = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Island Border"
                            from: 0; to: 6; stepSize: 1
                            value: Config.islandBorder
                            onMoved: function(v) { Config.islandBorder = Math.round(v) }
                        }

                        // ── Spacing & Padding ────────────────────────────
                        CCHeading { text: "Spacing & Padding" }

                        CCSliderRow {
                            label: "Island Spacing"
                            from: 0; to: 20; stepSize: 1
                            value: Config.islandSpacing
                            onMoved: function(v) { Config.islandSpacing = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Grouped Spacing"
                            from: 0; to: 10; stepSize: 1
                            value: Config.groupedSpacing
                            onMoved: function(v) { Config.groupedSpacing = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Module Pad H"
                            from: 0; to: 20; stepSize: 1
                            value: Config.modPadH
                            onMoved: function(v) { Config.modPadH = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Module Pad V"
                            from: 0; to: 10; stepSize: 1
                            value: Config.modPadV
                            onMoved: function(v) { Config.modPadV = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Edge Pad Left"
                            from: 0; to: 20; stepSize: 1
                            value: Config.barEdgePaddingLeft
                            onMoved: function(v) { Config.barEdgePaddingLeft = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Edge Pad Right"
                            from: 0; to: 20; stepSize: 1
                            value: Config.barEdgePaddingRight
                            onMoved: function(v) { Config.barEdgePaddingRight = Math.round(v) }
                        }

                        // ── Opacity ──────────────────────────────────────
                        CCHeading { text: "Opacity" }

                        CCSliderRow {
                            label: "Module BG"
                            from: 0.0; to: 1.0; stepSize: 0.05
                            value: Config.moduleBgOpacity
                            decimals: 2
                            onMoved: function(v) { Config.moduleBgOpacity = v }
                        }

                        CCSliderRow {
                            label: "Island BG (Island)"
                            from: 0.0; to: 1.0; stepSize: 0.05
                            value: Config.islandBgOpacityIsland
                            decimals: 2
                            onMoved: function(v) { Config.islandBgOpacityIsland = v }
                        }

                        CCSliderRow {
                            label: "Island BG Alpha"
                            from: 0.0; to: 1.0; stepSize: 0.05
                            value: Config.islandBgAlpha
                            decimals: 2
                            onMoved: function(v) { Config.islandBgAlpha = v }
                        }

                        CCSliderRow {
                            label: "Bar Border Alpha"
                            from: 0.0; to: 1.0; stepSize: 0.05
                            value: Config.barBorderAlpha
                            decimals: 2
                            onMoved: function(v) { Config.barBorderAlpha = v }
                        }

                        CCSliderRow {
                            label: "Island Border Alpha"
                            from: 0.0; to: 1.0; stepSize: 0.05
                            value: Config.islandBorderAlpha
                            decimals: 2
                            onMoved: function(v) { Config.islandBorderAlpha = v }
                        }

                        // ── Sizes ────────────────────────────────────────
                        CCHeading { text: "Sizes" }

                        CCSliderRow {
                            label: "Glyph Size"
                            from: 8; to: 24; stepSize: 1
                            value: Config.glyphSize
                            onMoved: function(v) { Config.glyphSize = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Info Glyph Size"
                            from: 8; to: 24; stepSize: 1
                            value: Config.infoGlyphSize
                            onMoved: function(v) { Config.infoGlyphSize = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Info Font Size"
                            from: 8; to: 20; stepSize: 1
                            value: Config.infoFontSize
                            onMoved: function(v) { Config.infoFontSize = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Label Font Size"
                            from: 8; to: 20; stepSize: 1
                            value: Config.labelFontSize
                            onMoved: function(v) { Config.labelFontSize = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Media Font Size"
                            from: 8; to: 20; stepSize: 1
                            value: Config.mediaInfoFontSize
                            onMoved: function(v) { Config.mediaInfoFontSize = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Media Glyph Size"
                            from: 8; to: 24; stepSize: 1
                            value: Config.mediaGlyphSize
                            onMoved: function(v) { Config.mediaGlyphSize = Math.round(v) }
                        }

                        // ── Workspaces ────────────────────────────────────
                        CCHeading { text: "Workspaces" }

                        CCToggleRow {
                            label: "WS Mode"
                            value: Config.wsIconMode === "icon"
                            onText: "Icons"
                            offText: Config.wsIconMode === "number" ? "Numbers" : "Dots"
                            onToggled: function(v) {
                                if (v) Config.wsIconMode = "icon"
                                else Config.wsIconMode = Config.wsIconMode === "icon" ? "dot" : Config.wsIconMode
                            }
                        }

                        Row {
                            Layout.fillWidth: true
                            spacing: 4
                            CCBtn {
                                text: "Dot"
                                active: Config.wsIconMode === "dot"
                                onClicked: Config.wsIconMode = "dot"
                            }
                            CCBtn {
                                text: "Number"
                                active: Config.wsIconMode === "number"
                                onClicked: Config.wsIconMode = "number"
                            }
                            CCBtn {
                                text: "Icon"
                                active: Config.wsIconMode === "icon"
                                onClicked: Config.wsIconMode = "icon"
                            }
                        }

                        CCSliderRow {
                            label: "WS Glyph Size"
                            from: 8; to: 24; stepSize: 1
                            value: Config.wsGlyphSize
                            onMoved: function(v) { Config.wsGlyphSize = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "WS Spacing"
                            from: 0; to: 16; stepSize: 1
                            value: Config.wsSpacing
                            onMoved: function(v) { Config.wsSpacing = Math.round(v) }
                        }

                        CCToggleRow {
                            label: "WS Separators"
                            value: Config.wsSeparators
                            onToggled: function(v) { Config.wsSeparators = v }
                        }

                        // ── Cava ─────────────────────────────────────────
                        CCHeading { text: "Cava" }

                        CCSliderRow {
                            label: "Cava Width"
                            from: 5; to: 60; stepSize: 1
                            value: Config.cavaWidth
                            onMoved: function(v) { Config.cavaWidth = Math.round(v) }
                        }

                        Row {
                            Layout.fillWidth: true
                            spacing: 3
                            Repeater {
                                model: ["dots", "bars", "braille_fill", "blocks", "thin_bars"]
                                delegate: CCBtn {
                                    required property string modelData
                                    text: modelData
                                    active: Config.cavaStyle === modelData
                                    onClicked: Config.cavaStyle = modelData
                                }
                            }
                        }

                        CCToggleRow {
                            label: "Cava Gradient"
                            value: Config.cavaGradientEnabled
                            onToggled: function(v) { Config.cavaGradientEnabled = v }
                        }

                        // ── Media ────────────────────────────────────────
                        CCHeading { text: "Media" }

                        CCSliderRow {
                            label: "Thumb Size"
                            from: 10; to: 30; stepSize: 1
                            value: Config.mediaThumbSize
                            onMoved: function(v) { Config.mediaThumbSize = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Play/Pause Size"
                            from: 4; to: 14; stepSize: 1
                            value: Config.mediaPlayPauseSize
                            onMoved: function(v) { Config.mediaPlayPauseSize = Math.round(v) }
                        }

                        // ── System Tray ──────────────────────────────────
                        CCHeading { text: "System Tray" }

                        CCSliderRow {
                            label: "Icon Size"
                            from: 10; to: 32; stepSize: 1
                            value: Config.trayIconSz
                            onMoved: function(v) { Config.trayIconSz = Math.round(v) }
                        }

                        CCSliderRow {
                            label: "Item Spacing"
                            from: 0; to: 10; stepSize: 1
                            value: Config.trayItemSpacing
                            onMoved: function(v) { Config.trayItemSpacing = Math.round(v) }
                        }

                        // ── Battery ──────────────────────────────────────
                        CCHeading { text: "Battery" }

                        CCToggleRow {
                            label: "Radial Indicator"
                            value: Config.batteryRadialVisible
                            onToggled: function(v) { Config.batteryRadialVisible = v }
                        }

                        CCSliderRow {
                            label: "Radial Size"
                            from: 8; to: 24; stepSize: 1
                            value: Config.batteryRadialSize
                            onMoved: function(v) { Config.batteryRadialSize = Math.round(v) }
                        }

                        // ── Module Visibility ────────────────────────────
                        CCHeading { text: "Module Visibility" }

                        CCToggleRow { label: "Cava";          value: Config.showCava;          onToggled: function(v) { Config.showCava = v } }
                        CCToggleRow { label: "Weather";       value: Config.showWeather;       onToggled: function(v) { Config.showWeather = v } }
                        CCToggleRow { label: "Battery";       value: Config.showBattery;       onToggled: function(v) { Config.showBattery = v } }
                        CCToggleRow { label: "Media Player";  value: Config.showMediaPlayer;   onToggled: function(v) { Config.showMediaPlayer = v } }
                        CCToggleRow { label: "Idle Inhibitor";value: Config.showIdleInhibitor; onToggled: function(v) { Config.showIdleInhibitor = v } }
                        CCToggleRow { label: "Rofi Launcher"; value: Config.showRofi;          onToggled: function(v) { Config.showRofi = v } }
                        CCToggleRow { label: "Updates";       value: Config.showUpdates;       onToggled: function(v) { Config.showUpdates = v } }
                        CCToggleRow { label: "Power Profiles";value: Config.showPowerProfiles; onToggled: function(v) { Config.showPowerProfiles = v } }
                        CCToggleRow { label: "Overview";      value: Config.showOverview;      onToggled: function(v) { Config.showOverview = v } }
                        CCToggleRow { label: "Notifications"; value: Config.showNotifications; onToggled: function(v) { Config.showNotifications = v } }
                        CCToggleRow { label: "Wallpaper";     value: Config.showWallpaper;     onToggled: function(v) { Config.showWallpaper = v } }
                        CCToggleRow { label: "System Tray";   value: Config.showTray;          onToggled: function(v) { Config.showTray = v } }
                        CCToggleRow { label: "Active Window"; value: Config.showWindow;        onToggled: function(v) { Config.showWindow = v } }
                        CCToggleRow { label: "Distro Icon";   value: Config.showDistro;        onToggled: function(v) { Config.showDistro = v } }

                        // ── Background Per-Type ──────────────────────────
                        CCHeading { text: "Background Per-Type" }

                        CCSliderRow {
                            label: "WS BG Opacity"
                            from: -1.0; to: 1.0; stepSize: 0.05
                            value: Config.wsBgOpacity
                            decimals: 2
                            onMoved: function(v) { Config.wsBgOpacity = v }
                        }

                        CCSliderRow {
                            label: "Grouped BG"
                            from: -1.0; to: 1.0; stepSize: 0.05
                            value: Config.groupedBgOpacity
                            decimals: 2
                            onMoved: function(v) { Config.groupedBgOpacity = v }
                        }

                        CCSliderRow {
                            label: "Ungrouped BG"
                            from: -1.0; to: 1.0; stepSize: 0.05
                            value: Config.ungroupedBgOpacity
                            decimals: 2
                            onMoved: function(v) { Config.ungroupedBgOpacity = v }
                        }

                        CCSliderRow {
                            label: "Media BG"
                            from: -1.0; to: 1.0; stepSize: 0.05
                            value: Config.mediaBgOpacity
                            decimals: 2
                            onMoved: function(v) { Config.mediaBgOpacity = v }
                        }

                        CCSliderRow {
                            label: "Cava BG"
                            from: -1.0; to: 1.0; stepSize: 0.05
                            value: Config.cavaBgOpacity
                            decimals: 2
                            onMoved: function(v) { Config.cavaBgOpacity = v }
                        }

                        CCSliderRow {
                            label: "Active Window BG"
                            from: -1.0; to: 1.0; stepSize: 0.05
                            value: Config.activeWindowBgOpacity
                            decimals: 2
                            onMoved: function(v) { Config.activeWindowBgOpacity = v }
                        }

                        Item { implicitHeight: 8 }
                    }
                }

                // TAB 1: Hyprland
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: hyprCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: hyprCol
                        width: parent.width
                        spacing: 6

                        CCHeading { text: " Hyprland" }

                        // Hyprsunset toggle
                        CCToggleRow {
                            id: sunsetToggle
                            label: "Hyprsunset"
                            value: false
                            onText: "On 󰌵"
                            offText: "Off 󰌶"
                            onToggled: function(v) {
                                if (v) _sunsetOnProc.running = true
                                else   _sunsetOffProc.running = true
                            }
                        }
                        Process { id: _sunsetOnProc;  command: ["bash", "-c", "hyprsunset &"]; running: false }
                        Process { id: _sunsetOffProc; command: ["pkill", "hyprsunset"];        running: false }

                        // Gamma
                        Row {
                            Layout.fillWidth: true
                            spacing: 4
                            CCBtn { text: "γ −10"; onClicked: _gammaDec.running = true }
                            CCBtn { text: "γ +10"; onClicked: _gammaInc.running = true }
                        }
                        Process { id: _gammaDec; command: ["hyprctl", "hyprsunset", "gamma", "-10"]; running: false }
                        Process { id: _gammaInc; command: ["hyprctl", "hyprsunset", "gamma", "+10"]; running: false }

                        // Hyprpicker
                        CCBtn { text: "󰈊  Hyprpicker"; onClicked: _pickerProc.running = true }
                        Process { id: _pickerProc; command: ["hyprpicker"]; running: false }

                        // X-Ray toggle
                        CCToggleRow {
                            id: xrayToggle
                            label: "X-Ray"
                            value: false
                            onText: "On"
                            offText: "Off"
                            onToggled: function(v) { _xrayProc.running = true }
                        }
                        Process {
                            id: _xrayProc
                            command: ["bash", Config.hyprScripts + "/xray.sh"]
                            running: false
                        }

                        // Opacity toggle
                        CCToggleRow {
                            id: opacToggle
                            label: "Opacity"
                            value: false
                            onText: "On"
                            offText: "Off"
                            onToggled: function(v) { _opacProc.running = true }
                        }
                        Process {
                            id: _opacProc
                            command: ["bash", "-c", "$HOME/.config/hypr/scripts/window-opacity.sh"]
                            running: false
                        }

                        // Opacity +/-
                        Row {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Opacity"; color: Theme.cPrimary; font.pixelSize: 11; font.family: Config.labelFont; anchors.verticalCenter: parent.verticalCenter }
                            CCBtn { text: "−"; onClicked: _opacDec.running = true }
                            CCBtn { text: "+"; onClicked: _opacInc.running = true }
                        }
                        Process {
                            id: _opacDec
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/hypr/hyprviz.conf\"; " +
                                "v=$(grep 'active_opacity' \"$f\" | grep -oP '[0-9.]+'); " +
                                "nv=$(echo \"$v - 0.05\" | bc); " +
                                "[ $(echo \"$nv >= 0\" | bc) -eq 1 ] && " +
                                "sed -i \"s/active_opacity = .*/active_opacity = $nv/\" \"$f\" && " +
                                "sed -i \"s/inactive_opacity = .*/inactive_opacity = $nv/\" \"$f\" && " +
                                "hyprctl reload"]
                            running: false
                        }
                        Process {
                            id: _opacInc
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/hypr/hyprviz.conf\"; " +
                                "v=$(grep 'active_opacity' \"$f\" | grep -oP '[0-9.]+'); " +
                                "nv=$(echo \"$v + 0.05\" | bc); " +
                                "[ $(echo \"$nv <= 1\" | bc) -eq 1 ] && " +
                                "sed -i \"s/active_opacity = .*/active_opacity = $nv/\" \"$f\" && " +
                                "sed -i \"s/inactive_opacity = .*/inactive_opacity = $nv/\" \"$f\" && " +
                                "hyprctl reload"]
                            running: false
                        }

                        // Blur Size +/-
                        Row {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Blur Size"; color: Theme.cPrimary; font.pixelSize: 11; font.family: Config.labelFont; anchors.verticalCenter: parent.verticalCenter }
                            CCBtn { text: "−"; onClicked: _blurSizeDec.running = true }
                            CCBtn { text: "+"; onClicked: _blurSizeInc.running = true }
                        }
                        Process {
                            id: _blurSizeDec
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/hypr/hyprviz.conf\"; " +
                                "v=$(sed -n '/blur {/,/}/{ s/.*size = \\([0-9]*\\).*/\\1/p }' \"$f\"); " +
                                "nv=$((v > 0 ? v - 1 : 0)); " +
                                "sed -i '/blur {/,/}/{s/size = '$v'/size = '$nv'/}' \"$f\" && hyprctl reload"]
                            running: false
                        }
                        Process {
                            id: _blurSizeInc
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/hypr/hyprviz.conf\"; " +
                                "v=$(sed -n '/blur {/,/}/{ s/.*size = \\([0-9]*\\).*/\\1/p }' \"$f\"); " +
                                "nv=$((v + 1)); " +
                                "sed -i '/blur {/,/}/{s/size = '$v'/size = '$nv'/}' \"$f\" && hyprctl reload"]
                            running: false
                        }

                        // Blur Passes +/-
                        Row {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Blur Passes"; color: Theme.cPrimary; font.pixelSize: 11; font.family: Config.labelFont; anchors.verticalCenter: parent.verticalCenter }
                            CCBtn { text: "−"; onClicked: _blurPassesDec.running = true }
                            CCBtn { text: "+"; onClicked: _blurPassesInc.running = true }
                        }
                        Process {
                            id: _blurPassesDec
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/hypr/hyprviz.conf\"; " +
                                "v=$(grep 'passes = ' \"$f\" | grep -oP '[0-9]+'); " +
                                "nv=$((v > 0 ? v - 1 : 0)); " +
                                "sed -i 's/passes = '$v'/passes = '$nv'/' \"$f\" && hyprctl reload"]
                            running: false
                        }
                        Process {
                            id: _blurPassesInc
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/hypr/hyprviz.conf\"; " +
                                "v=$(grep 'passes = ' \"$f\" | grep -oP '[0-9]+'); " +
                                "nv=$((v + 1)); " +
                                "sed -i 's/passes = '$v'/passes = '$nv'/' \"$f\" && hyprctl reload"]
                            running: false
                        }

                        // Gap Presets
                        CCHeading { text: "Gap Presets" }

                        Row {
                            Layout.fillWidth: true
                            spacing: 3
                            Repeater {
                                model: ["minimal", "balanced", "spacious", "zero"]
                                delegate: CCBtn {
                                    required property string modelData
                                    text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                    onClicked: {
                                        _gapProc.command = ["bash", "-c",
                                            "$HOME/.config/hyprcandy/hooks/hyprland_gap_presets.sh " + modelData]
                                        _gapProc.running = true
                                    }
                                }
                            }
                        }
                        Process { id: _gapProc; running: false }

                        Item { implicitHeight: 8 }
                    }
                }

                // TAB 2: Themes
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: themesCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: themesCol
                        width: parent.width
                        spacing: 6

                        CCHeading { text: "󰔎 Matugen Themes" }

                        Repeater {
                            model: [
                                { name: "Light",       scheme: "scheme-fidelity" },
                                { name: "Dark",        scheme: "scheme-monochrome" },
                                { name: "Content",     scheme: "scheme-content" },
                                { name: "Expressive",  scheme: "scheme-expressive" },
                                { name: "Neutral",     scheme: "scheme-neutral" },
                                { name: "Rainbow",     scheme: "scheme-rainbow" },
                                { name: "Tonal-spot",  scheme: "scheme-tonal-spot" },
                                { name: "Fruit-salad", scheme: "scheme-fruit-salad" },
                                { name: "Vibrant",     scheme: "scheme-vibrant" }
                            ]
                            delegate: CCBtn {
                                required property var modelData
                                Layout.fillWidth: true
                                text: modelData.name
                                onClicked: {
                                    const scheme = modelData.scheme
                                    const name   = modelData.name
                                    const mode = name === "Light" ? "light" : "dark"
                                    _themeProc.command = ["bash", "-c",
                                        "sed -i 's/--type scheme-[^ ]*/--type " + scheme + "/' \"$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh\" && " +
                                        "sed -i 's/-m " + (mode === "light" ? "dark" : "light") + "/-m " + mode + "/g' \"$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh\" && " +
                                        "bash \"$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh\" && " +
                                        "echo '" + scheme + "' > \"$HOME/.config/hyprcandy/matugen-state\""]
                                    _themeProc.running = true
                                }
                            }
                        }
                        Process { id: _themeProc; running: false }

                        Item { implicitHeight: 8 }
                    }
                }

                // TAB 3: Dock
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: dockCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: dockCol
                        width: parent.width
                        spacing: 6

                        CCHeading { text: "󰞒 Dock" }

                        CCBtn {
                            Layout.fillWidth: true
                            text: "󰶘 Cycle Position"
                            onClicked: _dockCycleProc.running = true
                        }
                        Process {
                            id: _dockCycleProc
                            command: ["bash", Config.candyDir + "/GJS/hyprcandydock/cycle.sh"]
                            running: false
                        }

                        // Dock fields: spacing, padding, border, radius
                        Repeater {
                            model: [
                                { label: "Spacing",  key: "buttonSpacing", lo: 0, hi: 30 },
                                { label: "Padding",  key: "innerPadding",  lo: 0, hi: 30 },
                                { label: "Border W", key: "borderWidth",   lo: 0, hi: 10 },
                                { label: "Border R", key: "borderRadius",  lo: 0, hi: 100 }
                            ]
                            delegate: CCEntryRow {
                                required property var modelData
                                label: modelData.label
                                onApplied: function(val) {
                                    const n = parseInt(val)
                                    if (!isNaN(n) && n >= modelData.lo && n <= modelData.hi) {
                                        _dockWriteProc.command = ["bash", "-c",
                                            "f=\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\"; " +
                                            "sed -i 's/" + modelData.key + ": [0-9]*/" + modelData.key + ": " + n + "/' \"$f\" && " +
                                            "pkill -SIGUSR2 -f 'gjs dock-main.js'"]
                                        _dockWriteProc.running = true
                                    }
                                }
                            }
                        }
                        Process { id: _dockWriteProc; running: false }

                        // Icon Size (needs dock restart)
                        CCEntryRow {
                            label: "Icon Size"
                            onApplied: function(val) {
                                const n = parseInt(val)
                                if (!isNaN(n) && n >= 12 && n <= 64) {
                                    _dockIconProc.command = ["bash", "-c",
                                        "f=\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\"; " +
                                        "sed -i 's/appIconSize: [0-9]*/appIconSize: " + n + "/' \"$f\" && " +
                                        "t=\"$HOME/.hyprcandy/GJS/hyprcandydock/toggle.sh\"; " +
                                        "bash \"$t\" && sleep 1 && bash \"$t\""]
                                    _dockIconProc.running = true
                                }
                            }
                        }
                        Process { id: _dockIconProc; running: false }

                        Item { implicitHeight: 8 }
                    }
                }

                // TAB 4: Menus (Rofi)
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: menusCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: menusCol
                        width: parent.width
                        spacing: 6

                        CCHeading { text: "󰮫 Menus (Rofi)" }

                        CCEntryRow {
                            label: "Border"
                            onApplied: function(val) {
                                const n = parseInt(val)
                                if (!isNaN(n) && n >= 0 && n <= 10)
                                    _rofiBorderProc.command = ["bash", "-c",
                                        "f=\"$HOME/.config/hyprcandy/settings/rofi-border.rasi\"; " +
                                        "sed -i 's/border-width: [0-9]*px/border-width: " + n + "px/' \"$f\""]
                                _rofiBorderProc.running = true
                            }
                        }
                        Process { id: _rofiBorderProc; running: false }

                        CCEntryRow {
                            label: "Radius"
                            onApplied: function(val) {
                                const v = parseFloat(val)
                                if (!isNaN(v) && v >= 0 && v <= 5) {
                                    const vs = v.toFixed(1)
                                    _rofiRadiusProc.command = ["bash", "-c",
                                        "f=\"$HOME/.config/hyprcandy/settings/rofi-border-radius.rasi\"; " +
                                        "sed -i 's/border-radius: [0-9.]*em/border-radius: " + vs + "em/' \"$f\""]
                                    _rofiRadiusProc.running = true
                                }
                            }
                        }
                        Process { id: _rofiRadiusProc; running: false }

                        // Icon Size +/-
                        Row {
                            Layout.fillWidth: true
                            spacing: 4
                            Text { text: "Icon Size"; color: Theme.cPrimary; font.pixelSize: 11; font.family: Config.labelFont; anchors.verticalCenter: parent.verticalCenter }
                            CCBtn { text: "−"; onClicked: _rofiIconDec.running = true }
                            CCBtn { text: "+"; onClicked: _rofiIconInc.running = true }
                        }
                        Process {
                            id: _rofiIconDec
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/rofi/config.rasi\"; " +
                                "v=$(sed -n '/element-icon/,/}/{s/.*size:[[:space:]]*\\([0-9.]*\\)em.*/\\1/p}' \"$f\"); " +
                                "nv=$(echo \"$v - 0.5\" | bc); " +
                                "[ $(echo \"$nv >= 0.5\" | bc) -eq 1 ] && " +
                                "sed -i '/element-icon/,/}/{s/size:[[:space:]]*[0-9.]*em/size:                        '\"$nv\"'em/}' \"$f\""]
                            running: false
                        }
                        Process {
                            id: _rofiIconInc
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/rofi/config.rasi\"; " +
                                "v=$(sed -n '/element-icon/,/}/{s/.*size:[[:space:]]*\\([0-9.]*\\)em.*/\\1/p}' \"$f\"); " +
                                "nv=$(echo \"$v + 0.5\" | bc); " +
                                "sed -i '/element-icon/,/}/{s/size:[[:space:]]*[0-9.]*em/size:                        '\"$nv\"'em/}' \"$f\""]
                            running: false
                        }

                        Item { implicitHeight: 8 }
                    }
                }

                // TAB 5: SDDM
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: sddmCol.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                    ColumnLayout {
                        id: sddmCol
                        width: parent.width
                        spacing: 6

                        CCHeading { text: "󰍂 SDDM" }

                        readonly property string sddmTheme: "/usr/share/sddm/themes/sugar-candy/theme.conf"

                        CCEntryRow {
                            label: "Header"
                            onApplied: function(val) {
                                _sddmHeaderProc.command = ["sudo", "sed", "-i",
                                    "s|^HeaderText=.*|HeaderText=" + val + "|",
                                    sddmCol.sddmTheme]
                                _sddmHeaderProc.running = true
                            }
                        }
                        Process { id: _sddmHeaderProc; running: false }

                        CCEntryRow {
                            label: "Form Pos"
                            onApplied: function(val) {
                                _sddmFormProc.command = ["sudo", "sed", "-i",
                                    "s|^FormPosition=.*|FormPosition=" + val + "|",
                                    sddmCol.sddmTheme]
                                _sddmFormProc.running = true
                            }
                        }
                        Process { id: _sddmFormProc; running: false }

                        CCEntryRow {
                            label: "Blur R"
                            onApplied: function(val) {
                                const n = parseInt(val)
                                if (!isNaN(n) && n >= 0 && n <= 100) {
                                    _sddmBlurProc.command = ["sudo", "sed", "-i",
                                        "s|^BlurRadius=.*|BlurRadius=" + n + "|",
                                        sddmCol.sddmTheme]
                                    _sddmBlurProc.running = true
                                }
                            }
                        }
                        Process { id: _sddmBlurProc; running: false }

                        CCBtn {
                            Layout.fillWidth: true
                            text: "󰈈 Preview"
                            onClicked: _sddmPreviewProc.running = true
                        }
                        Process {
                            id: _sddmPreviewProc
                            command: ["sddm-greeter", "--test-mode", "--theme",
                                      "/usr/share/sddm/themes/sugar-candy"]
                            running: false
                        }

                        Item { implicitHeight: 8 }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Reusable inline components
    // ═══════════════════════════════════════════════════════════════════════

    // ── Section heading ───────────────────────────────────────────────────
    component CCHeading: Text {
        Layout.fillWidth: true
        Layout.topMargin: 6
        Layout.bottomMargin: 2
        color: Theme.cPrimary
        font.family: Config.labelFont
        font.pixelSize: 13
        font.weight: Font.Bold
    }

    // ── Slider with label + value display ─────────────────────────────────
    component CCSliderRow: RowLayout {
        property alias label: _slLabel.text
        property alias from: _sl.from
        property alias to: _sl.to
        property alias stepSize: _sl.stepSize
        property alias value: _sl.value
        property int decimals: 0
        signal moved(real v)

        Layout.fillWidth: true
        spacing: 4

        Text {
            id: _slLabel
            Layout.preferredWidth: 100
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Slider {
            id: _sl
            Layout.fillWidth: true
            height: 20
            onMoved: parent.moved(_sl.value)

            background: Rectangle {
                x: _sl.leftPadding
                y: _sl.topPadding + _sl.availableHeight / 2 - height / 2
                width: _sl.availableWidth
                height: 4
                radius: 2
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)

                Rectangle {
                    width: _sl.visualPosition * parent.width
                    height: parent.height
                    radius: 2
                    color: Theme.cPrimary
                }
            }

            handle: Rectangle {
                x: _sl.leftPadding + _sl.visualPosition * (_sl.availableWidth - width)
                y: _sl.topPadding + _sl.availableHeight / 2 - height / 2
                width: 14; height: 14
                radius: 7
                color: Theme.cInversePrimary
                border.color: Theme.cPrimary
                border.width: 1
            }
        }

        Text {
            Layout.preferredWidth: 36
            text: decimals > 0 ? _sl.value.toFixed(decimals) : Math.round(_sl.value).toString()
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: 10
            horizontalAlignment: Text.AlignRight
        }
    }

    // ── Toggle row ────────────────────────────────────────────────────────
    component CCToggleRow: RowLayout {
        property alias label: _tgLabel.text
        property bool value: false
        property string onText: "On"
        property string offText: "Off"
        signal toggled(bool v)

        Layout.fillWidth: true
        spacing: 4

        Text {
            id: _tgLabel
            Layout.preferredWidth: 110
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            height: 24
            radius: 6
            color: value
                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.7)
                : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.2)
            border.width: value ? 1 : 0
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                  Theme.cPrimary.b, 0.5)

            Text {
                anchors.centerIn: parent
                text: value ? onText : offText
                color: Theme.cPrimary
                font.family: Config.labelFont
                font.pixelSize: 10
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    value = !value
                    toggled(value)
                }
            }

            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    // ── Button ────────────────────────────────────────────────────────────
    component CCBtn: Rectangle {
        id: _btnRoot
        property alias text: _btnText.text
        property bool active: false
        signal clicked()

        implicitWidth: _btnText.implicitWidth + 16
        implicitHeight: 24
        radius: 6
        color: active
            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                      Theme.cInversePrimary.b, 0.7)
            : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                      Theme.cInversePrimary.b, 0.2)
        border.width: active ? 1 : 0
        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                              Theme.cPrimary.b, 0.5)

        Text {
            id: _btnText
            anchors.centerIn: parent
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: 10
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            hoverEnabled: true
            onClicked: _btnRoot.clicked()
            onContainsMouseChanged: {
                if (containsMouse) _btnRoot.opacity = 0.8
                else _btnRoot.opacity = 1.0
            }
        }

        Behavior on color { ColorAnimation { duration: 150 } }
        Behavior on opacity { NumberAnimation { duration: 100 } }
    }

    // ── Text entry row ────────────────────────────────────────────────────
    component CCEntryRow: RowLayout {
        property alias label: _entLabel.text
        signal applied(string val)

        Layout.fillWidth: true
        spacing: 4

        Text {
            id: _entLabel
            Layout.preferredWidth: 80
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true
            height: 24
            radius: 6
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                           Theme.cPrimary.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                  Theme.cPrimary.b, 0.15)

            TextInput {
                id: _entInput
                anchors.fill: parent
                anchors.margins: 4
                color: Theme.cPrimary
                font.family: Config.labelFont
                font.pixelSize: 11
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                onAccepted: applied(text)
            }
        }
    }
}
