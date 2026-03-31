pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  Control Center — hyprcandy quickshell edition.
//
//  Layout:
//    • Centered on screen: ~4/5 screen height × ~2/3 screen width
//    • Left sidebar (vertical nav) → Right content pane
//    • Sidebar: user info section at top, then tab buttons
//    • Content: Bar sub-tabs (General / Icons / Workspaces / Media /
//               Cava / Background / Visibility) + Hyprland / Themes /
//               Dock / Menus / SDDM
//
//  Slider style matches startmenu SliderBg exactly:
//    trough = 14 px tall, innerH = 8 px, gradient fill, dot-glyph thumb.
// ═══════════════════════════════════════════════════════════════════════════
PanelWindow {
    id: ccWin

    // Center on screen using anchors + screen-fraction sizing
    anchors { top: true; bottom: true; left: true; right: true }
    margins { top: 0; bottom: 0; left: 0; right: 0 }

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-controlcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    visible: ControlCenterState.visible

    // Overlay click-away backdrop
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.45)
        MouseArea {
            anchors.fill: parent
            onClicked: ControlCenterState.close()
        }
    }

    // ── The panel itself ───────────────────────────────────────────────────
    Rectangle {
        id: panel
        // ~2/3 width, ~4/5 height, centered
        width:  Math.min(900, parent.width  * 0.67)
        height: Math.min(760, parent.height * 0.82)
        anchors.centerIn: parent

        radius: 20
        color:  Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                        Theme.cOnSecondary.b, 0.92)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g,
                              Theme.cOutVar.b, 0.35)
        clip: true

        // Escape to close
        Keys.onEscapePressed: ControlCenterState.close()
        focus: true

        Row {
            anchors.fill: parent
            spacing: 0

            // ═══════════════════════════════════════════════════════════════
            //  LEFT SIDEBAR
            // ═══════════════════════════════════════════════════════════════
            Rectangle {
                id: sidebar
                width: 180
                height: parent.height
                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                               Theme.cOnSecondary.b, 0.6)
                // Right border separator
                Rectangle {
                    anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                    width: 1
                    color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.2)
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 12 }
                    spacing: 6

                    // ── User info ─────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 100
                        radius: 14
                        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                       Theme.cInversePrimary.b, 0.18)
                        border.width: 1
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                              Theme.cPrimary.b, 0.2)

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            // User icon circle — click to pick image
                            Rectangle {
                                id: userIconCircle
                                Layout.alignment: Qt.AlignHCenter
                                width: 52; height: 52; radius: 26
                                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                               Theme.cInversePrimary.b, 0.35)
                                border.width: 2
                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                      Theme.cPrimary.b, 0.6)
                                clip: true

                                Image {
                                    id: userImg
                                    anchors.fill: parent
                                    source: "file://" + Config.home + "/.config/hyprcandy/user-icon.png"
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: userImg.status !== Image.Ready
                                    text: ""
                                    font.family: Config.fontFamily
                                    font.pixelSize: 26
                                    color: Theme.cPrimary
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: userIconPicker.running = true
                                }
                                // Hover overlay
                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius
                                    color: Qt.rgba(0, 0, 0, 0.35)
                                    visible: iconHover.containsMouse
                                    Text {
                                        anchors.centerIn: parent; text: ""
                                        font.family: Config.fontFamily; font.pixelSize: 14
                                        color: Theme.cPrimary
                                    }
                                }
                                MouseArea {
                                    id: iconHover; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: userIconPicker.running = true
                                }
                            }

                            Text {
                                id: userNameText
                                Layout.alignment: Qt.AlignHCenter
                                text: "Loading..."
                                color: Theme.cPrimary
                                font.family: Config.labelFont
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // ── Nav buttons ───────────────────────────────────────
                    Repeater {
                        model: [
                            { icon: "󱟛", label: "Bar",       idx: 0 },
                            { icon: " ", label: "Hyprland",  idx: 1 },
                            { icon: "󰔎", label: "Themes",    idx: 2 },
                            { icon: "󰞒", label: "Dock",      idx: 3 },
                            { icon: "󰮫", label: "Menus",     idx: 4 },
                            { icon: "󰍂", label: "SDDM",      idx: 5 }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            height: 36; radius: 10
                            color: mainStack.currentIndex === modelData.idx
                                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                          Theme.cInversePrimary.b, 0.65)
                                : "transparent"
                            border.width: mainStack.currentIndex === modelData.idx ? 1 : 0
                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                  Theme.cPrimary.b, 0.4)

                            Row {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                          leftMargin: 12 }
                                spacing: 8
                                Text {
                                    text: modelData.icon
                                    font.family: Config.fontFamily; font.pixelSize: 14
                                    color: Theme.cPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.label
                                    font.family: Config.labelFont; font.pixelSize: 12
                                    font.weight: mainStack.currentIndex === modelData.idx
                                        ? Font.Medium : Font.Normal
                                    color: Theme.cPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            // Active indicator bar on right
                            Rectangle {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                width: 3; height: 18; radius: 2
                                color: Theme.cPrimary
                                visible: mainStack.currentIndex === modelData.idx
                            }

                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    mainStack.currentIndex = modelData.idx
                                    barSubStack.currentIndex = 0  // reset bar sub-tab
                                }
                            }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Version / close
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "hyprcandy"
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                           Theme.cPrimary.b, 0.4)
                            font.family: Config.labelFont; font.pixelSize: 9
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 22; height: 22; radius: 11
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                           Theme.cPrimary.b, 0.08)
                            Text {
                                anchors.centerIn: parent; text: "󰅙"
                                font.family: Config.fontFamily; font.pixelSize: 12
                                color: Theme.cPrimary
                            }
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: ControlCenterState.close()
                            }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════════════════════════════
            //  RIGHT CONTENT PANE
            // ═══════════════════════════════════════════════════════════════
            Item {
                width: panel.width - sidebar.width
                height: panel.height

                StackLayout {
                    id: mainStack
                    anchors.fill: parent
                    currentIndex: 0

                    // ── TAB 0: Bar ─────────────────────────────────────────
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 6

                            // Bar sub-tab header row
                            Row {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: ["General","Icons","Workspaces","Media","Cava","Background","Visibility"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        height: 28
                                        implicitWidth: _stLabel.implicitWidth + 16
                                        radius: 8
                                        color: barSubStack.currentIndex === index
                                            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                      Theme.cInversePrimary.b, 0.7)
                                            : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                      Theme.cInversePrimary.b, 0.18)
                                        border.width: barSubStack.currentIndex === index ? 1 : 0
                                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.45)
                                        Text {
                                            id: _stLabel; anchors.centerIn: parent
                                            text: modelData; color: Theme.cPrimary
                                            font.family: Config.labelFont; font.pixelSize: 10
                                            font.weight: barSubStack.currentIndex === index
                                                ? Font.Medium : Font.Normal
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: barSubStack.currentIndex = index
                                        }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }
                            }

                            // Bar sub-tab content
                            StackLayout {
                                id: barSubStack
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndex: 0

                                // ── General ─────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Mode & Position" }
                                        CCSegmented {
                                            label: "Bar Mode"
                                            options: ["bar", "island", "tri"]
                                            current: Config.barMode
                                            onPicked: function(v) { Config.barMode = v }
                                        }
                                        CCSegmented {
                                            label: "Position"
                                            options: ["top","bottom","left","right"]
                                            current: Config.barPosition
                                            onPicked: function(v) { Config.barPosition = v }
                                        }

                                        CCSection { text: "Dimensions" }
                                        CCSlider { label:"Bar Height";    from:20;to:80;  value:Config.barHeight;    onMoved:function(v){Config.barHeight=v} }
                                        CCSlider { label:"Module Height";  from:12;to:70;  value:Config.moduleHeight;  onMoved:function(v){Config.moduleHeight=v} }

                                        CCSection { text: "Screen Margins" }
                                        CCSlider { label:"Top Margin";    from:0;to:30; value:Config.outerMarginTop;    onMoved:function(v){Config.outerMarginTop=v} }
                                        CCSlider { label:"Bottom Margin"; from:0;to:30; value:Config.outerMarginBottom; onMoved:function(v){Config.outerMarginBottom=v} }
                                        CCSlider { label:"Side Margin";   from:0;to:80; value:Config.outerMarginSide;   onMoved:function(v){Config.outerMarginSide=v} }
                                        CCSlider { label:"Edge Pad Left"; from:0;to:30; value:Config.barEdgePaddingLeft; onMoved:function(v){Config.barEdgePaddingLeft=v} }
                                        CCSlider { label:"Edge Pad Right";from:0;to:30; value:Config.barEdgePaddingRight;onMoved:function(v){Config.barEdgePaddingRight=v} }

                                        CCSection { text: "Shape" }
                                        CCSlider { label:"Bar Radius";    from:0;to:40; value:Config.barRadius;    onMoved:function(v){Config.barRadius=v} }
                                        CCSlider { label:"Island Radius"; from:0;to:40; value:Config.islandRadius; onMoved:function(v){Config.islandRadius=v} }

                                        CCSection { text: "Borders" }
                                        CCSlider { label:"Bar Border";        from:0;to:8; value:Config.barBorderWidth;    onMoved:function(v){Config.barBorderWidth=v} }
                                        CCSlider { label:"Bar Border Alpha";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.barBorderAlpha;    onMoved:function(v){Config.barBorderAlpha=v} }
                                        CCSlider { label:"Island Border";     from:0;to:8; value:Config.islandBorder;      onMoved:function(v){Config.islandBorder=v} }
                                        CCSlider { label:"Island Border α";   from:0;to:1;stepSize:0.05;decimals:2; value:Config.islandBorderAlpha;  onMoved:function(v){Config.islandBorderAlpha=v} }

                                        CCSection { text: "Spacing & Padding" }
                                        CCSlider { label:"Island Spacing";  from:0;to:24; value:Config.islandSpacing;  onMoved:function(v){Config.islandSpacing=v} }
                                        CCSlider { label:"Grouped Spacing"; from:0;to:12; value:Config.groupedSpacing; onMoved:function(v){Config.groupedSpacing=v} }
                                        CCSlider { label:"Module Pad H";    from:0;to:20; value:Config.modPadH;        onMoved:function(v){Config.modPadH=v} }
                                        CCSlider { label:"Module Pad V";    from:0;to:12; value:Config.modPadV;        onMoved:function(v){Config.modPadV=v} }

                                        CCSection { text: "Opacity" }
                                        CCSlider { label:"Module BG";       from:0;to:1;stepSize:0.05;decimals:2; value:Config.moduleBgOpacity;       onMoved:function(v){Config.moduleBgOpacity=v} }
                                        CCSlider { label:"Island BG";       from:0;to:1;stepSize:0.05;decimals:2; value:Config.islandBgOpacityIsland;  onMoved:function(v){Config.islandBgOpacityIsland=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Icons ────────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Glyph Sizes" }
                                        CCSlider { label:"Glyph Size";      from:8;to:24; value:Config.glyphSize;      onMoved:function(v){Config.glyphSize=v} }
                                        CCSlider { label:"Info Glyph";      from:8;to:24; value:Config.infoGlyphSize;   onMoved:function(v){Config.infoGlyphSize=v} }
                                        CCSlider { label:"Media Glyph";     from:8;to:24; value:Config.mediaGlyphSize;  onMoved:function(v){Config.mediaGlyphSize=v} }

                                        CCSection { text: "Text Sizes" }
                                        CCSlider { label:"Info Text";       from:8;to:20; value:Config.infoFontSize;     onMoved:function(v){Config.infoFontSize=v} }
                                        CCSlider { label:"Label Text";      from:8;to:20; value:Config.labelFontSize;    onMoved:function(v){Config.labelFontSize=v} }
                                        CCSlider { label:"Media Text";      from:8;to:20; value:Config.mediaInfoFontSize;onMoved:function(v){Config.mediaInfoFontSize=v} }

                                        CCSection { text: "Workspace Icon Glyphs" }
                                        CCIconEntry { label:"Active Dot";     value:Config.wsDotActive;     onApplied:function(v){Config.wsDotActive=v} }
                                        CCIconEntry { label:"Persistent Dot"; value:Config.wsDotPersistent; onApplied:function(v){Config.wsDotPersistent=v} }
                                        CCIconEntry { label:"Empty Dot";      value:Config.wsDotEmpty;      onApplied:function(v){Config.wsDotEmpty=v} }
                                        CCIconEntry { label:"WS Separator";   value:Config.wsSeparatorGlyph;onApplied:function(v){Config.wsSeparatorGlyph=v} }

                                        CCSection { text: "Control Center & Power" }
                                        CCIconEntry { label:"CC Glyph";    value:Config.ccGlyph;    onApplied:function(v){Config.ccGlyph=v} }
                                        CCIconEntry { label:"Power Glyph"; value:Config.powerGlyph; onApplied:function(v){Config.powerGlyph=v} }

                                        CCSection { text: "Battery" }
                                        CCToggle { label:"Radial Visible"; value:Config.batteryRadialVisible; onToggled:function(v){Config.batteryRadialVisible=v} }
                                        CCSlider { label:"Radial Size";  from:8;to:32; value:Config.batteryRadialSize;  onMoved:function(v){Config.batteryRadialSize=v} }
                                        CCSlider { label:"Radial Stroke";from:1;to:6;  value:Config.batteryRadialWidth; onMoved:function(v){Config.batteryRadialWidth=v} }

                                        CCSection { text: "Tray" }
                                        CCSlider { label:"Icon Size";   from:10;to:32; value:Config.trayIconSz;     onMoved:function(v){Config.trayIconSz=v} }
                                        CCSlider { label:"Item Pad H";  from:0;to:8;   value:Config.trayItemPadH;   onMoved:function(v){Config.trayItemPadH=v} }
                                        CCSlider { label:"Item Spacing";from:0;to:10;  value:Config.trayItemSpacing; onMoved:function(v){Config.trayItemSpacing=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Workspaces ───────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Display Mode" }
                                        CCSegmented {
                                            label: "Icon Mode"
                                            options: ["dot","number","icon"]
                                            current: Config.wsIconMode
                                            onPicked: function(v) { Config.wsIconMode = v }
                                        }

                                        CCSection { text: "Sizing" }
                                        CCSlider { label:"Glyph Size";  from:8;to:24; value:Config.wsGlyphSize; onMoved:function(v){Config.wsGlyphSize=v} }

                                        CCSection { text: "Spacing (0 = true zero)" }
                                        CCSlider { label:"WS Spacing";    from:0;to:20; value:Config.wsSpacing;  onMoved:function(v){Config.wsSpacing=v} }
                                        CCSlider { label:"Margin Left";   from:0;to:20; value:Config.wsMarginLeft; onMoved:function(v){Config.wsMarginLeft=v} }
                                        CCSlider { label:"Margin Right";  from:0;to:20; value:Config.wsMarginRight;onMoved:function(v){Config.wsMarginRight=v} }

                                        CCSection { text: "Button Padding" }
                                        CCSlider { label:"Pad Left";   from:0;to:16; value:Config.wsPadLeft;   onMoved:function(v){Config.wsPadLeft=v} }
                                        CCSlider { label:"Pad Right";  from:0;to:16; value:Config.wsPadRight;  onMoved:function(v){Config.wsPadRight=v} }
                                        CCSlider { label:"Pad Top";    from:0;to:10; value:Config.wsPadTop;    onMoved:function(v){Config.wsPadTop=v} }
                                        CCSlider { label:"Pad Bottom"; from:0;to:10; value:Config.wsPadBottom; onMoved:function(v){Config.wsPadBottom=v} }

                                        CCSection { text: "Separators" }
                                        CCToggle { label:"Show Separators"; value:Config.wsSeparators; onToggled:function(v){Config.wsSeparators=v} }
                                        CCSlider { label:"Sep Size";   from:6;to:20; value:Config.wsSeparatorSize;     onMoved:function(v){Config.wsSeparatorSize=v} }
                                        CCSlider { label:"Sep Pad L";  from:0;to:10; value:Config.wsSeparatorPadLeft;  onMoved:function(v){Config.wsSeparatorPadLeft=v} }
                                        CCSlider { label:"Sep Pad R";  from:0;to:10; value:Config.wsSeparatorPadRight; onMoved:function(v){Config.wsSeparatorPadRight=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Media ─────────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Thumbnail" }
                                        CCSlider { label:"Thumb Size";     from:10;to:40; value:Config.mediaThumbSize;    onMoved:function(v){Config.mediaThumbSize=v} }

                                        CCSection { text: "Controls" }
                                        CCSlider { label:"Play/Pause Size";from:4;to:20;  value:Config.mediaPlayPauseSize; onMoved:function(v){Config.mediaPlayPauseSize=v} }

                                        CCSection { text: "Text" }
                                        CCSlider { label:"Info Text";      from:8;to:18;  value:Config.mediaInfoFontSize;  onMoved:function(v){Config.mediaInfoFontSize=v} }

                                        CCSection { text: "Padding (0 = true zero)" }
                                        CCSlider { label:"Pad Left";   from:0;to:16; value:Config.mediaPadLeft;   onMoved:function(v){Config.mediaPadLeft=v} }
                                        CCSlider { label:"Pad Right";  from:0;to:16; value:Config.mediaPadRight;  onMoved:function(v){Config.mediaPadRight=v} }
                                        CCSlider { label:"Pad Top";    from:0;to:10; value:Config.mediaPadTop;    onMoved:function(v){Config.mediaPadTop=v} }
                                        CCSlider { label:"Pad Bottom"; from:0;to:10; value:Config.mediaPadBottom; onMoved:function(v){Config.mediaPadBottom=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Cava ──────────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "ASCII Style" }
                                        // Style picker grid — 2 columns of pill buttons
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 4
                                            Repeater {
                                                model: Object.keys(Config.cavaStyleMap)
                                                delegate: Rectangle {
                                                    required property string modelData
                                                    width: 110; height: 28; radius: 8
                                                    color: Config.cavaStyle === modelData
                                                        ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                  Theme.cInversePrimary.b, 0.7)
                                                        : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                  Theme.cInversePrimary.b, 0.18)
                                                    border.width: Config.cavaStyle === modelData ? 1 : 0
                                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                          Theme.cPrimary.b, 0.5)
                                                    Row {
                                                        anchors.centerIn: parent; spacing: 4
                                                        Text {
                                                            text: Config.cavaStyleMap[modelData] || ""
                                                            font.family: Config.fontFamily
                                                            font.pixelSize: 9; color: Theme.cPrimary
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                        Text {
                                                            text: modelData; color: Theme.cPrimary
                                                            font.family: Config.labelFont; font.pixelSize: 9
                                                            anchors.verticalCenter: parent.verticalCenter
                                                        }
                                                    }
                                                    MouseArea {
                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                        onClicked: Config.cavaStyle = modelData
                                                    }
                                                    Behavior on color { ColorAnimation { duration: 120 } }
                                                }
                                            }
                                        }

                                        CCSection { text: "Width & Behavior" }
                                        CCSlider { label:"Cava Width";      from:5;to:60;  value:Config.cavaWidth; onMoved:function(v){Config.cavaWidth=v} }
                                        CCToggle { label:"Transparent Inactive"; value:Config.cavaTransparentWhenInactive; onToggled:function(v){Config.cavaTransparentWhenInactive=v} }
                                        CCSlider { label:"Active Opacity";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.cavaActiveOpacity;   onMoved:function(v){Config.cavaActiveOpacity=v} }
                                        CCSlider { label:"Inactive Opacity";from:0;to:1;stepSize:0.05;decimals:2; value:Config.cavaInactiveOpacity;  onMoved:function(v){Config.cavaInactiveOpacity=v} }

                                        CCSection { text: "Color" }
                                        CCToggle { label:"Gradient";value:Config.cavaGradientEnabled;onToggled:function(v){Config.cavaGradientEnabled=v} }
                                        CCColorPicker {
                                            label: "Color A"
                                            currentColor: Config.cavaGradientEnabled
                                                ? Config.cavaGradientStartColor : Config.cavaGlyphColor
                                        }
                                        CCColorPicker {
                                            label: "Color B (gradient)"
                                            currentColor: Config.cavaGradientEndColor
                                            enabled: Config.cavaGradientEnabled
                                        }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Background ────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Per-Group Background Opacity" }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "-1 = use global module BG opacity"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.5)
                                            font.family: Config.labelFont; font.pixelSize: 9
                                            wrapMode: Text.Wrap
                                        }

                                        CCSlider { label:"Workspaces";   from:-1;to:1;stepSize:0.05;decimals:2; value:Config.wsBgOpacity;          onMoved:function(v){Config.wsBgOpacity=v} }
                                        CCSlider { label:"Grouped";      from:-1;to:1;stepSize:0.05;decimals:2; value:Config.groupedBgOpacity;      onMoved:function(v){Config.groupedBgOpacity=v} }
                                        CCSlider { label:"Ungrouped";    from:-1;to:1;stepSize:0.05;decimals:2; value:Config.ungroupedBgOpacity;    onMoved:function(v){Config.ungroupedBgOpacity=v} }
                                        CCSlider { label:"Media";        from:-1;to:1;stepSize:0.05;decimals:2; value:Config.mediaBgOpacity;        onMoved:function(v){Config.mediaBgOpacity=v} }
                                        CCSlider { label:"Cava";         from:-1;to:1;stepSize:0.05;decimals:2; value:Config.cavaBgOpacity;         onMoved:function(v){Config.cavaBgOpacity=v} }
                                        CCSlider { label:"Active Window";from:-1;to:1;stepSize:0.05;decimals:2; value:Config.activeWindowBgOpacity; onMoved:function(v){Config.activeWindowBgOpacity=v} }

                                        CCSection { text: "Active Window" }
                                        CCSlider { label:"Min Width"; from:0;to:80; value:Config.activeWindowMinWidth; onMoved:function(v){Config.activeWindowMinWidth=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Visibility ────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Show / Hide Modules" }
                                        CCToggle { label:"Cava";           value:Config.showCava;           onToggled:function(v){Config.showCava=v} }
                                        CCToggle { label:"Weather";        value:Config.showWeather;        onToggled:function(v){Config.showWeather=v} }
                                        CCToggle { label:"Battery";        value:Config.showBattery;        onToggled:function(v){Config.showBattery=v} }
                                        CCToggle { label:"Media Player";   value:Config.showMediaPlayer;    onToggled:function(v){Config.showMediaPlayer=v} }
                                        CCToggle { label:"Idle Inhibitor"; value:Config.showIdleInhibitor;  onToggled:function(v){Config.showIdleInhibitor=v} }
                                        CCToggle { label:"Rofi";           value:Config.showRofi;           onToggled:function(v){Config.showRofi=v} }
                                        CCToggle { label:"Updates";        value:Config.showUpdates;        onToggled:function(v){Config.showUpdates=v} }
                                        CCToggle { label:"Power Profiles"; value:Config.showPowerProfiles;  onToggled:function(v){Config.showPowerProfiles=v} }
                                        CCToggle { label:"Overview";       value:Config.showOverview;       onToggled:function(v){Config.showOverview=v} }
                                        CCToggle { label:"Notifications";  value:Config.showNotifications;  onToggled:function(v){Config.showNotifications=v} }
                                        CCToggle { label:"Wallpaper Btn";  value:Config.showWallpaper;      onToggled:function(v){Config.showWallpaper=v} }
                                        CCToggle { label:"System Tray";    value:Config.showTray;           onToggled:function(v){Config.showTray=v} }
                                        CCToggle { label:"Active Window";  value:Config.showWindow;         onToggled:function(v){Config.showWindow=v} }
                                        CCToggle { label:"Distro Icon";    value:Config.showDistro;         onToggled:function(v){Config.showDistro=v} }

                                        Item { height: 10 }
                                    }
                                }
                            }
                        }
                    }

                    // ── TAB 1: Hyprland ────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5

                            CCSection { text: " Hyprland" }

                            CCToggle {
                                id: sunsetToggle; label: "Hyprsunset"; value: false
                                onToggled: function(v) {
                                    if (v) _sunsetOn.running = true
                                    else   _sunsetOff.running = true
                                }
                            }
                            Process { id: _sunsetOn;  command: ["bash","-c","hyprsunset &"]; running: false }
                            Process { id: _sunsetOff; command: ["pkill","hyprsunset"];       running: false }

                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text { text:"Gamma"; color:Theme.cPrimary; font.family:Config.labelFont; font.pixelSize:11; Layout.preferredWidth:90 }
                                CCPillBtn { text:"−10"; onClicked: _gammaDec.running=true }
                                CCPillBtn { text:"+10"; onClicked: _gammaInc.running=true }
                            }
                            Process { id: _gammaDec; command:["hyprctl","hyprsunset","gamma","-10"]; running:false }
                            Process { id: _gammaInc; command:["hyprctl","hyprsunset","gamma","+10"]; running:false }

                            CCPillBtn { text:"󰈊  Hyprpicker"; Layout.fillWidth:true; onClicked:_picker.running=true }
                            Process { id:_picker; command:["hyprpicker"]; running:false }

                            CCToggle { id:xrayToggle; label:"X-Ray"; value:false; onToggled:function(v){_xray.running=true} }
                            Process { id:_xray; command:["bash",Config.hyprScripts+"/xray.sh"]; running:false }

                            CCToggle { id:opacToggle; label:"Opacity"; value:false; onToggled:function(v){_opac.running=true} }
                            Process { id:_opac; command:["bash","-c","$HOME/.config/hypr/scripts/window-opacity.sh"]; running:false }

                            RowLayout { Layout.fillWidth:true; spacing:6
                                Text { text:"Opacity"; color:Theme.cPrimary; font.family:Config.labelFont; font.pixelSize:11; Layout.preferredWidth:90 }
                                CCPillBtn { text:"−"; onClicked:_opacDec.running=true }
                                CCPillBtn { text:"+"; onClicked:_opacInc.running=true }
                            }
                            Process { id:_opacDec; command:["bash","-c","f=\"$HOME/.config/hypr/hyprviz.conf\"; v=$(grep 'active_opacity' \"$f\" | grep -oP '[0-9.]+'); nv=$(echo \"$v - 0.05\" | bc); [ $(echo \"$nv >= 0\" | bc) -eq 1 ] && sed -i \"s/active_opacity = .*/active_opacity = $nv/\" \"$f\" && sed -i \"s/inactive_opacity = .*/inactive_opacity = $nv/\" \"$f\" && hyprctl reload"]; running:false }
                            Process { id:_opacInc; command:["bash","-c","f=\"$HOME/.config/hypr/hyprviz.conf\"; v=$(grep 'active_opacity' \"$f\" | grep -oP '[0-9.]+'); nv=$(echo \"$v + 0.05\" | bc); [ $(echo \"$nv <= 1\" | bc) -eq 1 ] && sed -i \"s/active_opacity = .*/active_opacity = $nv/\" \"$f\" && sed -i \"s/inactive_opacity = .*/inactive_opacity = $nv/\" \"$f\" && hyprctl reload"]; running:false }

                            RowLayout { Layout.fillWidth:true; spacing:6
                                Text { text:"Blur Size"; color:Theme.cPrimary; font.family:Config.labelFont; font.pixelSize:11; Layout.preferredWidth:90 }
                                CCPillBtn { text:"−"; onClicked:_blurSzDec.running=true }
                                CCPillBtn { text:"+"; onClicked:_blurSzInc.running=true }
                            }
                            Process { id:_blurSzDec; command:["bash","-c","f=\"$HOME/.config/hypr/hyprviz.conf\"; v=$(sed -n '/blur {/,/}/{ s/.*size = \\([0-9]*\\).*/\\1/p }' \"$f\"); nv=$((v > 0 ? v - 1 : 0)); sed -i \"/blur {/,/}/{s/size = $v/size = $nv/}\" \"$f\" && hyprctl reload"]; running:false }
                            Process { id:_blurSzInc; command:["bash","-c","f=\"$HOME/.config/hypr/hyprviz.conf\"; v=$(sed -n '/blur {/,/}/{ s/.*size = \\([0-9]*\\).*/\\1/p }' \"$f\"); nv=$((v + 1)); sed -i \"/blur {/,/}/{s/size = $v/size = $nv/}\" \"$f\" && hyprctl reload"]; running:false }

                            RowLayout { Layout.fillWidth:true; spacing:6
                                Text { text:"Blur Passes"; color:Theme.cPrimary; font.family:Config.labelFont; font.pixelSize:11; Layout.preferredWidth:90 }
                                CCPillBtn { text:"−"; onClicked:_blurPDec.running=true }
                                CCPillBtn { text:"+"; onClicked:_blurPInc.running=true }
                            }
                            Process { id:_blurPDec; command:["bash","-c","f=\"$HOME/.config/hypr/hyprviz.conf\"; v=$(grep 'passes = ' \"$f\" | grep -oP '[0-9]+'); nv=$((v > 0 ? v - 1 : 0)); sed -i \"s/passes = $v/passes = $nv/\" \"$f\" && hyprctl reload"]; running:false }
                            Process { id:_blurPInc; command:["bash","-c","f=\"$HOME/.config/hypr/hyprviz.conf\"; v=$(grep 'passes = ' \"$f\" | grep -oP '[0-9]+'); nv=$((v + 1)); sed -i \"s/passes = $v/passes = $nv/\" \"$f\" && hyprctl reload"]; running:false }

                            CCSection { text:"Gap Presets" }
                            Flow { Layout.fillWidth:true; spacing:4
                                Repeater {
                                    model:["minimal","balanced","spacious","zero"]
                                    delegate: CCPillBtn {
                                        required property string modelData
                                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                        onClicked: { _gapProc.command=["bash","-c","$HOME/.config/hyprcandy/hooks/hyprland_gap_presets.sh "+modelData]; _gapProc.running=true }
                                    }
                                }
                            }
                            Process { id:_gapProc; running:false }
                            Item { height:10 }
                        }
                    }

                    // ── TAB 2: Themes ──────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5
                            CCSection { text: "󰔎 Matugen Themes" }
                            Flow { Layout.fillWidth: true; spacing: 4
                                Repeater {
                                    model: [
                                        {name:"Fidelity",   scheme:"scheme-fidelity"},
                                        {name:"Monochrome", scheme:"scheme-monochrome"},
                                        {name:"Content",    scheme:"scheme-content"},
                                        {name:"Expressive", scheme:"scheme-expressive"},
                                        {name:"Neutral",    scheme:"scheme-neutral"},
                                        {name:"Rainbow",    scheme:"scheme-rainbow"},
                                        {name:"Tonal-spot", scheme:"scheme-tonal-spot"},
                                        {name:"Fruit",      scheme:"scheme-fruit-salad"},
                                        {name:"Vibrant",    scheme:"scheme-vibrant"}
                                    ]
                                    delegate: CCPillBtn {
                                        required property var modelData
                                        text: modelData.name
                                        onClicked: {
                                            const mode = modelData.name === "Light" ? "light" : "dark"
                                            _themeProc.command = ["bash","-c",
                                                "sed -i 's/--type scheme-[^ ]*/--type "+modelData.scheme+"/' \"$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh\" && " +
                                                "bash \"$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh\" && " +
                                                "echo '"+modelData.scheme+"' > \"$HOME/.config/hyprcandy/matugen-state\""]
                                            _themeProc.running = true
                                        }
                                    }
                                }
                            }
                            Process { id:_themeProc; running:false }
                            Item { height:10 }
                        }
                    }

                    // ── TAB 3: Dock ────────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5
                            CCSection { text: "󰞒 Dock" }
                            CCPillBtn { text:"󰶘 Cycle Position"; Layout.fillWidth:true; onClicked:_dockCycle.running=true }
                            Process { id:_dockCycle; command:["bash",Config.candyDir+"/GJS/hyprcandydock/cycle.sh"]; running:false }
                            Repeater {
                                model:[{l:"Spacing",k:"buttonSpacing"},{l:"Padding",k:"innerPadding"},{l:"Border W",k:"borderWidth"},{l:"Border R",k:"borderRadius"}]
                                delegate: CCEntryRow {
                                    required property var modelData
                                    label: modelData.l
                                    onApplied: function(val) {
                                        const n = parseInt(val)
                                        if (!isNaN(n)) {
                                            _dockWrite.command=["bash","-c","f=\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\"; sed -i 's/"+modelData.k+": [0-9]*/"+modelData.k+": "+n+"/' \"$f\" && pkill -SIGUSR2 -f 'gjs dock-main.js'"]
                                            _dockWrite.running=true
                                        }
                                    }
                                }
                            }
                            Process { id:_dockWrite; running:false }
                            CCEntryRow {
                                label:"Icon Size"
                                onApplied: function(val) {
                                    const n=parseInt(val)
                                    if (!isNaN(n)&&n>=12&&n<=64){
                                        _dockIcon.command=["bash","-c","f=\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\"; sed -i 's/appIconSize: [0-9]*/appIconSize: "+n+"/' \"$f\" && t=\"$HOME/.hyprcandy/GJS/hyprcandydock/toggle.sh\"; bash \"$t\" && sleep 1 && bash \"$t\""]
                                        _dockIcon.running=true
                                    }
                                }
                            }
                            Process { id:_dockIcon; running:false }
                            Item { height:10 }
                        }
                    }

                    // ── TAB 4: Menus ───────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5
                            CCSection { text: "󰮫 Menus (Rofi)" }
                            CCEntryRow { label:"Border px"; onApplied:function(v){const n=parseInt(v);if(!isNaN(n)){_rofiBorder.command=["bash","-c","sed -i 's/border-width: [0-9]*px/border-width: "+n+"px/' \"$HOME/.config/hyprcandy/settings/rofi-border.rasi\""]; _rofiBorder.running=true}} }
                            Process { id:_rofiBorder; running:false }
                            CCEntryRow { label:"Radius em"; onApplied:function(v){const n=parseFloat(v);if(!isNaN(n)){_rofiRadius.command=["bash","-c","sed -i 's/border-radius: [0-9.]*em/border-radius: "+n.toFixed(1)+"em/' \"$HOME/.config/hyprcandy/settings/rofi-border-radius.rasi\""]; _rofiRadius.running=true}} }
                            Process { id:_rofiRadius; running:false }
                            RowLayout { Layout.fillWidth:true; spacing:6
                                Text { text:"Icon Size"; color:Theme.cPrimary; font.family:Config.labelFont; font.pixelSize:11; Layout.preferredWidth:90 }
                                CCPillBtn { text:"−"; onClicked:_rofiIconDec.running=true }
                                CCPillBtn { text:"+"; onClicked:_rofiIconInc.running=true }
                            }
                            Process { id:_rofiIconDec; command:["bash","-c","f=\"$HOME/.config/rofi/config.rasi\"; v=$(sed -n '/element-icon/,/}/{s/.*size:[[:space:]]*\\([0-9.]*\\)em.*/\\1/p}' \"$f\"); nv=$(echo \"$v - 0.5\" | bc); [ $(echo \"$nv >= 0.5\" | bc) -eq 1 ] && sed -i \"/element-icon/,/}/{s/size:[[:space:]]*[0-9.]*em/size: ${nv}em/}\" \"$f\""]; running:false }
                            Process { id:_rofiIconInc; command:["bash","-c","f=\"$HOME/.config/rofi/config.rasi\"; v=$(sed -n '/element-icon/,/}/{s/.*size:[[:space:]]*\\([0-9.]*\\)em.*/\\1/p}' \"$f\"); nv=$(echo \"$v + 0.5\" | bc); sed -i \"/element-icon/,/}/{s/size:[[:space:]]*[0-9.]*em/size: ${nv}em/}\" \"$f\""]; running:false }
                            Item { height:10 }
                        }
                    }

                    // ── TAB 5: SDDM ────────────────────────────────────────
                    CCScrollPane {
                        property string sddmTheme: "/usr/share/sddm/themes/sugar-candy/theme.conf"
                        ColumnLayout {
                            width: parent.width; spacing: 5
                            CCSection { text: "󰍂 SDDM" }
                            CCEntryRow { label:"Header"; onApplied:function(v){_sddmHdr.command=["sudo","sed","-i","s|^HeaderText=.*|HeaderText="+v+"|","/usr/share/sddm/themes/sugar-candy/theme.conf"];_sddmHdr.running=true} }
                            Process { id:_sddmHdr; running:false }
                            CCEntryRow { label:"Form Pos"; onApplied:function(v){_sddmForm.command=["sudo","sed","-i","s|^FormPosition=.*|FormPosition="+v+"|","/usr/share/sddm/themes/sugar-candy/theme.conf"];_sddmForm.running=true} }
                            Process { id:_sddmForm; running:false }
                            CCEntryRow { label:"Blur R"; onApplied:function(v){const n=parseInt(v);if(!isNaN(n)){_sddmBlur.command=["sudo","sed","-i","s|^BlurRadius=.*|BlurRadius="+n+"|","/usr/share/sddm/themes/sugar-candy/theme.conf"];_sddmBlur.running=true}} }
                            Process { id:_sddmBlur; running:false }
                            CCPillBtn { text:"󰈈 Preview"; Layout.fillWidth:true; onClicked:_sddmPreview.running=true }
                            Process { id:_sddmPreview; command:["sddm-greeter","--test-mode","--theme","/usr/share/sddm/themes/sugar-candy"]; running:false }
                            Item { height:10 }
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Processes
    // ═══════════════════════════════════════════════════════════════════════
    Process {
        id: userNameProc
        command: ["bash", "-c", "id -un"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { if (l.trim()) userNameText.text = l.trim() }
        }
    }

    Process {
        id: userIconPicker
        command: ["bash", "-c",
            "f=$(zenity --file-selection --file-filter='Images | *.png *.jpg *.jpeg *.webp' 2>/dev/null) && " +
            "[ -n \"$f\" ] && " +
            "magick \"$f\" -resize 96x96^ -gravity center -extent 96x96 " +
            "  \\( +clone -alpha extract -fill black -colorize 100 " +
            "     -fill white -draw 'circle 48,48 48,0' \\) " +
            "  -alpha off -compose CopyOpacity -composite -strip " +
            "  \"$HOME/.config/hyprcandy/user-icon.png\" && " +
            "pkill -SIGUSR1 qs 2>/dev/null; true"]
        running: false
        onExited: {
            // Force image reload by toggling source
            userImg.source = ""
            userImg.source = "file://" + Config.home + "/.config/hyprcandy/user-icon.png?" + Date.now()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Reusable components — styled to match startmenu SliderBg
    // ═══════════════════════════════════════════════════════════════════════

    // ── Scrollable pane ─────────────────────────────────────────────────────
    component CCScrollPane: Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: _scrollContent.implicitHeight + 16
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: 4; radius: 2
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
            }
        }
        default property alias scrollContent: _scrollContent.data
        ColumnLayout {
            id: _scrollContent
            width: parent.width - 8
            anchors { left: parent.left; leftMargin: 4; top: parent.top; topMargin: 8 }
            spacing: 0
        }
    }

    // ── Section heading ──────────────────────────────────────────────────────
    component CCSection: RowLayout {
        property alias text: _sh.text
        Layout.fillWidth: true
        Layout.topMargin: 10
        Layout.bottomMargin: 3
        Text {
            id: _sh
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: 11
            font.weight: Font.Bold
            font.letterSpacing: 0.5
        }
        Rectangle {
            Layout.fillWidth: true; height: 1
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
        }
    }

    // ── Slider — matches startmenu SliderBg exactly ──────────────────────────
    //   Trough: 14px tall, rounded, border outline
    //   Fill:   inversePrimary→onPrimary gradient (horizontal)
    //   Thumb:  󰟃 dot-circle glyph, clamped to trough
    component CCSlider: RowLayout {
        id: _ccsl
        property alias label: _lbl.text
        property real  from:      0
        property real  to:        1
        property real  stepSize:  1
        property real  value:     0
        property int   decimals:  0
        signal moved(real v)

        Layout.fillWidth: true
        spacing: 6

        Text {
            id: _lbl
            Layout.preferredWidth: 96
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 11
            elide: Text.ElideRight
        }

        // Trough item
        Item {
            id: _trough
            Layout.fillWidth: true
            height: 20

            readonly property int tH: 14
            readonly property int pad: 3
            readonly property int iH: tH - pad * 2
            readonly property real norm: _ccsl.to > _ccsl.from
                ? Math.max(0, Math.min(1, (_ccsl.value - _ccsl.from) / (_ccsl.to - _ccsl.from)))
                : 0

            Item {
                y: (_trough.height - _trough.tH) / 2
                width: parent.width; height: _trough.tH

                // Trough bg
                Rectangle {
                    anchors.fill: parent; radius: _trough.tH / 2
                    color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                }

                // Gradient fill — clip to filled portion
                Item {
                    x: _trough.pad; y: _trough.pad
                    width:  Math.max(0, (parent.width - _trough.pad * 2) * _trough.norm)
                    height: _trough.iH
                    clip: true
                    Rectangle {
                        width:  parent.parent.width - _trough.pad * 2
                        height: _trough.iH
                        radius: _trough.iH / 2
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position: 0.0; color: Theme.cInversePrimary }
                            GradientStop { position: 1.0; color: Theme.cOnPrimary }
                        }
                    }
                }

                // Dot-glyph thumb (󰟃)
                Text {
                    text: "󰟃"
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: _trough.iH + 2
                    color: Theme.cPrimary
                    style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.25)
                    x: {
                        const tw = parent.width - _trough.pad * 2
                        const cx = _trough.pad + tw * _trough.norm - implicitWidth / 2
                        return Math.max(_trough.pad - implicitWidth/2 + 1,
                               Math.min(parent.width - _trough.pad - implicitWidth/2 - 1, cx))
                    }
                    y: (_trough.tH - implicitHeight) / 2
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                preventStealing: true
                function _calc(mx) {
                    const n = Math.max(0, Math.min(1, mx / width))
                    const raw = _ccsl.from + n * (_ccsl.to - _ccsl.from)
                    const stepped = _ccsl.stepSize > 0
                        ? Math.round(raw / _ccsl.stepSize) * _ccsl.stepSize : raw
                    return Math.max(_ccsl.from, Math.min(_ccsl.to, stepped))
                }
                onPressed:         function(m) { const v=_calc(m.x); _ccsl.value=v; _ccsl.moved(v) }
                onPositionChanged: function(m) { if(pressed){const v=_calc(m.x); _ccsl.value=v; _ccsl.moved(v)} }
                onWheel:           function(e) {
                    const dir = e.angleDelta.y > 0 ? 1 : -1
                    const step = _ccsl.stepSize > 0 ? _ccsl.stepSize : (_ccsl.to - _ccsl.from) * 0.02
                    const v = Math.max(_ccsl.from, Math.min(_ccsl.to, _ccsl.value + step * dir))
                    _ccsl.value = v; _ccsl.moved(v)
                }
            }
        }

        Text {
            Layout.preferredWidth: 38
            text: _ccsl.decimals > 0
                ? _ccsl.value.toFixed(_ccsl.decimals)
                : Math.round(_ccsl.value).toString()
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 10
            horizontalAlignment: Text.AlignRight
        }
    }

    // ── Toggle ──────────────────────────────────────────────────────────────
    component CCToggle: RowLayout {
        property alias label: _tl.text
        property bool  value: false
        signal toggled(bool v)

        Layout.fillWidth: true; spacing: 6

        Text {
            id: _tl
            Layout.preferredWidth: 110
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 11
            elide: Text.ElideRight
        }

        Item { Layout.fillWidth: true }

        // iOS-style pill toggle
        Rectangle {
            id: _pill
            width: 44; height: 24; radius: 12
            color: value
                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.9)
                : Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.35)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                  Theme.cPrimary.b, value ? 0.6 : 0.2)

            Rectangle {
                id: _thumb
                width: 18; height: 18; radius: 9
                color: value ? Theme.cPrimary : Theme.cOnSurfVar
                anchors.verticalCenter: parent.verticalCenter
                x: value ? parent.width - width - 3 : 3
                Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            MouseArea {
                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                onClicked: { value = !value; toggled(value) }
            }
            Behavior on color { ColorAnimation { duration: 150 } }
        }
    }

    // ── Segmented control ───────────────────────────────────────────────────
    component CCSegmented: RowLayout {
        property alias label: _sgl.text
        property var   options: []
        property string current: ""
        signal picked(string v)

        Layout.fillWidth: true; spacing: 6

        Text {
            id: _sgl
            Layout.preferredWidth: 96
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 11
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.fillWidth: true; height: 26; radius: 8
            color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                           Theme.cInversePrimary.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                  Theme.cPrimary.b, 0.2)

            Row {
                anchors.fill: parent; anchors.margins: 2; spacing: 2
                Repeater {
                    model: options
                    delegate: Rectangle {
                        required property string modelData
                        width: (parent.width - (options.length - 1) * 2) / options.length
                        height: parent.height; radius: 6
                        color: current === modelData
                            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                      Theme.cInversePrimary.b, 0.8)
                            : "transparent"
                        border.width: current === modelData ? 1 : 0
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                              Theme.cPrimary.b, 0.45)

                        Text {
                            anchors.centerIn: parent
                            text: modelData; color: Theme.cPrimary
                            font.family: Config.labelFont; font.pixelSize: 10
                            font.weight: current === modelData ? Font.Medium : Font.Normal
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: picked(modelData)
                        }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }
        }
    }

    // ── Pill button ──────────────────────────────────────────────────────────
    component CCPillBtn: Rectangle {
        id: _pb
        property alias text: _pbt.text
        property bool  active: false
        signal clicked()

        implicitWidth: _pbt.implicitWidth + 20
        implicitHeight: 28; radius: 8
        color: active
            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                      Theme.cInversePrimary.b, 0.8)
            : (pbma.containsMouse
                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.35)
                : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.18))
        border.width: 1
        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                              Theme.cPrimary.b, active ? 0.55 : 0.2)

        Text {
            id: _pbt; anchors.centerIn: parent
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 10
        }
        MouseArea {
            id: pbma; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: _pb.clicked()
        }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // ── Icon / glyph text entry ──────────────────────────────────────────────
    component CCIconEntry: RowLayout {
        property alias label: _iel.text
        property string value: ""
        signal applied(string v)

        Layout.fillWidth: true; spacing: 6

        Text {
            id: _iel
            Layout.preferredWidth: 96
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 11
            elide: Text.ElideRight
        }
        // Preview glyph
        Text {
            text: value !== "" ? value : "—"
            font.family: Config.fontFamily; font.pixelSize: 16
            color: Theme.cPrimary; Layout.preferredWidth: 22
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            Layout.fillWidth: true; height: 26; radius: 6
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
            TextInput {
                anchors { fill: parent; margins: 5 }
                text: value; color: Theme.cPrimary
                font.family: Config.labelFont; font.pixelSize: 11
                verticalAlignment: TextInput.AlignVCenter; clip: true
                onAccepted: applied(text)
                onEditingFinished: applied(text)
            }
        }
    }

    // ── Text entry row ───────────────────────────────────────────────────────
    component CCEntryRow: RowLayout {
        property alias label: _erl.text
        signal applied(string val)

        Layout.fillWidth: true; spacing: 6

        Text {
            id: _erl
            Layout.preferredWidth: 96
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 11
            elide: Text.ElideRight
        }
        Rectangle {
            Layout.fillWidth: true; height: 26; radius: 6
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
            TextInput {
                anchors { fill: parent; margins: 5 }
                color: Theme.cPrimary
                font.family: Config.labelFont; font.pixelSize: 11
                verticalAlignment: TextInput.AlignVCenter; clip: true
                onAccepted: applied(text)
            }
        }
    }

    // ── Color picker (matugen palette swatch row) ────────────────────────────
    component CCColorPicker: ColumnLayout {
        property alias label: _cpl.text
        property color currentColor: Theme.cPrimary
        property bool  enabled: true

        Layout.fillWidth: true; spacing: 3
        opacity: enabled ? 1.0 : 0.4

        RowLayout {
            Layout.fillWidth: true
            Text {
                id: _cpl; Layout.preferredWidth: 96
                color: Theme.cPrimary
                font.family: Config.labelFont; font.pixelSize: 11
            }
            Rectangle {
                width: 22; height: 14; radius: 4
                color: currentColor
                border.width: 1
                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                      Theme.cPrimary.b, 0.4)
            }
            Text {
                text: currentColor.toString().toUpperCase()
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                               Theme.cPrimary.b, 0.6)
                font.family: Config.labelFont; font.pixelSize: 9
            }
        }

        // Matugen palette swatches
        Flow {
            Layout.fillWidth: true; spacing: 4
            Repeater {
                model: [
                    Theme.cPrimary, Theme.cInversePrimary, Theme.cPrimaryContainer,
                    Theme.cSecondary, Theme.cTertiary, Theme.cTertiaryContainer,
                    Theme.cOnPrimary, Theme.cOnSecondary, Theme.cOnSurf,
                    Theme.cSurfLow, Theme.cSurfMid, Theme.cSurfHi,
                    Theme.cErr, Theme.cOutVar, Theme.cScrim
                ]
                delegate: Rectangle {
                    required property color modelData
                    width: 20; height: 20; radius: 4
                    color: modelData
                    border.width: currentColor.toString() === modelData.toString() ? 2 : 0
                    border.color: Theme.cPrimary
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: if (parent.parent.parent.parent.enabled) currentColor = modelData
                    }
                }
            }
        }
    }
}
