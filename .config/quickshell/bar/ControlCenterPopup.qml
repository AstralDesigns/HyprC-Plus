pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  Control Center — hyprcandy quickshell edition.
//
//  Layout:
//    • Anchored like startmenu/notifications — same gap from bar edge,
//      horizontally centered, tracks top/bottom bar position.
//    • Left sidebar (vertical nav) → Right content pane
//    • Sidebar: user icon (click → wallpaper picker) + tab buttons
//    • Content: Bar sub-tabs + Hyprland / Themes / Dock / Menus / SDDM
//
//  Slider style matches startmenu SliderBg exactly:
//    trough = 14 px tall, innerH = 8 px, gradient fill (inversePrimary→onPrimary), dot-glyph thumb.
//
//  Wallpaper picker:
//    • Clicking the user icon circle opens a wallpaper-picker-like overlay
//      rendered ABOVE the control center (higher layer order).
//    • Right-clicking a wallpaper thumbnail shows a small tray-style popover
//      with "Set as user icon" option (converts via imagemagick).
//
//  Layer: Top layer, explicit width/height so the surface only wraps the popup
//         (no full-screen stretch → blur only around the panel, not full-width).
// ═══════════════════════════════════════════════════════════════════════════
PanelWindow {
    id: ccWin

    // ── Weather location state ────────────────────────────────────────────────
    readonly property string _weatherLocFile: Quickshell.env("HOME") + "/.config/hyprcandy/weather-location.conf"
    property string _weatherPinnedName: ""   // display name of pinned location
    property bool   _weatherPinned:     false
    property double _weatherPinnedLat:  0.0
    property double _weatherPinnedLon:  0.0

    // ── Bar state (read from qs_bar_state.json, same as startmenu) ───────
    property bool   _barAtBottom: Config.barPosition === "bottom"
    property real   _barGap:      Config.outerMarginTop + Config.barHeight + 6
    property real   _barGapBot:   Config.outerMarginBottom + Config.barHeight + 6
    property real   _sideMargin:  Config.outerMarginSide

    // ── Scripts directory
    readonly property string scriptDir: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts"

    // ── Dock current values (read from config.js on open) ─────────────────
    property string _dockSpacingVal:    "0"
    property string _dockPaddingVal:    "0"
    property string _dockBorderWVal:    "2"
    property string _dockBorderRVal:    "20"
    property string _dockIconSizeVal:   "24"
    property string _dockStartIconVal:  ""

    // ── Rofi current values ───────────────────────────────────────────────
    property string _rofiBorderVal:  "2"
    property string _rofiRadiusVal:  "1.0"

    // ── SDDM current values ───────────────────────────────────────────────
    property string _sddmHeaderVal:  "󰫣󰫣󰫣"
    property string _sddmFormVal:    "center"
    property string _sddmBlurVal:    "55"

    // ── Hyprland entry values ─────────────────────────────────────────────
    property string _opacEntryVal:       ""
    property string _blurSizeEntryVal:   ""
    property string _blurPassesEntryVal: ""
    property string _gapsInnerEntryVal:  ""
    property string _gapsOuterEntryVal:  ""
    property string _borderWEntryVal:    ""
    property string _borderREntryVal:    ""

    // Load dock + rofi + sddm + hyprland values when CC opens
    Connections {
        target: ControlCenterState
        function onVisibleChanged() {
            if (ControlCenterState.visible) {
                _dockValReader.running = true
                _rofiValReader.running = true
                _sddmValReader.running = true
                _weatherLocReader.running = true
                _hyprlandValReader.running = true
            }
        }
    }

    // Read hyprland config values
    Process {
        id: _hyprlandValReader
        // Use grep -A 25 for blur so the block lookup doesn't depend on ^} matching indented braces.
        command: ["bash", "-c",
            'f="$HOME/.config/hypr/hyprviz.conf"; ' +
            'grep "active_opacity = " "$f" 2>/dev/null | head -1 | grep -oP "[0-9.]+"; ' +
            'grep -A 25 "blur {" "$f" 2>/dev/null | grep "size = " | head -1 | grep -oP "[0-9]+"; ' +
            'grep -A 25 "blur {" "$f" 2>/dev/null | grep "passes = " | head -1 | grep -oP "[0-9]+"; ' +
            'grep "gaps_in = " "$f" 2>/dev/null | head -1 | grep -oP "[0-9]+"; ' +
            'grep "gaps_out = " "$f" 2>/dev/null | head -1 | grep -oP "[0-9]+"; ' +
            'grep "border_size = " "$f" 2>/dev/null | head -1 | grep -oP "[0-9]+"; ' +
            'grep "rounding = " "$f" 2>/dev/null | head -1 | grep -oP "[0-9]+"']
        running: false
        property string _output: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _hyprlandValReader._output += l.trim() + "\n" }
        }
        onExited: {
            const lines = _output.trim().split("\n")
            _output = ""
            // Force-set both the backing property AND the TextInput text so stale
            // QML bindings (broken by prior user edits) are always refreshed.
            if (lines[0] && lines[0].length > 0) { _opacEntryVal      = lines[0]; _opacTI.text      = lines[0] }
            if (lines[1] && lines[1].length > 0) { _blurSizeEntryVal  = lines[1]; _blurSizeTI.text  = lines[1] }
            if (lines[2] && lines[2].length > 0) { _blurPassesEntryVal= lines[2]; _blurPassesTI.text= lines[2] }
            if (lines.length > 3) { _gapsInnerEntryVal = lines[3] || "0"; _gapsInnerTI.text  = _gapsInnerEntryVal }
            if (lines.length > 4) { _gapsOuterEntryVal = lines[4] || "0"; _gapsOuterTI.text  = _gapsOuterEntryVal }
            if (lines.length > 5) { _borderWEntryVal   = lines[5] || "0"; _borderWTI.text    = _borderWEntryVal }
            if (lines.length > 6) { _borderREntryVal   = lines[6] || "0"; _borderRTI.text    = _borderREntryVal }
        }
    }
    Process {
        id: _dockValReader
        command: ["bash", "-c",
            "f=\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\"; " +
            "[ -f \"$f\" ] || exit 0; " +
            "grep -oP 'buttonSpacing:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP 'innerPadding:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP 'borderWidth:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP 'borderRadius:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP 'appIconSize:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP \"startIcon:\\s*'\\K[^']+\" \"$f\" | head -1"]
        running: false
        property var _lines: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _dockValReader._lines.push(l.trim()) }
        }
        onExited: {
            const ls = _lines
            _lines = []
            _dockSpacingVal   = (ls[0] !== undefined && ls[0]) ? ls[0] : "0"
            _dockPaddingVal   = (ls[1] !== undefined && ls[1]) ? ls[1] : "0"
            _dockBorderWVal   = (ls[2] !== undefined && ls[2]) ? ls[2] : "2"
            _dockBorderRVal   = (ls[3] !== undefined && ls[3]) ? ls[3] : "20"
            _dockIconSizeVal  = (ls[4] !== undefined && ls[4]) ? ls[4] : "24"
            _dockStartIconVal = (ls[5] !== undefined && ls[5]) ? ls[5] : ""
        }
    }
    Process {
        id: _rofiValReader
        command: ["bash", "-c",
            "f=\"$HOME/.config/hyprcandy/settings/rofi-border.rasi\"; " +
            "[ -f \"$f\" ] && grep -oP 'border-width: \\K[0-9]+' \"$f\" | head -1 || echo ''; " +
            "f=\"$HOME/.config/hyprcandy/settings/rofi-border-radius.rasi\"; " +
            "[ -f \"$f\" ] && grep -oP 'border-radius: \\K[0-9.]+' \"$f\" | head -1 || echo ''"]
        running: false
        property var _lines: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _rofiValReader._lines.push(l.trim()) }
        }
        onExited: {
            const ls = _lines; _lines = []
            _rofiBorderVal = (ls[0] !== undefined && ls[0]) ? ls[0] : "2"
            _rofiRadiusVal = (ls[1] !== undefined && ls[1]) ? ls[1] : "1.0"
        }
    }
    Process {
        id: _sddmValReader
        command: ["bash", "-c",
            "sd=\"$HOME/.config/hyprcandy\"; " +
            "[ -f \"$sd/sddm_header.state\" ] && cat \"$sd/sddm_header.state\" || " +
            "  sudo grep -oP '^HeaderText=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | head -1; " +
            "[ -f \"$sd/sddm_form.state\" ] && cat \"$sd/sddm_form.state\" || " +
            "  sudo grep -oP '^FormPosition=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | head -1; " +
            "[ -f \"$sd/sddm_blur.state\" ] && cat \"$sd/sddm_blur.state\" || " +
            "  sudo grep -oP '^BlurRadius=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | head -1"]
        running: false
        property var _lines: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _sddmValReader._lines.push(l.trim()) }
        }
        onExited: {
            const ls = _lines; _lines = []
            _sddmHeaderVal = (ls[0] !== undefined && ls[0]) ? ls[0] : ""
            _sddmFormVal   = (ls[1] !== undefined && ls[1]) ? ls[1] : "center"
            _sddmBlurVal   = (ls[2] !== undefined && ls[2]) ? ls[2] : "75"
        }
    }

    // ── Weather location reader ───────────────────────────────────────────────
    Process {
        id: _weatherLocReader
        command: ["bash", "-c",
            'f="$HOME/.config/hyprcandy/weather-location.conf"; ' +
            '[ -f "$f" ] && source "$f" 2>/dev/null && echo "PINNED:${NAME:-Pinned}" || echo "UNPINNED"'
        ]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const t = l.trim()
                if (t.startsWith("PINNED:")) {
                    ccWin._weatherPinned = true
                    ccWin._weatherPinnedName = t.slice(7)
                } else {
                    ccWin._weatherPinned = false
                    ccWin._weatherPinnedName = ""
                }
            }
        }
        onExited: running = false
    }
    // Geocoding search process — queries Open-Meteo geocoding API
    Process {
        id: _weatherGeoProc
        property string _query: ""
        command: ["bash", "-c",
            'Q=$(python3 -c "import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1]))" "' +
            _weatherGeoProc._query.replace(/'/g, "") + '" 2>/dev/null || ' +
            'echo "' + _weatherGeoProc._query.replace(/[^a-zA-Z0-9 ]/g, "").replace(/ /g, "+") + '"); ' +
            'curl -sf --max-time 6 ' +
            '"https://geocoding-api.open-meteo.com/v1/search?name=${Q}&count=5&language=en&format=json" ' +
            '2>/dev/null || echo "{}"'
        ]
        running: false
        property string _buf: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _weatherGeoProc._buf += l }
        }
        onRunningChanged: if (running) _buf = ""
        onExited: {
            try {
                const d = JSON.parse(_weatherGeoProc._buf)
                ccWin._weatherGeoResults = d.results || []
            } catch(e) {
                ccWin._weatherGeoResults = []
            }
            ccWin._weatherGeoSearching = false
        }
    }
    // Save process — writes conf file and busts weather cache
    Process {
        id: _weatherLocSave
        running: false
        onExited: {
            running = false
            _weatherCacheBust.running = true
            _weatherLocReader.running = true
        }
    }
    Process {
        id: _weatherCacheBust
        command: ["bash", "-c", "rm -f /tmp/astal-weather-cache.json"]
        running: false
        onExited: running = false
    }

    // Geocoding results and search state (bound by the CC widget below)
    property var    _weatherGeoResults:  []
    property bool   _weatherGeoSearching: false

    // ── Panel sizing — explicit width/height so the layer surface only
    //    surrounds the popup (no full-screen stretch = no full-width blur).
    //    The width is clamped between 620 and 940 px; height fills most of the
    //    available vertical space minus the bar gap.
    property real _screenH: screen ? screen.height : 900
    property real _panelW:  Math.min(1060, Math.max(700, (screen ? screen.width : 1920) * 0.62))
    property real _activeGap: _barAtBottom ? _barGapBot : _barGap
    property real _panelH:  Math.min(_screenH - _activeGap - 24,
                                     Math.max(500, _screenH * 0.78))

    // Anchor to bar edge (top or bottom) and center horizontally.
    // We no longer anchor left+right so the layer surface only wraps the popup.
    anchors {
        top:    !_barAtBottom
        bottom:  _barAtBottom
    }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }
    implicitWidth:  _panelW
    implicitHeight: _panelH

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-controlcenter"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    color: "transparent"
    visible: ControlCenterState.visible

    // ── Dismiss on focus change ──────────────────────────────────────────────
    // When the user clicks into a real app window, close the control center.
    // This mirrors the startmenu's dismiss-on-focus pattern.
    Connections {
        target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                ControlCenterState.close()
        }
    }

    // ── Settings persistence for tab and weather location ───────────────────
    Settings {
        id: ccTabSettings
        category: "cc-tabs-v1"
        property int activeTab: 1  // Default to Hyprland tab (index 1)
    }
    Settings {
        id: ccLocSettings
        category: "cc-weather-loc-v1"
        property string pinnedName: ""
        property double pinnedLat: 0.0
        property double pinnedLon: 0.0
    }

    // ── The panel itself ───────────────────────────────────────────────────
    Rectangle {
        id: panel
        // Fill the PanelWindow (which is now explicitly sized to wrap the popup)
        anchors.fill: parent

        radius: 20
        color:  Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                        Theme.cOnSecondary.b, 0.6)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g,
                              Theme.cOutVar.b, 0.38)
        clip: false

        // Scale-in animation from bar direction
        scale: ControlCenterState.visible ? 1.0 : 0.94
        transformOrigin: _barAtBottom ? Item.Bottom : Item.Top
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        opacity: ControlCenterState.visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 140 } }

        Keys.onEscapePressed: ControlCenterState.close()
        focus: true

        Component.onCompleted: {
            // Initialize weather pinned location from settings
            if (ccLocSettings.pinnedName) {
                ccWin._weatherPinned = true
                ccWin._weatherPinnedName = ccLocSettings.pinnedName
                ccWin._weatherPinnedLat = ccLocSettings.pinnedLat
                ccWin._weatherPinnedLon = ccLocSettings.pinnedLon
            }
        }

        Connections {
            target: ControlCenterState
            function onVisibleChanged() {
                if (ControlCenterState.visible) panel.forceActiveFocus()
            }
        }

        // ── Clip wrapper — keeps children inside the panel's rounded corners ──
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            clip: true
            color: "transparent"

        // Sidebar and content pane are absolutely-positioned siblings with
        // no shared edge — eliminates all sub-pixel bleed at the boundary.
        Item {
            anchors.fill: parent

            // ═══════════════════════════════════════════════════════════════
            //  LEFT SIDEBAR — standalone rounded rect, left-anchored
            // ═══════════════════════════════════════════════════════════════
            Item {
                id: sidebar
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: 190

                // Full sidebar background — panel.radius rounds all four
                // corners; the clip wrapper above trims the right two.
                Rectangle {
                    anchors.fill: parent
                    radius: panel.radius
                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                                   Theme.cOnSecondary.b, 0.55)
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 14 }
                    spacing: 5

                    // ── User info card ─────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 110
                        radius: 16
                        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                       Theme.cInversePrimary.b, 0.14)
                        border.width: 1
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                              Theme.cPrimary.b, 0.18)

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            // User icon circle — click opens wallpaper picker overlay
                            Rectangle {
                                id: userIconCircle
                                Layout.alignment: Qt.AlignHCenter
                                width: 58; height: 58; radius: 29
                                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                               Theme.cInversePrimary.b, 0.32)
                                border.width: 2
                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                      Theme.cPrimary.b, 0.55)
                                clip: true

                                Image {
                                    id: userImg
                                    anchors.fill: parent
                                    source: "file://" + Quickshell.env("HOME") + "/.config/hyprcandy/user-icon.png"
                                    fillMode: Image.PreserveAspectCrop
                                    smooth: true
                                    mipmap: true
                                    visible: status === Image.Ready
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: userImg.status !== Image.Ready
                                    text: "󰀄"
                                    font.family: Config.fontFamily
                                    font.pixelSize: 28
                                    color: Theme.cPrimary
                                }

                                // Hover edit overlay
                                Rectangle {
                                    anchors.fill: parent; radius: parent.radius
                                    color: Qt.rgba(0, 0, 0, 0.38)
                                    visible: iconHoverArea.containsMouse
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰄀"
                                        font.family: Config.fontFamily
                                        font.pixelSize: 18
                                        color: "white"
                                    }
                                }
                                MouseArea {
                                    id: iconHoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: wpPickerOverlay.open()
                                }
                            }

                            Text {
                                id: userNameText
                                Layout.alignment: Qt.AlignHCenter
                                text: "—"
                                color: Theme.cPrimary
                                font.family: Config.labelFont
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // ── Nav buttons ───────────────────────────────────────
                    Repeater {
                        model: [
                            { icon: "", label: "Hyprland",  idx: 1 },
                            { icon: "󱟛", label: "Bar",       idx: 0 },
                            { icon: "󰔎", label: "Themes",    idx: 2 },
                            { icon: "󰞒", label: "Dock",      idx: 3 },
                            { icon: "󰮫", label: "Menus",     idx: 4 },
                            { icon: "󰍂", label: "SDDM",      idx: 5 }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            // ComponentBehavior: Bound — capture outer id as required property
                            property int _stackIdx: mainStack.currentIndex
                            Layout.fillWidth: true
                            height: 38; radius: 11
                            color: _stackIdx === modelData.idx
                                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                          Theme.cInversePrimary.b, 0.62)
                                : (navHover.containsMouse
                                    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                              Theme.cInversePrimary.b, 0.22)
                                    : "transparent")
                            border.width: _stackIdx === modelData.idx ? 1 : 0
                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                  Theme.cPrimary.b, 0.38)

                            Row {
                                anchors { left: parent.left; verticalCenter: parent.verticalCenter
                                          leftMargin: 14 }
                                spacing: 10
                                Text {
                                    text: modelData.icon
                                    font.family: Config.fontFamily; font.pixelSize: 15
                                    color: Theme.cPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.label
                                    font.family: Config.labelFont; font.pixelSize: 13
                                    font.weight: (modelData && _stackIdx === modelData.idx) ? 600 : 400
                                    color: Theme.cPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            // Active indicator pill on right
                            Rectangle {
                                anchors { right: parent.right; rightMargin: 4
                                          verticalCenter: parent.verticalCenter }
                                width: 3; height: 20; radius: 2
                                color: Theme.cPrimary
                                visible: parent._stackIdx === modelData.idx
                            }

                            MouseArea {
                                id: navHover
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: {
                                    mainStack.currentIndex = modelData.idx
                                    barSubStack.currentIndex = 0
                                    ccTabSettings.activeTab = modelData.idx
                                }
                            }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    // Version / close row
                    RowLayout {
                        Layout.fillWidth: true
                        Text {
                            text: "hyprcandy"
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                           Theme.cPrimary.b, 0.35)
                            font.family: Config.labelFont; font.pixelSize: 10
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: 26; height: 26; radius: 13
                            color: closeHov.containsMouse
                                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                          Theme.cPrimary.b, 0.15)
                                : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                          Theme.cPrimary.b, 0.06)
                            Text {
                                anchors.centerIn: parent; text: "󰅙"
                                font.family: Config.fontFamily; font.pixelSize: 14
                                color: Theme.cPrimary
                            }
                            MouseArea {
                                id: closeHov; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: ControlCenterState.close()
                            }
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                    }
                }
            }

            // ═══════════════════════════════════════════════════════════════
            //  RIGHT CONTENT PANE — own rounded rect, no shared edge with sidebar
            // ═══════════════════════════════════════════════════════════════
            Rectangle {
                anchors {
                    left: sidebar.right; right: parent.right
                    top: parent.top;     bottom: parent.bottom
                }
                radius: 20
                color: "transparent"
                clip: true

                StackLayout {
                    id: mainStack
                    anchors.fill: parent
                    currentIndex: ccTabSettings.activeTab

                    // ── TAB 0: Bar ──────────────────────────────────────────
                    Item {
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
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
                                        property int _subIdx: barSubStack.currentIndex
                                        height: 30
                                        implicitWidth: _stLabel.implicitWidth + 18
                                        radius: 9
                                        color: _subIdx === index
                                            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                      Theme.cInversePrimary.b, 0.72)
                                            : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                      Theme.cInversePrimary.b, 0.16)
                                        border.width: _subIdx === index ? 1 : 0
                                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.42)
                                        Text {
                                            id: _stLabel; anchors.centerIn: parent
                                            text: modelData; color: Theme.cPrimary
                                            font.family: Config.labelFont; font.pixelSize: 12
                                            font.weight: (index !== undefined && _subIdx === index) ? 600 : 400
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: barSubStack.currentIndex = index
                                        }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }
                            }

                            // Separator
                            Rectangle {
                                Layout.fillWidth: true; height: 1
                                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.22)
                            }

                            // Bar sub-tab content
                            StackLayout {
                                id: barSubStack
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndex: 0

                                // ── General ────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Weather Location" }

                                        // Current location status row
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Text {
                                                text: ccWin._weatherPinned
                                                    ? ("󰍎 " + ccWin._weatherPinnedName)
                                                    : "󰇢 Auto (IP geolocation)"
                                                color: ccWin._weatherPinned
                                                    ? Theme.cPrimary
                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.5)
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                font.weight: ccWin._weatherPinned ? Font.Medium : Font.Normal
                                                Layout.fillWidth: true; elide: Text.ElideRight
                                            }
                                            Rectangle {
                                                visible: ccWin._weatherPinned
                                                height: 22; radius: 6
                                                implicitWidth: _clrLbl.implicitWidth + 14
                                                color: _clrHov.containsMouse
                                                    ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.22)
                                                    : Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.10)
                                                border.width: 1
                                                border.color: Qt.rgba(Theme.cErr.r, Theme.cErr.g,
                                                                       Theme.cErr.b, 0.45)
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Text {
                                                    id: _clrLbl; anchors.centerIn: parent
                                                    text: "Clear"; color: Theme.cErr
                                                    font.family: Config.labelFont; font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    id: _clrHov; anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        _weatherLocSave.command = ["bash", "-c",
                                                            'rm -f "$HOME/.config/hyprcandy/weather-location.conf"']
                                                        _weatherLocSave.running = true
                                                        ccWin._weatherPinned = false
                                                        ccWin._weatherPinnedName = ""
                                                        ccWin._weatherPinnedLat = 0.0
                                                        ccWin._weatherPinnedLon = 0.0
                                                        // Clear settings
                                                        ccLocSettings.pinnedName = ""
                                                        ccLocSettings.pinnedLat = 0.0
                                                        ccLocSettings.pinnedLon = 0.0
                                                    }
                                                }
                                            }
                                        }

                                        // Search row
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6
                                            Rectangle {
                                                Layout.fillWidth: true; height: 28; radius: 7
                                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                               Theme.cPrimary.b, 0.06)
                                                border.width: 1
                                                border.color: _wLocInput.activeFocus
                                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.55)
                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.2)
                                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                                TextInput {
                                                    id: _wLocInput
                                                    anchors { fill: parent; margins: 6 }
                                                    color: Theme.cPrimary
                                                    font.family: Config.labelFont; font.pixelSize: 12
                                                    verticalAlignment: TextInput.AlignVCenter; clip: true
                                                    // placeholderText only available in Qt 5.12+; using overlay text instead
                                                    Keys.onReturnPressed: {
                                                        const q = text.trim()
                                                        if (q.length < 2) return
                                                        ccWin._weatherGeoResults  = []
                                                        ccWin._weatherGeoSearching = true
                                                        _weatherGeoProc._query = q
                                                        _weatherGeoProc.running = true
                                                    }
                                                }
                                                // Placeholder label
                                                Text {
                                                    anchors { fill: parent; leftMargin: 7 }
                                                    verticalAlignment: Text.AlignVCenter
                                                    visible: _wLocInput.text === "" && !_wLocInput.activeFocus
                                                    text: "Search city or district…"
                                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                   Theme.cPrimary.b, 0.35)
                                                    font.family: Config.labelFont; font.pixelSize: 12
                                                }
                                            }
                                            // Search button
                                            Rectangle {
                                                width: 28; height: 28; radius: 7
                                                color: _wSrchHov.containsMouse
                                                    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                              Theme.cInversePrimary.b, 0.38)
                                                    : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                              Theme.cInversePrimary.b, 0.16)
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: ccWin._weatherGeoSearching ? "󰑪" : "󰍉"
                                                    font.family: Config.fontFamily; font.pixelSize: 14
                                                    color: Theme.cPrimary
                                                    RotationAnimator on rotation {
                                                        from: 0; to: 360; duration: 900
                                                        loops: Animation.Infinite
                                                        running: ccWin._weatherGeoSearching
                                                    }
                                                }
                                                MouseArea {
                                                    id: _wSrchHov; anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const q = _wLocInput.text.trim()
                                                        if (q.length < 2) return
                                                        ccWin._weatherGeoResults  = []
                                                        ccWin._weatherGeoSearching = true
                                                        _weatherGeoProc._query = q
                                                        _weatherGeoProc.running = true
                                                    }
                                                }
                                            }
                                        }

                                        // Search results list
                                        Repeater {
                                            model: ccWin._weatherGeoResults
                                            delegate: Rectangle {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true; height: 38; radius: 8
                                                color: _resHov.containsMouse
                                                    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                              Theme.cInversePrimary.b, 0.28)
                                                    : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                              Theme.cInversePrimary.b, 0.10)
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                ColumnLayout {
                                                    anchors { fill: parent; leftMargin: 10; rightMargin: 8
                                                              topMargin: 4; bottomMargin: 4 }
                                                    spacing: 1
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.name || ""
                                                        color: Theme.cPrimary
                                                        font.family: Config.labelFont; font.pixelSize: 12
                                                        font.weight: Font.Medium; elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: [modelData.admin1, modelData.admin2,
                                                               modelData.country].filter(Boolean).join(", ")
                                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                       Theme.cPrimary.b, 0.55)
                                                        font.family: Config.labelFont; font.pixelSize: 10
                                                        elide: Text.ElideRight
                                                    }
                                                }
                                                MouseArea {
                                                    id: _resHov; anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const r    = modelData
                                                        const lat  = (r.latitude  || 0).toFixed(4)
                                                        const lon  = (r.longitude || 0).toFixed(4)
                                                        const name = (r.name || "Location").replace(/'/g, "")
                                                            + (r.admin1 ? ", " + r.admin1.replace(/'/g, "") : "")
                                                        const content =
                                                            "LAT=" + lat + "\n" +
                                                            "LON=" + lon + "\n" +
                                                            "NAME='" + name + "'\n"
                                                        _weatherLocSave.command = ["bash", "-c",
                                                            'mkdir -p "$HOME/.config/hyprcandy" && ' +
                                                            "printf '%s' '" + content + "' > " +
                                                            '"$HOME/.config/hyprcandy/weather-location.conf"']
                                                        _weatherLocSave.running = true
                                                        // Save to settings for persistence across CC launches
                                                        ccLocSettings.pinnedName = name
                                                        ccLocSettings.pinnedLat = parseFloat(lat)
                                                        ccLocSettings.pinnedLon = parseFloat(lon)
                                                        ccWin._weatherGeoResults = []
                                                        _wLocInput.text = ""
                                                    }
                                                }
                                            }
                                        }

                                        // Hint when no results yet
                                        Text {
                                            visible: ccWin._weatherGeoResults.length === 0
                                                  && !ccWin._weatherGeoSearching
                                            text: "Type a city, town or district and press Enter"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.35)
                                            font.family: Config.labelFont; font.pixelSize: 10
                                            wrapMode: Text.Wrap; Layout.fillWidth: true
                                        }
                                        Text {
                                            visible: ccWin._weatherGeoResults.length === 0
                                                  && ccWin._weatherGeoSearching
                                            text: "Searching…"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.45)
                                            font.family: Config.labelFont; font.pixelSize: 11
                                            Layout.fillWidth: true
                                        }

                                        CCSection { text: "Mode & Position" }
                                        CCSegmented {
                                            label: "Bar Mode"
                                            options: ["bar", "island", "tri"]
                                            current: Config.barMode
                                            onPicked: function(v) { Config.barMode = v }
                                        }
                                        CCSegmented {
                                            label: "Position"
                                            options: ["top","bottom"] //,"left","right" (commented currently broken left&right position)
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
                                        CCSlider { label:"Module BG";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.moduleBgOpacity;      onMoved:function(v){Config.moduleBgOpacity=v} }
                                        CCSlider { label:"Island BG";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.islandBgOpacityIsland;onMoved:function(v){Config.islandBgOpacityIsland=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Icons ──────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Glyph Sizes" }
                                        CCSlider { label:"Glyph Size";  from:8;to:24; value:Config.glyphSize;     onMoved:function(v){Config.glyphSize=v} }
                                        CCSlider { label:"Info Glyph";  from:8;to:24; value:Config.infoGlyphSize;  onMoved:function(v){Config.infoGlyphSize=v} }
                                        CCSlider { label:"Media Glyph"; from:8;to:24; value:Config.mediaGlyphSize; onMoved:function(v){Config.mediaGlyphSize=v} }

                                        CCSection { text: "Text Sizes" }
                                        CCSlider { label:"Info Text";  from:8;to:20; value:Config.infoFontSize;     onMoved:function(v){Config.infoFontSize=v} }
                                        CCSlider { label:"Label Text"; from:8;to:20; value:Config.labelFontSize;    onMoved:function(v){Config.labelFontSize=v} }
                                        CCSlider { label:"Media Text"; from:8;to:20; value:Config.mediaInfoFontSize;onMoved:function(v){Config.mediaInfoFontSize=v} }

                                        CCSection { text: "Workspace Icon Glyphs" }
                                        CCIconEntry { label:"Active Dot";     value:Config.wsDotActive;     onApplied:function(v){Config.wsDotActive=v} }
                                        CCIconEntry { label:"Persistent Dot"; value:Config.wsDotPersistent; onApplied:function(v){Config.wsDotPersistent=v} }
                                        CCIconEntry { label:"Empty Dot";      value:Config.wsDotEmpty;      onApplied:function(v){Config.wsDotEmpty=v} }
                                        CCIconEntry { label:"WS Separator";   value:Config.wsSeparatorGlyph;onApplied:function(v){Config.wsSeparatorGlyph=v} }

                                        CCSection { text: "Control Center" }
                                        CCIconEntry { label:"CC Glyph";    value:Config.ccGlyph;    onApplied:function(v){Config.ccGlyph=v} }

                                        CCSection { text: "Battery" }
                                        CCToggle { label:"Radial Visible"; value:Config.batteryRadialVisible; onToggled:function(v){Config.batteryRadialVisible=v} }
                                        CCSlider { label:"Radial Size";  from:8;to:32; value:Config.batteryRadialSize;  onMoved:function(v){Config.batteryRadialSize=v} }
                                        CCSlider { label:"Radial Stroke";from:1;to:6;  value:Config.batteryRadialWidth; onMoved:function(v){Config.batteryRadialWidth=v} }

                                        CCSection { text: "Tray" }
                                        CCSlider { label:"Icon Size";    from:10;to:32; value:Config.trayIconSz;     onMoved:function(v){Config.trayIconSz=v} }
                                        CCSlider { label:"Item Pad H";   from:0;to:8;   value:Config.trayItemPadH;   onMoved:function(v){Config.trayItemPadH=v} }
                                        CCSlider { label:"Item Spacing"; from:0;to:10;  value:Config.trayItemSpacing; onMoved:function(v){Config.trayItemSpacing=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Workspaces ─────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Display Mode" }
                                        // "dot" mode removed as requested — only number & icon
                                        CCSegmented {
                                            label: "Icon Mode"
                                            options: ["number","icon"]
                                            current: Config.wsIconMode === "dot" ? "number" : Config.wsIconMode
                                            onPicked: function(v) { Config.wsIconMode = v }
                                        }

                                        CCSection { text: "Sizing" }
                                        CCSlider { label:"Glyph Size"; from:8;to:24; value:Config.wsGlyphSize; onMoved:function(v){Config.wsGlyphSize=v} }

                                        CCSection { text: "Spacing (0 = true zero)" }
                                        CCSlider { label:"WS Spacing";   from:0;to:20; value:Config.wsSpacing;   onMoved:function(v){Config.wsSpacing=v} }
                                        CCSlider { label:"Margin Left";  from:0;to:20; value:Config.wsMarginLeft; onMoved:function(v){Config.wsMarginLeft=v} }
                                        CCSlider { label:"Margin Right"; from:0;to:20; value:Config.wsMarginRight;onMoved:function(v){Config.wsMarginRight=v} }

                                        CCSection { text: "Button Padding" }
                                        CCSlider { label:"Pad Left";   from:0;to:16; value:Config.wsPadLeft;   onMoved:function(v){Config.wsPadLeft=v} }
                                        CCSlider { label:"Pad Right";  from:0;to:16; value:Config.wsPadRight;  onMoved:function(v){Config.wsPadRight=v} }
                                        CCSlider { label:"Pad Top";    from:0;to:10; value:Config.wsPadTop;    onMoved:function(v){Config.wsPadTop=v} }
                                        CCSlider { label:"Pad Bottom"; from:0;to:10; value:Config.wsPadBottom; onMoved:function(v){Config.wsPadBottom=v} }

                                        CCSection { text: "Separators" }
                                        CCToggle { label:"Show Separators"; value:Config.wsSeparators; onToggled:function(v){Config.wsSeparators=v} }
                                        CCSlider { label:"Sep Size";  from:6;to:20; value:Config.wsSeparatorSize;     onMoved:function(v){Config.wsSeparatorSize=v} }
                                        CCSlider { label:"Sep Pad L"; from:0;to:10; value:Config.wsSeparatorPadLeft;  onMoved:function(v){Config.wsSeparatorPadLeft=v} }
                                        CCSlider { label:"Sep Pad R"; from:0;to:10; value:Config.wsSeparatorPadRight; onMoved:function(v){Config.wsSeparatorPadRight=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Media ──────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Thumbnail" }
                                        CCSlider { label:"Thumb Size";      from:10;to:40; value:Config.mediaThumbSize;    onMoved:function(v){Config.mediaThumbSize=v} }

                                        CCSection { text: "Controls" }
                                        CCSlider { label:"Play/Pause Size"; from:4;to:20;  value:Config.mediaPlayPauseSize; onMoved:function(v){Config.mediaPlayPauseSize=v} }

                                        CCSection { text: "Text" }
                                        CCSlider { label:"Info Text";       from:8;to:18;  value:Config.mediaInfoFontSize;  onMoved:function(v){Config.mediaInfoFontSize=v} }

                                        CCSection { text: "Padding (0 = true zero)" }
                                        CCSlider { label:"Pad Left";   from:0;to:16; value:Config.mediaPadLeft;   onMoved:function(v){Config.mediaPadLeft=v} }
                                        CCSlider { label:"Pad Right";  from:0;to:16; value:Config.mediaPadRight;  onMoved:function(v){Config.mediaPadRight=v} }
                                        CCSlider { label:"Pad Top";    from:0;to:10; value:Config.mediaPadTop;    onMoved:function(v){Config.mediaPadTop=v} }
                                        CCSlider { label:"Pad Bottom"; from:0;to:10; value:Config.mediaPadBottom; onMoved:function(v){Config.mediaPadBottom=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Cava ───────────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "ASCII Style" }
                                        // Preview icons row — one per style, wraps to next line
                                        Flow {
                                            Layout.fillWidth: true
                                            spacing: 6
                                            Repeater {
                                                model: Object.keys(Config.cavaStyleMap)
                                                delegate: Item {
                                                    required property string modelData
                                                    required property int    index
                                                    // Fixed width so all cells align uniformly
                                                    width: 72; height: 52

                                                    Column {
                                                        anchors.fill: parent
                                                        spacing: 4

                                                        // ── Preview chars ──────────────────────
                                                        Rectangle {
                                                            width: parent.width; height: 28
                                                            radius: 7
                                                            color: Config.cavaStyle === modelData
                                                                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                          Theme.cInversePrimary.b, 0.30)
                                                                : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                          Theme.cInversePrimary.b, 0.09)
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: Config.cavaStyleMap[modelData] || ""
                                                                font.family: Config.fontFamily
                                                                font.pixelSize: 11
                                                                color: Config.cavaStyle === modelData
                                                                    ? Theme.cPrimary
                                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                              Theme.cPrimary.b, 0.55)
                                                                Behavior on color { ColorAnimation { duration: 120 } }
                                                            }
                                                        }

                                                        // ── Style name button ──────────────────
                                                        Rectangle {
                                                            width: parent.width; height: 20
                                                            radius: 6
                                                            color: Config.cavaStyle === modelData
                                                                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                          Theme.cInversePrimary.b, 0.72)
                                                                : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                          Theme.cInversePrimary.b, 0.16)
                                                            border.width: Config.cavaStyle === modelData ? 1 : 0
                                                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                                  Theme.cPrimary.b, 0.5)
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                color: Theme.cPrimary
                                                                font.family: Config.labelFont
                                                                font.pixelSize: 10
                                                                elide: Text.ElideRight
                                                                width: parent.width - 6
                                                                horizontalAlignment: Text.AlignHCenter
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent
                                                                cursorShape: Qt.PointingHandCursor
                                                                onClicked: Config.cavaStyle = modelData
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        CCSection { text: "Width & Behavior" }
                                        CCSlider { label:"Bar Count";   from:5;to:80;stepSize:1;    value:Config.cavaWidth;      onMoved:function(v){Config.cavaWidth=v} }
                                        CCSlider { label:"Bar Spacing"; from:0;to:6;stepSize:0.5;decimals:1; value:Config.cavaBarSpacing; onMoved:function(v){Config.cavaBarSpacing=v} }
                                        CCToggle { label:"Transparent Inactive"; value:Config.cavaTransparentWhenInactive; onToggled:function(v){Config.cavaTransparentWhenInactive=v} }
                                        CCSlider { label:"Active Opacity";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.cavaActiveOpacity;  onMoved:function(v){Config.cavaActiveOpacity=v} }
                                        CCSlider { label:"Inactive Opacity";from:0;to:1;stepSize:0.05;decimals:2; value:Config.cavaInactiveOpacity;onMoved:function(v){Config.cavaInactiveOpacity=v} }

                                        CCSection { text: "Color" }
                                        CCToggle { label:"Gradient"; value:Config.cavaGradientEnabled; onToggled:function(v){Config.cavaGradientEnabled=v} }
                                        // Color A: single color when gradient off; start color when on
                                        CCColorPicker {
                                            label: Config.cavaGradientEnabled ? "Start Color" : "Bar Color"
                                            currentColor: Config.cavaGradientEnabled
                                                ? Config.cavaGradientStartColor
                                                : Config.cavaGlyphColor
                                            onColorPicked: function(c) {
                                                if (Config.cavaGradientEnabled)
                                                    Config.cavaGradientStartColor = c
                                                else
                                                    Config.cavaGlyphColor = c
                                            }
                                        }
                                        // Color B: gradient end color
                                        CCColorPicker {
                                            label: "End Color"
                                            currentColor: Config.cavaGradientEnabled
                                                ? Config.cavaGradientEndColor
                                                : Theme.cSecondary
                                            pickerEnabled: Config.cavaGradientEnabled
                                            onColorPicked: function(c) {
                                                if (Config.cavaGradientEnabled)
                                                    Config.cavaGradientEndColor = c
                                            }
                                        }
                                        CCSlider {
                                            label: "Gradient Split"
                                            visible: Config.cavaGradientEnabled
                                            from: 0.1; to: 0.9; stepSize: 0.05; decimals: 2
                                            value: Config.cavaGradientSplit
                                            onMoved: function(v) { Config.cavaGradientSplit = v }
                                        }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Background ─────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Per-Group Background Opacity" }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "−1 = use global module BG opacity"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.48)
                                            font.family: Config.labelFont; font.pixelSize: 11
                                            wrapMode: Text.Wrap
                                        }

                                        CCSlider { label:"Workspaces";    from:-1;to:1;stepSize:0.05;decimals:2; value:Config.wsBgOpacity;          onMoved:function(v){Config.wsBgOpacity=v} }
                                        CCSlider { label:"Grouped";       from:-1;to:1;stepSize:0.05;decimals:2; value:Config.groupedBgOpacity;      onMoved:function(v){Config.groupedBgOpacity=v} }
                                        CCSlider { label:"Ungrouped";     from:-1;to:1;stepSize:0.05;decimals:2; value:Config.ungroupedBgOpacity;    onMoved:function(v){Config.ungroupedBgOpacity=v} }
                                        CCSlider { label:"Media";         from:-1;to:1;stepSize:0.05;decimals:2; value:Config.mediaBgOpacity;        onMoved:function(v){Config.mediaBgOpacity=v} }
                                        CCSlider { label:"Cava";          from:-1;to:1;stepSize:0.05;decimals:2; value:Config.cavaBgOpacity;         onMoved:function(v){Config.cavaBgOpacity=v} }
                                        CCSlider { label:"Distro";        from:-1;to:1;stepSize:0.05;decimals:2; value:Config.distroBgOpacity;       onMoved:function(v){Config.distroBgOpacity=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Visibility ─────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Show / Hide Modules" }
                                        CCToggle { label:"Cava";           value:Config.showCava;           onToggled:function(v){Config.showCava=v} }
                                        CCToggle {
                                            label:"Cava Auto-Hide"
                                            value:Config.cavaAutoHide
                                            enabled: Config.showCava
                                            onToggled:function(v){Config.cavaAutoHide=v}
                                        }
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
                                        CCToggle { label:"Distro Icon";    value:Config.showDistro;         onToggled:function(v){Config.showDistro=v} }

                                        Item { height: 10 }
                                    }
                                }
                            }
                        }
                    }

                    // ── TAB 1: Hyprland ─────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5

                            CCSection { text: " Hyprland" }

                            // ── Hyprsunset toggle — reads sentinel state file ─────
                            CCToggle {
                                id: sunsetToggle
                                label: "Hyprsunset"
                                value: false
                                Component.onCompleted: _sunsetStatus.running = true
                                onToggled: function(v) {
                                    _sunsetToggleProc.command = [scriptDir + "/hyprland-hyprsunset.sh", "toggle"]
                                    _sunsetToggleProc.running = true
                                }
                            }
                            Process {
                                id: _sunsetStatus
                                command: [scriptDir + "/hyprland-hyprsunset.sh", "status"]
                                running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) { sunsetToggle.value = l.trim() === "on" }
                                }
                            }
                            Process { id: _sunsetToggleProc; running: false }

                            // ── Gamma +/- buttons ─────────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text {
                                    text: "Gamma"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                CCPillBtn {
                                    text: "−10"
                                    onClicked: {
                                        _gammaDec.command = [scriptDir + "/hyprland-gamma.sh", "-10"]
                                        _gammaDec.running = true
                                    }
                                }
                                CCPillBtn {
                                    text: "+10"
                                    onClicked: {
                                        _gammaInc.command = [scriptDir + "/hyprland-gamma.sh", "10"]
                                        _gammaInc.running = true
                                    }
                                }
                            }
                            Process { id: _gammaDec; running: false; onExited: running = false }
                            Process { id: _gammaInc; running: false; onExited: running = false }

                            CCPillBtn { text: "󰈊  Hyprpicker"; onClicked: _picker.running = true }
                            Process { id: _picker; command: ["hyprpicker"]; running: false }

                            // ── X-Ray toggle ──────────────────────────────────────
                            CCToggle {
                                id: xrayToggle; label: "X-Ray"; value: false
                                Component.onCompleted: _xrayStatus.running = true
                                onToggled: function(v) {
                                    _xrayToggleProc.command = [scriptDir + "/hyprland-xray.sh", "toggle"]
                                    _xrayToggleProc.running = true
                                }
                            }
                            Process {
                                id: _xrayStatus
                                command: [scriptDir + "/hyprland-xray.sh", "status"]
                                running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) { xrayToggle.value = l.trim() === "on" }
                                }
                            }
                            Process { id: _xrayToggleProc; running: false }

                            // ── Opacity toggle ────────────────────────────────────
                            CCToggle {
                                id: opacToggle; label: "Opacity"; value: false
                                Component.onCompleted: _opacStatus.running = true
                                onToggled: function(v) {
                                    _opacToggleProc.command = [scriptDir + "/hyprland-opacity.sh", "toggle"]
                                    _opacToggleProc.running = true
                                }
                            }
                            Process {
                                id: _opacStatus
                                command: [scriptDir + "/hyprland-opacity.sh", "status"]
                                running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) { opacToggle.value = l.trim() === "on" }
                                }
                            }
                            Process { id: _opacToggleProc; running: false }

                            // ── Opacity +/- buttons with direct entry ────────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    text: "Opacity"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                CCPillBtn {
                                    text: "−"
                                    onClicked: {
                                        _opacDec.command = [scriptDir + "/hyprland-opacity-adjust.sh", "-0.05"]
                                        _opacDec.running = true
                                    }
                                }
                                // Direct value entry
                                Rectangle {
                                    Layout.preferredWidth: 60; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _opacTI
                                        anchors { fill: parent; margins: 6 }
                                        text: _opacEntryVal
                                        color: Theme.cPrimary
                                        font.family: Config.labelFont
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        validator: DoubleValidator { bottom: 0.0; top: 1.0; decimals: 2; notation: DoubleValidator.StandardNotation }
                                        onAccepted: {
                                            _opacSet.command = [scriptDir + "/hyprland-opacity-set.sh", text]
                                            _opacSet.running = true
                                            _opacEntryVal = text
                                        }
                                    }
                                }
                                CCPillBtn {
                                    text: "+"
                                    onClicked: {
                                        _opacInc.command = [scriptDir + "/hyprland-opacity-adjust.sh", "0.05"]
                                        _opacInc.running = true
                                    }
                                }
                            }
                            Process { id: _opacDec; running: false; onExited: { running = false; _hyprlandValReader.running = true } }
                            Process { id: _opacInc; running: false; onExited: { running = false; _hyprlandValReader.running = true } }
                            Process { id: _opacSet; running: false }

                            // ── Blur Size +/- buttons with direct entry ──────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    text: "Blur Size"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                CCPillBtn {
                                    text: "−"
                                    onClicked: {
                                        _blurSizeDec.command = [scriptDir + "/hyprland-blur-size.sh", "-1"]
                                        _blurSizeDec.running = true
                                    }
                                }
                                // Direct value entry
                                Rectangle {
                                    Layout.preferredWidth: 60; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _blurSizeTI
                                        anchors { fill: parent; margins: 6 }
                                        text: _blurSizeEntryVal
                                        color: Theme.cPrimary
                                        font.family: Config.labelFont
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        validator: IntValidator { bottom: 0; top: 50 }
                                        onAccepted: {
                                            _blurSizeSet.command = [scriptDir + "/hyprland-blur-size-set.sh", text]
                                            _blurSizeSet.running = true
                                            _blurSizeEntryVal = text
                                        }
                                    }
                                }
                                CCPillBtn {
                                    text: "+"
                                    onClicked: {
                                        _blurSizeInc.command = [scriptDir + "/hyprland-blur-size.sh", "1"]
                                        _blurSizeInc.running = true
                                    }
                                }
                            }
                            Process { id: _blurSizeDec; running: false; onExited: { running = false; _hyprlandValReader.running = true } }
                            Process { id: _blurSizeInc; running: false; onExited: { running = false; _hyprlandValReader.running = true } }
                            Process { id: _blurSizeSet; running: false }

                            // ── Blur Passes +/- buttons with direct entry ────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    text: "Blur Passes"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                CCPillBtn {
                                    text: "−"
                                    onClicked: {
                                        _blurPassesDec.command = [scriptDir + "/hyprland-blur-passes.sh", "-1"]
                                        _blurPassesDec.running = true
                                    }
                                }
                                // Direct value entry
                                Rectangle {
                                    Layout.preferredWidth: 60; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.12)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _blurPassesTI
                                        anchors { fill: parent; margins: 6 }
                                        text: _blurPassesEntryVal
                                        color: Theme.cPrimary
                                        font.family: Config.labelFont
                                        font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        validator: IntValidator { bottom: 0; top: 10 }
                                        onAccepted: {
                                            _blurPassesSet.command = [scriptDir + "/hyprland-blur-passes-set.sh", text]
                                            _blurPassesSet.running = true
                                            _blurPassesEntryVal = text
                                        }
                                    }
                                }
                                CCPillBtn {
                                    text: "+"
                                    onClicked: {
                                        _blurPassesInc.command = [scriptDir + "/hyprland-blur-passes.sh", "1"]
                                        _blurPassesInc.running = true
                                    }
                                }
                            }
                            Process { id: _blurPassesDec; running: false; onExited: { running = false; _hyprlandValReader.running = true } }
                            Process { id: _blurPassesInc; running: false; onExited: { running = false; _hyprlandValReader.running = true } }
                            Process { id: _blurPassesSet; running: false }

                            // ── Gaps & Border ─────────────────────────────────────
                            CCSection { text: "Gaps & Border" }

                            // Inner Gaps
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text {
                                    text: "Inner Gaps"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont
                                    font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                CCPillBtn { text: "−"; onClicked: {
                                    const nv = Math.max(0, (parseInt(_gapsInnerEntryVal) || 0) - 1)
                                    _gapsInnerDec.command=[scriptDir+"/hyprland-gaps-inner-set.sh", nv.toString()]
                                    _gapsInnerDec.running=true
                                    _gapsInnerEntryVal = nv.toString()
                                    _gapsInnerTI.text  = _gapsInnerEntryVal
                                }}
                                Rectangle {
                                    Layout.preferredWidth: 60; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.12)
                                    border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _gapsInnerTI
                                        anchors { fill: parent; margins: 6 }
                                        text: _gapsInnerEntryVal; color: Theme.cPrimary
                                        font.family: Config.labelFont; font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        validator: IntValidator { bottom: 0; top: 100 }
                                        onAccepted: { _gapsInnerSet.command=[scriptDir+"/hyprland-gaps-inner-set.sh",text]; _gapsInnerSet.running=true; _gapsInnerEntryVal=text }
                                    }
                                }
                                CCPillBtn { text: "+"; onClicked: {
                                    const nv = Math.min(100, (parseInt(_gapsInnerEntryVal) || 0) + 1)
                                    _gapsInnerInc.command=[scriptDir+"/hyprland-gaps-inner-set.sh", nv.toString()]
                                    _gapsInnerInc.running=true
                                    _gapsInnerEntryVal = nv.toString()
                                    _gapsInnerTI.text  = _gapsInnerEntryVal
                                }}
                            }
                            Process { id:_gapsInnerDec; running:false }
                            Process { id:_gapsInnerInc; running:false }
                            Process { id:_gapsInnerSet; running:false }

                            // Outer Gaps
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text { text: "Outer Gaps"; color: Theme.cPrimary; font.family: Config.labelFont; font.pixelSize: 13; Layout.preferredWidth: 100 }
                                CCPillBtn { text: "−"; onClicked: {
                                    const nv = Math.max(0, (parseInt(_gapsOuterEntryVal) || 0) - 1)
                                    _gapsOuterDec.command=[scriptDir+"/hyprland-gaps-outer-set.sh", nv.toString()]
                                    _gapsOuterDec.running=true
                                    _gapsOuterEntryVal = nv.toString()
                                    _gapsOuterTI.text  = _gapsOuterEntryVal
                                }}
                                Rectangle {
                                    Layout.preferredWidth: 60; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.12)
                                    border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _gapsOuterTI
                                        anchors { fill: parent; margins: 6 }
                                        text: _gapsOuterEntryVal; color: Theme.cPrimary
                                        font.family: Config.labelFont; font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        validator: IntValidator { bottom: 0; top: 100 }
                                        onAccepted: { _gapsOuterSet.command=[scriptDir+"/hyprland-gaps-outer-set.sh",text]; _gapsOuterSet.running=true; _gapsOuterEntryVal=text }
                                    }
                                }
                                CCPillBtn { text: "+"; onClicked: {
                                    const nv = Math.min(100, (parseInt(_gapsOuterEntryVal) || 0) + 1)
                                    _gapsOuterInc.command=[scriptDir+"/hyprland-gaps-outer-set.sh", nv.toString()]
                                    _gapsOuterInc.running=true
                                    _gapsOuterEntryVal = nv.toString()
                                    _gapsOuterTI.text  = _gapsOuterEntryVal
                                }}
                            }
                            Process { id:_gapsOuterDec; running:false }
                            Process { id:_gapsOuterInc; running:false }
                            Process { id:_gapsOuterSet; running:false }

                            // Border Width
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text { text: "Border W"; color: Theme.cPrimary; font.family: Config.labelFont; font.pixelSize: 13; Layout.preferredWidth: 100 }
                                CCPillBtn { text: "−"; onClicked: {
                                    const nv = Math.max(0, (parseInt(_borderWEntryVal) || 0) - 1)
                                    _borderWDec.command=[scriptDir+"/hyprland-border-width-set.sh", nv.toString()]
                                    _borderWDec.running=true
                                    _borderWEntryVal = nv.toString()
                                    _borderWTI.text  = _borderWEntryVal
                                }}
                                Rectangle {
                                    Layout.preferredWidth: 60; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.12)
                                    border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _borderWTI
                                        anchors { fill: parent; margins: 6 }
                                        text: _borderWEntryVal; color: Theme.cPrimary
                                        font.family: Config.labelFont; font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        validator: IntValidator { bottom: 0; top: 20 }
                                        onAccepted: { _borderWSet.command=[scriptDir+"/hyprland-border-width-set.sh",text]; _borderWSet.running=true; _borderWEntryVal=text }
                                    }
                                }
                                CCPillBtn { text: "+"; onClicked: {
                                    const nv = Math.min(20, (parseInt(_borderWEntryVal) || 0) + 1)
                                    _borderWInc.command=[scriptDir+"/hyprland-border-width-set.sh", nv.toString()]
                                    _borderWInc.running=true
                                    _borderWEntryVal = nv.toString()
                                    _borderWTI.text  = _borderWEntryVal
                                }}
                            }
                            Process { id:_borderWDec; running:false }
                            Process { id:_borderWInc; running:false }
                            Process { id:_borderWSet; running:false }

                            // Border Radius (Rounding)
                            RowLayout {
                                Layout.fillWidth: true; spacing: 6
                                Text { text: "Border R"; color: Theme.cPrimary; font.family: Config.labelFont; font.pixelSize: 13; Layout.preferredWidth: 100 }
                                CCPillBtn { text: "−"; onClicked: {
                                    const nv = Math.max(0, (parseInt(_borderREntryVal) || 0) - 1)
                                    _borderRDec.command=[scriptDir+"/hyprland-border-radius-set.sh", nv.toString()]
                                    _borderRDec.running=true
                                    _borderREntryVal = nv.toString()
                                    _borderRTI.text  = _borderREntryVal
                                }}
                                Rectangle {
                                    Layout.preferredWidth: 60; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.12)
                                    border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _borderRTI
                                        anchors { fill: parent; margins: 6 }
                                        text: _borderREntryVal; color: Theme.cPrimary
                                        font.family: Config.labelFont; font.pixelSize: 12
                                        horizontalAlignment: Text.AlignHCenter
                                        validator: IntValidator { bottom: 0; top: 50 }
                                        onAccepted: { _borderRSet.command=[scriptDir+"/hyprland-border-radius-set.sh",text]; _borderRSet.running=true; _borderREntryVal=text }
                                    }
                                }
                                CCPillBtn { text: "+"; onClicked: {
                                    const nv = Math.min(50, (parseInt(_borderREntryVal) || 0) + 1)
                                    _borderRInc.command=[scriptDir+"/hyprland-border-radius-set.sh", nv.toString()]
                                    _borderRInc.running=true
                                    _borderREntryVal = nv.toString()
                                    _borderRTI.text  = _borderREntryVal
                                }}
                            }
                            Process { id:_borderRDec; running:false }
                            Process { id:_borderRInc; running:false }
                            Process { id:_borderRSet; running:false }

                            CCSection { text: "Gap Presets" }
                            Flow { Layout.fillWidth: true; spacing: 5
                                Repeater {
                                    model: ["minimal", "balanced", "spacious", "zero"]
                                    delegate: CCPillBtn {
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
                            Item { height: 10 }
                        }
                    }

                    // ── TAB 2: Themes ────────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            id: _themeTab
                            width: parent.width; spacing: 5
                            CCSection { text: "󰔎 Matugen Themes" }
                            // Current theme state
                            property string _currentTheme: "scheme-content"
                            Component.onCompleted: {
                                _themeRead.running = true
                            }

                            // ── Light Mode button alone at top ─────────────────────────────────
                            CCSection { text: "Light Mode" }
                            RowLayout { Layout.fillWidth:true; spacing:5
                                CCPillBtn {
                                    text:"☀ Light"
                                    active: parent.parent._currentTheme === "light"
                                    onClicked: {
                                        _themeProc.command = [scriptDir+"/theme-set.sh", "light"]
                                        _themeProc.running = true
                                        parent.parent._currentTheme = "light"
                                    }
                                }
                            }

                            // ── Dark Mode Schemes ───────────────────────────────────────────────
                            CCSection { text: "Dark Mode Schemes" }
                            Flow { Layout.fillWidth: true; spacing: 5
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
                                        active: parent.parent.parent._currentTheme === modelData.scheme
                                        onClicked: {
                                            _themeProc.command = [scriptDir+"/theme-set.sh", modelData.scheme]
                                            _themeProc.running = true
                                            parent.parent.parent._currentTheme = modelData.scheme
                                        }
                                    }
                                }
                            }
                            Process { id:_themeProc; running:false }
                            Process {
                                id: _themeRead
                                command: ["bash", "-c", "cat \"$HOME/.config/hyprcandy/matugen-state\" 2>/dev/null || echo scheme-content"]
                                running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v) _themeTab._currentTheme = v
                                    }
                                }
                            }
                            Item { height:10 }
                        }
                    }

                    // ── TAB 3: Dock (hyprcandy-dock) ─────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5
                            CCSection { text: "󰞒 Dock" }

                            // Cycle position — calls dock-cycle.sh which setsid-detaches from QS
                            CCPillBtn {
                                text: "󰶘 Cycle Position"
                                onClicked: {
                                    _dockCycle.command = [scriptDir + "/dock-cycle.sh"]
                                    _dockCycle.running = true
                                }
                            }
                            Process { id: _dockCycle; running: false; onExited: running = false }

                            // Spacing — read current value on open
                            CCEntryRow {
                                label: "Spacing"
                                value: _dockSpacingVal
                                onApplied: function(val) {
                                    const n = parseInt(val)
                                    if (!isNaN(n) && n >= 0 && n <= 30) {
                                        _dockWrite.command = [scriptDir + "/dock-set.sh", "buttonSpacing", n.toString()]
                                        _dockWrite.running = true
                                    }
                                }
                            }
                            CCEntryRow {
                                label: "Padding"
                                value: _dockPaddingVal
                                onApplied: function(val) {
                                    const n = parseInt(val)
                                    if (!isNaN(n) && n >= 0 && n <= 30) {
                                        _dockWrite.command = [scriptDir + "/dock-set.sh", "innerPadding", n.toString()]
                                        _dockWrite.running = true
                                    }
                                }
                            }
                            CCEntryRow {
                                label: "Border W"
                                value: _dockBorderWVal
                                onApplied: function(val) {
                                    const n = parseInt(val)
                                    if (!isNaN(n) && n >= 0 && n <= 10) {
                                        _dockWrite.command = [scriptDir + "/dock-set.sh", "borderWidth", n.toString()]
                                        _dockWrite.running = true
                                    }
                                }
                            }
                            CCEntryRow {
                                label: "Border R"
                                value: _dockBorderRVal
                                onApplied: function(val) {
                                    const n = parseInt(val)
                                    if (!isNaN(n) && n >= 0 && n <= 100) {
                                        _dockWrite.command = [scriptDir + "/dock-set.sh", "borderRadius", n.toString()]
                                        _dockWrite.running = true
                                    }
                                }
                            }
                            Process { id: _dockWrite; running: false; onExited: running = false }

                            // Read dock config values on load
                            Process { id: _dockReadSpacing; command: [scriptDir+"/dock-get.sh", "buttonSpacing"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockSpacingVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadPadding; command: [scriptDir+"/dock-get.sh", "innerPadding"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockPaddingVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadBorderW; command: [scriptDir+"/dock-get.sh", "borderWidth"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockBorderWVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadBorderR; command: [scriptDir+"/dock-get.sh", "borderRadius"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockBorderRVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadIconSize; command: [scriptDir+"/dock-get.sh", "appIconSize"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockIconSizeVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadStartIcon; command: [scriptDir+"/dock-get.sh", "startIcon"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v) _dockStartIconVal = v
                                    }
                                }
                            }

                            // Start all dock reads on component complete
                            Timer {
                                interval: 100; running: true; repeat: false
                                onTriggered: {
                                    _dockReadSpacing.running = true
                                    _dockReadPadding.running = true
                                    _dockReadBorderW.running = true
                                    _dockReadBorderR.running = true
                                    _dockReadIconSize.running = true
                                    _dockReadStartIcon.running = true
                                }
                            }

                            CCEntryRow {
                                label: "Icon Size"
                                value: _dockIconSizeVal
                                onApplied: function(val) {
                                    const n = parseInt(val)
                                    if (!isNaN(n) && n >= 12 && n <= 64) {
                                        _dockIcon.command = [scriptDir + "/dock-icon-size.sh", n.toString()]
                                        _dockIcon.running = true
                                    }
                                }
                            }
                            Process { id: _dockIcon; running: false; onExited: running = false }

                            CCEntryRow {
                                label: "Start Icon"
                                value: _dockStartIconVal
                                onApplied: function(val) {
                                    if (val) {
                                        _dockStartIcon.command = [scriptDir + "/dock-start-icon.sh", val]
                                        _dockStartIcon.running = true
                                    }
                                }
                            }
                            Process { id: _dockStartIcon; running: false; onExited: running = false }
                            Item { height: 10 }
                        }
                    }

                    // ── TAB 4: Menus (Rofi) ──────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5
                            CCSection { text: "󰮫 Menus (Rofi)" }

                            CCEntryRow {
                                label: "Border"
                                value: _rofiBorderVal
                                onApplied: function(v) {
                                    const n = parseInt(v)
                                    if (!isNaN(n) && n >= 0 && n <= 10) {
                                        _rofiBorderVal = n.toString()
                                        _rofiBorder.command = [scriptDir + "/rofi-border.sh", n.toString()]
                                        _rofiBorder.running = true
                                    }
                                }
                            }
                            Process { id: _rofiBorder; running: false }

                            CCEntryRow {
                                label: "Radius"
                                value: _rofiRadiusVal
                                onApplied: function(v) {
                                    const n = parseFloat(v)
                                    if (!isNaN(n) && n >= 0 && n <= 5) {
                                        _rofiRadiusVal = n.toFixed(1)
                                        _rofiRadius.command = [scriptDir + "/rofi-radius.sh", n.toFixed(1)]
                                        _rofiRadius.running = true
                                    }
                                }
                            }
                            Process { id: _rofiRadius; running: false }

                            RowLayout { Layout.fillWidth: true; spacing: 8
                                Text { text: "Icon Size"; color: Theme.cPrimary; font.family: Config.labelFont; font.pixelSize: 13; Layout.preferredWidth: 100 }
                                CCPillBtn { text: "−"; onClicked: _rofiIconDec.running = true }
                                CCPillBtn { text: "+"; onClicked: _rofiIconInc.running = true }
                            }
                            Process { id: _rofiIconDec; command: [scriptDir + "/rofi-icon-size.sh", "-0.5"]; running: false }
                            Process { id: _rofiIconInc; command: [scriptDir + "/rofi-icon-size.sh", "0.5"]; running: false }
                            Item { height: 10 }
                        }
                    }

                    // ── TAB 5: SDDM ──────────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            width: parent.width; spacing: 5
                            CCSection { text: "󰍂 SDDM" }

                            CCEntryRow {
                                label: "Header"
                                value: _sddmHeaderVal
                                onApplied: function(v) {
                                    _sddmHeaderVal = v
                                    _sddmHdr.command = [scriptDir + "/sddm-set.sh", "HeaderText", v, "sddm_header.state"]
                                    _sddmHdr.running = true
                                }
                            }
                            Process { id: _sddmHdr; running: false }

                            CCEntryRow {
                                label: "Form Pos"
                                value: _sddmFormVal
                                onApplied: function(v) {
                                    _sddmFormVal = v
                                    _sddmForm.command = [scriptDir + "/sddm-set.sh", "FormPosition", v, "sddm_form.state"]
                                    _sddmForm.running = true
                                }
                            }
                            Process { id: _sddmForm; running: false }

                            CCEntryRow {
                                label: "Blur R"
                                value: _sddmBlurVal
                                onApplied: function(v) {
                                    const n = parseInt(v)
                                    if (!isNaN(n) && n >= 0 && n <= 100) {
                                        _sddmBlurVal = n.toString()
                                        _sddmBlur.command = [scriptDir + "/sddm-set.sh", "BlurRadius", n.toString(), "sddm_blur.state"]
                                        _sddmBlur.running = true
                                    }
                                }
                            }
                            Process { id: _sddmBlur; running: false }

                            CCPillBtn { text: "󰈈 Preview"; onClicked: _sddmPreview.running = true }
                            Process {
                                id: _sddmPreview
                                command: ["bash", "-c",
                                    "setsid sddm-greeter --test-mode --theme /usr/share/sddm/themes/sugar-candy </dev/null >/dev/null 2>&1 &"]
                                running: false
                                onExited: running = false
                            }
                            Item { height: 10 }
                        }
                    }
                }
            }
        }
        }
    // ═══════════════════════════════════════════════════════════════
    //  Wallpaper Picker Overlay
    //  Opens ABOVE the control center when the user icon is clicked.
    //  Left sidebar for directory navigation; ImageMagick thumbnails;
    //  single-click any image to set as user icon.
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: wpPickerOverlay
        // Positioned to cover the control center panel area; sits above it via z-order
        anchors.fill: panel
        z: 10
        visible: false
        radius: 20
        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                       Theme.cOnSecondary.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.40)
        clip: true
        scale: visible ? 1.0 : 0.94
        transformOrigin: Item.Top
        opacity: visible ? 1.0 : 0.0
        Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 140 } }

        function open() {
            visible = true
            if (wpSettings.wallpaperDir) {
                _wpSidebarPath = _parentOf(wpSettings.wallpaperDir)
                _wpCurrentDir  = wpSettings.wallpaperDir
                _wpDoScan()
            } else {
                _wpSidebarPath = Quickshell.env("HOME") + "/Pictures"
                _wpCurrentDir  = ""
            }
            if (_wpSidebarOpen) _wpScanSidebarDirs(_wpSidebarPath)
        }
        function close() { visible = false }

        function _parentOf(p) {
            if (!p) return Quickshell.env("HOME")
            const s = p.endsWith("/") ? p.slice(0, -1) : p
            const idx = s.lastIndexOf("/")
            return idx > 0 ? s.substring(0, idx) : "/"
        }
        function _pathHash(p) {
            let h = 5381
            for (let i = 0; i < p.length; i++)
                h = ((h << 5) + h + p.charCodeAt(i)) >>> 0
            return ('00000000' + h.toString(16)).slice(-8)
        }

        // ── State ─────────────────────────────────────────────────────────────
        property var    _wallpapers:    []
        property var    _filtered:      []
        property bool   _wpSidebarOpen: false
        property string _wpSidebarPath: Quickshell.env("HOME") + "/Pictures"
        property var    _wpSidebarDirs: []
        property string _wpCurrentDir:  ""
        property string _wpSearchText:  ""
        // Thumb pipeline
        signal thumbReady(string origPath, string thumbSrc)
        property var  _thumbQueue:   []
        property bool _thumbRunning: false
        property int  _focusedIdx:   0

        // ── Settings persistence ──────────────────────────────────────────────
        Settings {
            id: wpSettings
            category: "cc-wp-picker-v1"
            property string wallpaperDir: ""
        }

        // ── Directory scan ────────────────────────────────────────────────────
        function _wpDoScan() {
            if (!_wpCurrentDir) return
            wpSettings.wallpaperDir = _wpCurrentDir
            _wallpapers = []
            _filtered = []
            _thumbQueue = []
            _thumbRunning = false
            if (wpScanProc.running) wpScanProc.running = false
            Qt.callLater(function() { wpScanProc.running = true })
        }

        function _wpApplyFilter() {
            const q = _wpSearchText.trim().toLowerCase()
            _filtered = q
                ? _wallpapers.filter(function(p) {
                      return p.split('/').pop().toLowerCase().includes(q)
                  })
                : _wallpapers.slice()
            if (_focusedIdx >= _filtered.length)
                _focusedIdx = Math.max(0, _filtered.length - 1)
            Qt.callLater(wpPickerOverlay._thumbDrain)
        }

        // Watch for search text changes
        on_WpSearchTextChanged: {
            if (_wallpapers.length > 0) _wpApplyFilter()
        }

        Process {
            id: wpScanProc
            property var _buf: []
            command: wpPickerOverlay._wpCurrentDir ? [
                "bash", "-c",
                "find \"$1\" -maxdepth 1 -type f " +
                "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
                "-o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \\) -print | sort",
                "--", wpPickerOverlay._wpCurrentDir
            ] : ["bash", "-c", "exit 0"]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: function(l) {
                    const t = l.trim()
                    if (t) wpScanProc._buf.push(t)
                }
            }
            onRunningChanged: if (running) _buf = []
            onExited: function() {
                wpPickerOverlay._wallpapers = _buf.slice()
                wpPickerOverlay._wpApplyFilter()
            }
        }

        // ── Sidebar directory listing ─────────────────────────────────────────
        function _wpScanSidebarDirs(path) {
            wpSidebarProc._path = path
            if (wpSidebarProc.running) wpSidebarProc.running = false
            Qt.callLater(function() { wpSidebarProc.running = true })
        }
        on_WpSidebarOpenChanged: {
            if (_wpSidebarOpen) _wpScanSidebarDirs(_wpSidebarPath)
        }

        Process {
            id: wpSidebarProc
            property string _path: ""
            property var    _buf:  []
            command: _path ? [
                "bash", "-c",
                "find \"$1\" -maxdepth 1 -mindepth 1 -type d -not -name '.*' -print | sort",
                "--", _path
            ] : ["bash", "-c", "exit 0"]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: function(l) {
                    const t = l.trim()
                    if (t) wpSidebarProc._buf.push(t)
                }
            }
            onRunningChanged: if (running) _buf = []
            onExited: function() { wpPickerOverlay._wpSidebarDirs = _buf.slice() }
        }

        // ── Thumbnail pipeline (ImageMagick → 160×100 rounded PNG) ───────────
        function thumbRequest(path) {
            if (!path) return
            if (_thumbQueue.indexOf(path) < 0) _thumbQueue.push(path)
            _thumbDrain()
        }
        function _thumbDrain() {
            if (_thumbRunning || _thumbQueue.length === 0) return
            const path  = _thumbQueue.shift()
            const hash  = _pathHash(path)
            const dst   = "/tmp/qs_cc_thumbs/" + hash + ".png"
            const safe  = path.replace(/'/g, "'\\''")
            const safed = dst.replace(/'/g, "'\\''")
            const isGif  = path.toLowerCase().endsWith(".gif")
            const srcArg = isGif ? ("'" + safe + "'[0]") : ("'" + safe + "'")
            _thumbRunning = true
            wpThumbProc._origPath = path
            wpThumbProc._dst      = dst
            wpThumbProc._cmd =
                "mkdir -p /tmp/qs_cc_thumbs; " +
                "[ -f '" + safed + "' ] && { echo ok; exit 0; }; " +
                "magick " + srcArg + " " +
                "-resize 160x100^ -gravity center -extent 160x100 " +
                "\\( +clone -alpha extract " +
                "   -fill black -colorize 100 " +
                "   -fill white -draw 'roundrectangle 0,0 159,99 14,14' \\) " +
                "-alpha off -compose CopyOpacity -composite " +
                "-strip '" + safed + "' 2>/dev/null && echo ok"
            wpThumbProc.running = true
        }

        Process {
            id: wpThumbProc
            property string _origPath: ""
            property string _dst:      ""
            property string _cmd:      "true"
            command: ["bash", "-c", wpThumbProc._cmd]
            onExited: function(code) {
                if (code === 0)
                    wpPickerOverlay.thumbReady(wpThumbProc._origPath,
                        "file://" + wpThumbProc._dst + "?" + Date.now())
                wpPickerOverlay._thumbRunning = false
                wpPickerOverlay._thumbDrain()
            }
        }

        // ── Sidebar overlay (left-slide) ──────────────────────────────────────
        Rectangle {
            id: wpSidebar
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width:  wpPickerOverlay._wpSidebarOpen ? 240 : 0
            radius: 20; clip: true
            color:  Qt.rgba(Theme.cBackground.r, Theme.cBackground.g, Theme.cBackground.b, 0.97)
            z: 20
            Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors { fill: parent; margins: 10 }
                spacing: 5
                visible: wpPickerOverlay._wpSidebarOpen

                // Current path + up button
                Rectangle {
                    Layout.fillWidth: true; height: 34; radius: 10
                    color: Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g,
                                   Theme.cSurfHi.b, 0.6)
                    RowLayout {
                        anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                        spacing: 5
                        Text {
                            text: "󰁞"; color: Theme.cPrimary
                            font.pixelSize: 14; font.family: Config.fontFamily
                            MouseArea {
                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const up = wpPickerOverlay._parentOf(wpPickerOverlay._wpSidebarPath)
                                    wpPickerOverlay._wpSidebarPath = up
                                    wpPickerOverlay._wpScanSidebarDirs(up)
                                }
                            }
                        }
                        Text {
                            Layout.fillWidth: true
                            text: wpPickerOverlay._wpSidebarPath.split('/').pop() || "/"
                            color: Theme.cOnSurf; font.pixelSize: 12
                            font.family: Config.labelFont; elide: Text.ElideRight
                        }
                    }
                }

                // Directory list
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentHeight: wpSidebarCol.implicitHeight
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    Column {
                        id: wpSidebarCol
                        width: parent.width; spacing: 2
                        Repeater {
                            model: wpPickerOverlay._wpSidebarDirs
                            delegate: Rectangle {
                                required property string modelData
                                width: wpSidebarCol.width; height: 30; radius: 8
                                color: dirHov.containsMouse
                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: 100 } }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                                    spacing: 5
                                    Text {
                                        text: "󰉋"; color: Theme.cPrimary
                                        font.pixelSize: 13; font.family: Config.fontFamily
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: modelData.split('/').pop()
                                        color: Theme.cOnSurf; font.pixelSize: 12
                                        font.family: Config.labelFont; elide: Text.ElideRight
                                    }
                                    Text {
                                        text: "󰁔"; color: Theme.cOnSurfVar
                                        font.pixelSize: 12; font.family: Config.fontFamily
                                    }
                                }
                                MouseArea {
                                    id: dirHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wpPickerOverlay._wpSidebarPath = modelData
                                        wpPickerOverlay._wpScanSidebarDirs(modelData)
                                    }
                                    onDoubleClicked: {
                                        wpPickerOverlay._wpCurrentDir = modelData
                                        wpPickerOverlay._wpDoScan()
                                        wpPickerOverlay._wpSidebarOpen = false
                                    }
                                }
                            }
                        }
                    }
                }

                // "Use this folder" button
                Rectangle {
                    Layout.fillWidth: true; height: 32; radius: 10
                    color: useFolderHov.containsMouse
                        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: "Use this folder"
                        color: Theme.cPrimary; font.pixelSize: 12
                        font.family: Config.labelFont; font.weight: Font.Medium
                    }
                    MouseArea {
                        id: useFolderHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            wpPickerOverlay._wpCurrentDir = wpPickerOverlay._wpSidebarPath
                            wpPickerOverlay._wpDoScan()
                            wpPickerOverlay._wpSidebarOpen = false
                        }
                    }
                }
            }
        }

        // ── Main content area (slides right when sidebar opens) ───────────────
        Item {
            anchors.fill: parent
            property real contentLeft: wpPickerOverlay._wpSidebarOpen ? wpSidebar.width : 0
            Behavior on contentLeft { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

            ColumnLayout {
                anchors {
                    top: parent.top; bottom: parent.bottom
                    left: parent.left; right: parent.right
                    leftMargin: parent.contentLeft + 14
                    topMargin: 14; bottomMargin: 14; rightMargin: 14
                }
                spacing: 8

                // Header row with search
                RowLayout {
                    Layout.fillWidth: true; spacing: 8
                    // Folder toggle
                    Rectangle {
                        width: 110; height: 30; radius: 999
                        color: wpPickerOverlay._wpSidebarOpen
                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                            : (wpFolderHov.containsMouse
                                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                                : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.07))
                        border.color: wpPickerOverlay._wpSidebarOpen ? Theme.cPrimary : "transparent"
                        border.width: wpPickerOverlay._wpSidebarOpen ? 1 : 0
                        Behavior on color { ColorAnimation { duration: 130 } }
                        MouseArea {
                            id: wpFolderHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                wpPickerOverlay._wpSidebarOpen = !wpPickerOverlay._wpSidebarOpen
                                if (wpPickerOverlay._wpSidebarOpen)
                                    wpPickerOverlay._wpScanSidebarDirs(wpPickerOverlay._wpSidebarPath)
                            }
                        }
                        RowLayout {
                            anchors.centerIn: parent; spacing: 5
                            Text {
                                text: "󰉋"
                                color: wpPickerOverlay._wpSidebarOpen
                                    ? Theme.cPrimary
                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.7)
                                font.pixelSize: 13; font.family: Config.fontFamily
                            }
                            Text {
                                text: "Folder"
                                color: wpPickerOverlay._wpSidebarOpen
                                    ? Theme.cPrimary
                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.7)
                                font.pixelSize: 12; font.family: Config.labelFont
                                font.weight: Font.Medium
                            }
                        }
                    }
                    // Search bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: 30; radius: 20
                        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                       Theme.cInversePrimary.b, 0.12)
                        border.width: 1
                        border.color: wpSearchInput.activeFocus
                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 6
                            Text {
                                text: "󰍉"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.5)
                                font.pixelSize: 13; font.family: Config.fontFamily
                            }
                            TextInput {
                                id: wpSearchInput
                                Layout.fillWidth: true
                                color: Theme.cPrimary
                                font.family: Config.labelFont
                                font.pixelSize: 12
                                verticalAlignment: TextInput.AlignVCenter
                                clip: true
                                text: wpPickerOverlay._wpSearchText
                                onTextChanged: wpPickerOverlay._wpSearchText = text
                                Keys.onEscapePressed: {
                                    wpPickerOverlay._wpSearchText = ""
                                    wpSearchInput.deselect()
                                    wpPickerOverlay.close()
                                }
                                focus: true
                            }
                            Text {
                                visible: wpPickerOverlay._wpSearchText !== ""
                                text: "󰅖"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
                                font.pixelSize: 14; font.family: Config.fontFamily
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        wpPickerOverlay._wpSearchText = ""
                                        wpSearchInput.forceActiveFocus()
                                    }
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: wpSearchInput.forceActiveFocus()
                        }
                    }
                    // Close button
                    Rectangle {
                        width: 26; height: 26; radius: 13
                        color: wpCloseHov.containsMouse
                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.07)
                        Text {
                            anchors.centerIn: parent; text: "󰅙"
                            font.family: Config.fontFamily; font.pixelSize: 14
                            color: Theme.cPrimary
                        }
                        MouseArea {
                            id: wpCloseHov; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: wpPickerOverlay.close()
                        }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }

                // Separator
                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.25)
                }

                // Hint when no folder selected
                Text {
                    visible: wpPickerOverlay._wpCurrentDir === ""
                    text: "Open  Folder  to choose an image directory, then click any image to set it as your user icon."
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                    font.family: Config.labelFont; font.pixelSize: 12
                    wrapMode: Text.Wrap; Layout.fillWidth: true
                }

                // Thumbnail grid with clean scrollbar
                Flickable {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: wpGrid.implicitHeight + 12
                    clip: true; boundsBehavior: Flickable.StopAtBounds
                    ScrollBar.vertical: ScrollBar {
                        policy: ScrollBar.AsNeeded
                        width: 6
                        padding: 4
                        contentItem: Rectangle {
                            implicitWidth: 4; radius: 2
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        background: Rectangle { color: "transparent" }
                    }
                    Grid {
                        id: wpGrid
                        width: parent.width
                        columns: Math.max(2, Math.floor(parent.width / 155))
                        spacing: 7
                        anchors { left: parent.left; top: parent.top; topMargin: 4 }

                        Repeater {
                            model: wpPickerOverlay._filtered
                            delegate: Item {
                                id: wpThumbItem
                                required property string modelData
                                required property int    index
                                width:  (wpGrid.width - wpGrid.spacing * (wpGrid.columns - 1)) / wpGrid.columns
                                height: width * 0.625
                                property string thumbSrc: ""
                                property bool _isFocused: index === wpPickerOverlay._focusedIdx

                                Component.onCompleted: wpPickerOverlay.thumbRequest(modelData)
                                Connections {
                                    target: wpPickerOverlay
                                    function onThumbReady(origPath, src) {
                                        if (origPath === wpThumbItem.modelData)
                                            wpThumbItem.thumbSrc = src
                                    }
                                }

                                // Floating animation for focused image
                                Behavior on scale {
                                    NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
                                }
                                scale: wpThumbItem._isFocused ? 1.06 : 1.0
                                z: wpThumbItem._isFocused ? 10 : 0

                                Rectangle {
                                    anchors.fill: parent; radius: 10
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                   Theme.cInversePrimary.b, 0.18)
                                    border.width: wpItemHov.containsMouse || wpThumbItem._isFocused ? 2 : 1
                                    border.color: wpItemHov.containsMouse || wpThumbItem._isFocused
                                        ? Theme.cPrimary
                                        : Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
                                    clip: true
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    // Thumbnail from magick cache
                                    Image {
                                        anchors.fill: parent
                                        source: wpThumbItem.thumbSrc
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true; mipmap: true; asynchronous: true
                                        cache: false
                                        visible: status === Image.Ready && wpThumbItem.thumbSrc !== ""
                                    }
                                    // Placeholder while generating - fixed radius
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: Qt.rgba(Theme.cBackground.r, Theme.cBackground.g,
                                                       Theme.cBackground.b, 0.5)
                                        visible: parent.children[0].status !== Image.Ready
                                              || wpThumbItem.thumbSrc === ""
                                        Text {
                                            anchors.centerIn: parent
                                            text: "󰋩"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.3)
                                            font.pixelSize: 22; font.family: Config.fontFamily
                                        }
                                    }
                                    // Filename on hover - clipped to thumbnail bounds
                                    Rectangle {
                                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                                        height: wpItemHov.containsMouse ? 22 : 0
                                        color: Qt.rgba(0, 0, 0, 0.55)
                                        radius: 0
                                        clip: true
                                        Behavior on height { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                                        Text {
                                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                                            text: wpThumbItem.modelData.split('/').pop()
                                            color: "#ffffff"; font.pixelSize: 10
                                            elide: Text.ElideRight; verticalAlignment: Text.AlignVCenter
                                            width: parent.width - 12
                                        }
                                    }
                                }
                                MouseArea {
                                    id: wpItemHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        _wpAsIcon.command = [scriptDir+"/set-user-icon.sh", wpThumbItem.modelData]
                                        _wpAsIcon.running = true
                                        wpPickerOverlay.close()
                                    }
                                }
                            }
                        }
                    }

                    // Empty / loading state
                    Item {
                        anchors.fill: parent
                        visible: wpPickerOverlay._wallpapers.length === 0
                        Column {
                            anchors.centerIn: parent; spacing: 10
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: wpScanProc.running ? "󰑪"
                                    : wpPickerOverlay._wpCurrentDir ? "󰋩" : "󰉋"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.35)
                                font.pixelSize: 44; font.family: Config.fontFamily
                                RotationAnimator on rotation {
                                    from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                                    running: wpScanProc.running
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: wpScanProc.running ? "Scanning…"
                                    : wpPickerOverlay._wpCurrentDir ? "No images found"
                                    : "Open a folder to browse images"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                font.pixelSize: 13; font.family: Config.labelFont
                            }
                        }
                    }
                }
            }
        }

        // FocusScope for keyboard navigation and search management
        FocusScope {
            visible: wpPickerOverlay.visible
            Keys.onEscapePressed: wpPickerOverlay.close()
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
            "mkdir -p \"$HOME/.config/hyprcandy\" && " +
            "f=$(zenity --file-selection --file-filter='Images | *.png *.jpg *.jpeg *.webp' 2>/dev/null) && " +
            "[ -n \"$f\" ] && " +
            "magick \"$f\" -resize 96x96^ -gravity center -extent 96x96 " +
            "  \\( +clone -alpha extract -fill black -colorize 100 " +
            "     -fill white -draw 'circle 48,48 48,0' \\) " +
            "  -alpha off -compose CopyOpacity -composite -strip " +
            "  \"$HOME/.config/hyprcandy/user-icon.png\""]
        running: false
        onExited: {
            userImg.source = ""
            userImg.source = "file://" + Quickshell.env("HOME") + "/.config/hyprcandy/user-icon.png?" + Date.now()
        }
    }

    Process {
        id: _wpApply
        running: false
    }

    Process {
        id: _wpAsIcon
        running: false
        onExited: {
            // Refresh CC user icon display
            userImg.source = ""
            userImg.source = "file://" + Quickshell.env("HOME") + "/.config/hyprcandy/user-icon.png?" + Date.now()
        }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  Reusable components
    // ═══════════════════════════════════════════════════════════════════════

    // ── Scrollable pane — invisible scrollbar ────────────────────────────
    component CCScrollPane: Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        contentWidth: width
        contentHeight: _scrollContent.implicitHeight + 20
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // Invisible scrollbar so it doesn't block slider values
        ScrollBar.vertical: ScrollBar {
            policy: ScrollBar.AsNeeded
            contentItem: Rectangle {
                implicitWidth: 0
                color: "transparent"
            }
            background: Rectangle { color: "transparent" }
        }
        default property alias scrollContent: _scrollContent.data
        ColumnLayout {
            id: _scrollContent
            width: parent.width - 10
            anchors { left: parent.left; leftMargin: 4; top: parent.top; topMargin: 10 }
            spacing: 0
        }
    }

    // ── Section heading ──────────────────────────────────────────────────
    component CCSection: RowLayout {
        property alias text: _sh.text
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 4
        Text {
            id: _sh
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: 12
            font.weight: Font.Bold
            font.letterSpacing: 0.5
        }
        Rectangle {
            Layout.fillWidth: true; height: 1
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
        }
    }

    // ── Slider — exact match to startmenu SliderBg ───────────────────────
    //   Trough: 14px tall, innerH=8px, rounded border outline
    //   Fill:   inversePrimary→onPrimary gradient (horizontal)
    //   Thumb:  󰟃 dot-circle glyph
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
        spacing: 8

        Text {
            id: _lbl
            Layout.preferredWidth: 100
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 13
            elide: Text.ElideRight
        }

        // Trough item — matches startmenu SliderBg exactly
        Item {
            id: _trough
            Layout.fillWidth: true
            height: 22

            readonly property int tH: 14
            readonly property int pad: 3
            readonly property int iH: tH - pad * 2
            readonly property real norm: _ccsl.to > _ccsl.from
                ? Math.max(0, Math.min(1, (_ccsl.value - _ccsl.from) / (_ccsl.to - _ccsl.from)))
                : 0

            Item {
                y: (_trough.height - _trough.tH) / 2
                width: parent.width; height: _trough.tH

                // Trough background
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

                // Dot-glyph thumb (󰟃) — matches startmenu
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

        // Value readout — fixed width so slider doesn't jump
        Text {
            Layout.preferredWidth: 40
            text: _ccsl.decimals > 0
                ? _ccsl.value.toFixed(_ccsl.decimals)
                : Math.round(_ccsl.value).toString()
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 12
            horizontalAlignment: Text.AlignRight
        }
    }

    // ── Toggle ───────────────────────────────────────────────────────────
    component CCToggle: RowLayout {
        property alias label: _tl.text
        property bool  value: false
        signal toggled(bool v)

        Layout.fillWidth: true; spacing: 8

        Text {
            id: _tl
            Layout.preferredWidth: 130
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 13
            elide: Text.ElideRight
        }

        Item { Layout.fillWidth: true }

        // iOS-style pill toggle
        Rectangle {
            id: _pill
            width: 46; height: 26; radius: 13
            color: value
                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.9)
                : Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.35)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                  Theme.cPrimary.b, value ? 0.6 : 0.2)

            Rectangle {
                width: 20; height: 20; radius: 10
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

    // ── Segmented control ────────────────────────────────────────────────
    component CCSegmented: RowLayout {
        id: _sgRoot
        property alias label: _sgl.text
        property var   options: []
        property string current: ""
        signal picked(string v)

        Layout.fillWidth: true; spacing: 8

        Text {
            id: _sgl
            Layout.preferredWidth: 100
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 13
            elide: Text.ElideRight
        }

        Rectangle {
            Layout.preferredWidth: Math.min(360, options.length * 88)
            height: 28; radius: 9
            color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                           Theme.cInversePrimary.b, 0.12)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                  Theme.cPrimary.b, 0.18)

            Row {
                anchors.fill: parent; anchors.margins: 2; spacing: 2
                Repeater {
                    model: options
                    delegate: Rectangle {
                        required property string modelData
                        property bool _isCurrent: _sgRoot.current === modelData
                        width: (parent.width - (options.length - 1) * 2) / options.length
                        height: parent.height; radius: 7
                        color: _isCurrent
                            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                      Theme.cInversePrimary.b, 0.82)
                            : "transparent"
                        border.width: _isCurrent ? 1 : 0
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                              Theme.cPrimary.b, 0.45)

                        Text {
                            anchors.centerIn: parent
                            text: modelData; color: Theme.cPrimary
                            font.family: Config.labelFont; font.pixelSize: 12
                            font.weight: _isCurrent === true ? 600 : 400
                        }
                        MouseArea {
                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: _sgRoot.picked(modelData)
                        }
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                }
            }
        }
    }

    // ── Pill button ──────────────────────────────────────────────────────
    component CCPillBtn: Rectangle {
        id: _pb
        property alias text: _pbt.text
        property bool  active: false
        signal clicked()

        implicitWidth: _pbt.implicitWidth + 22
        implicitHeight: 30; radius: 9
        color: active
            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                      Theme.cInversePrimary.b, 0.82)
            : (pbma.containsMouse
                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.38)
                : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                          Theme.cInversePrimary.b, 0.16))
        border.width: 1
        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                              Theme.cPrimary.b, active ? 0.55 : 0.2)

        Text {
            id: _pbt; anchors.centerIn: parent
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 12
        }
        MouseArea {
            id: pbma; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: _pb.clicked()
        }
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    // ── Icon / glyph text entry ──────────────────────────────────────────
    component CCIconEntry: RowLayout {
        property alias label: _iel.text
        property string value: ""
        signal applied(string v)

        Layout.fillWidth: true; spacing: 8

        Text {
            id: _iel
            Layout.preferredWidth: 100
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 13
            elide: Text.ElideRight
        }
        Text {
            text: value !== "" ? value : "—"
            font.family: Config.fontFamily; font.pixelSize: 18
            color: Theme.cPrimary; Layout.preferredWidth: 24
            horizontalAlignment: Text.AlignHCenter
        }
        Rectangle {
            Layout.preferredWidth: 160; height: 28; radius: 7
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
            TextInput {
                anchors { fill: parent; margins: 6 }
                text: value; color: Theme.cPrimary
                font.family: Config.labelFont; font.pixelSize: 12
                verticalAlignment: TextInput.AlignVCenter; clip: true
                onAccepted: applied(text)
                onEditingFinished: applied(text)
            }
        }
    }

    // ── Text entry row ───────────────────────────────────────────────────
    component CCEntryRow: RowLayout {
        property alias label: _erl.text
        property string value: ""
        signal applied(string val)

        Layout.fillWidth: true; spacing: 8

        Text {
            id: _erl
            Layout.preferredWidth: 100
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 13
            elide: Text.ElideRight
        }
        Rectangle {
            Layout.preferredWidth: 180; height: 28; radius: 7
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.06)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
            TextInput {
                anchors { fill: parent; margins: 6 }
                text: value
                color: Theme.cPrimary
                font.family: Config.labelFont; font.pixelSize: 12
                verticalAlignment: TextInput.AlignVCenter; clip: true
                onAccepted: applied(text)
            }
        }
    }

    // ── Color picker (matugen palette swatches) ──────────────────────────
    component CCColorPicker: ColumnLayout {
        id: _cpRoot
        property alias label:        _cpl.text
        property color currentColor: Theme.cPrimary
        property bool  pickerEnabled: true
        signal colorPicked(color picked)

        Layout.fillWidth: true; spacing: 4
        opacity: pickerEnabled ? 1.0 : 0.4

        RowLayout {
            Layout.fillWidth: true
            Text {
                id: _cpl; Layout.preferredWidth: 100
                color: Theme.cPrimary
                font.family: Config.labelFont; font.pixelSize: 13
            }
            Rectangle {
                width: 24; height: 16; radius: 5
                color: _cpRoot.currentColor
                border.width: 1
                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                      Theme.cPrimary.b, 0.4)
            }
            Text {
                text: _cpRoot.currentColor.toString().toUpperCase()
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                               Theme.cPrimary.b, 0.55)
                font.family: Config.labelFont; font.pixelSize: 10
            }
        }

        Flow {
            Layout.fillWidth: true; spacing: 5
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
                    width: 22; height: 22; radius: 5
                    color: modelData
                    border.width: _cpRoot.currentColor.toString() === modelData.toString() ? 2 : 0
                    border.color: Theme.cPrimary
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (_cpRoot.pickerEnabled) {
                                _cpRoot.currentColor = modelData
                                _cpRoot.colorPicked(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
}
