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
    property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop  - 8) : Config.outerMarginTop + 4) + Config.barHeight
    property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom - 8) : Config.outerMarginBottom + 4) + Config.barHeight
    property real   _sideMargin:  Config.outerMarginSide

    // ── Scripts directory
    readonly property string scriptDir: Quickshell.env("HOME") + "/.config/quickshell/bar/scripts"

    // ── Dock current values (read from config.js on open) ─────────────────
    property string _dockSpacingVal:    "0"
    property string _dockPaddingVal:    "0"
    property string _dockBorderWVal:    "2"
    property string _dockBorderTLVal:   "20"
    property string _dockBorderTRVal:   "20"
    property string _dockBorderBLVal:   "20"
    property string _dockBorderBRVal:   "20"
    property string _dockBorderColorVar: "on_secondary"
    property string _dockIconSizeVal:   "24"
    property string _dockStartIconVal:  ""
    property string _dockRectBgStyle:   "glass"
    // Auto-hide + layer + margin — bar values come from Config directly;
    // dock values still need _confReadProc since GJS is a separate process
    property bool   _barAhEnabled:  Config.barAutoHide
    property string _barAhDelay:    Config.barAutoHideDelay.toString()
    property bool   _dockAhEnabled: Config.dockAutoHide
    property string _dockAhDelay:   Config.dockAutoHideDelay.toString()
    property int    _dockMarginVal: Config.dockMargin

    // ── Rofi current values ───────────────────────────────────────────────
    property string _rofiBorderVal:  "2"
    property string _rofiRadiusVal:  "1.0"

    // ── App Launcher (launcher-config.state) current values ───────────────
    property string _lcIconSizeVal:       "48"
    property string _lcTextFontSizeVal:   "11"
    property string _lcFixedTileWVal:     "90"
    property string _lcFixedTileHVal:     "78"
    property string _lcFrameWidthVal:     "500"
    property string _lcFrameHeightVal:    "480"
    property string _lcFrameWVertVal:     "380"
    property string _lcFrameHVertVal:     "560"
    property string _lcBorderRadiusVal:   "20"
    property string _lcBorderWidthVal:    "2"
    property string _lcSearchRadiusVal:   "12"
    property string _lcListRadiusVal:     "12"
    property string _lcInnerBorderWVal:   "1"
    property string _lcInnerPaddingVal:   "10"
    property string _lcSearchFracVal:     "1.0"

    // ── SDDM current values ───────────────────────────────────────────────
    property string _sddmHeaderVal:  "󰫣󰫣󰫣"
    property string _sddmFormVal:    "center"
    property string _sddmBlurVal:    "55"
    property string _sddmWidthVal:   ""
    property string _sddmHeightVal:  ""
    property string _sddmFontVal:    ""

    // ── Hyprland entry values ─────────────────────────────────────────────
    property string _opacEntryVal:       ""
    property string _blurSizeEntryVal:   ""
    property string _blurPassesEntryVal: ""
    property string _gapsInnerEntryVal:  ""
    property string _gapsOuterEntryVal:  ""
    property string _borderWEntryVal:    ""
    property string _borderREntryVal:    ""
    property string _currentLayout:      ""   // "scrolling" | "dwindle" | "master" | "monocle"
    property string _kbLayout:           ""   // keyboard layout — empty until first user entry

    // ── Hyprland slider real-number backing (used by CCSlider; seeded from
    //    hyprcandy-bar.conf [hyprland] on open, or Config.hyprDefault* if unset) ──
    property real _hyprOpacSlider:    -1   // -1 = not yet loaded from state file
    property real _winBgAlpha:       -1   // -1 = not yet read from gtk template
    property int  _hyprBlurSzSlider:  -1
    property int  _hyprBlurPsSlider:  -1
    property int  _hyprGapsInSlider:  -1
    property int  _hyprGapsOutSlider: -1
    property int  _hyprBorderWSlider: -1
    property int  _hyprBorderRSlider: -1

    // Resolved slider value: state-file value if set, otherwise Config default
    readonly property real hyprOpacVal:    _hyprOpacSlider    >= 0 ? _hyprOpacSlider    : Config.hyprDefaultOpacity
    readonly property int  hyprBlurSzVal:  _hyprBlurSzSlider  >= 0 ? _hyprBlurSzSlider  : Config.hyprDefaultBlurSize
    readonly property int  hyprBlurPsVal:  _hyprBlurPsSlider  >= 0 ? _hyprBlurPsSlider  : Config.hyprDefaultBlurPasses
    readonly property int  hyprGapsInVal:  _hyprGapsInSlider  >= 0 ? _hyprGapsInSlider  : Config.hyprDefaultGapsIn
    readonly property int  hyprGapsOutVal: _hyprGapsOutSlider >= 0 ? _hyprGapsOutSlider : Config.hyprDefaultGapsOut
    readonly property int  hyprBorderWVal: _hyprBorderWSlider >= 0 ? _hyprBorderWSlider : Config.hyprDefaultBorderW
    readonly property int  hyprBorderRVal: _hyprBorderRSlider >= 0 ? _hyprBorderRSlider : Config.hyprDefaultBorderR

    // ── Hyprland border colors ─────────────────────────────────────────────
    property color _activeBorderColor:   Theme.cPrimary
    property color _inactiveBorderColor: Theme.cOnSecondary
    
    // Border color mode: "matugen" | "pywal"
    property string _activeBorderMode: "matugen"
    property string _inactiveBorderMode: "matugen"
    
    // Selected matugen variables for borders
    property string _activeBorderVar: "$source_color"
    property string _inactiveBorderVar: "$background"

    // Selected pywal variables for borders
    property string _activeBorderPywalVar: "$color4"
    property string _inactiveBorderPywalVar: "$color0"

    // Available matugen border variables
    readonly property var _matugenBorderVars: [
        {label: "$source_color", var: "$source_color"},
        {label: "$primary", var: "$primary"},
        {label: "$primary_container", var: "$primary_container"},
        {label: "$primary_fixed_dim", var: "$primary_fixed_dim"},
        {label: "$inverse_primary", var: "$inverse_primary"},
        {label: "$secondary", var: "$secondary"},
        {label: "$secondary_container", var: "$secondary_container"},
        {label: "$secondary_fixed_dim", var: "$secondary_fixed_dim"},
        {label: "$tertiary", var: "$tertiary"},
        {label: "$tertiary_container", var: "$tertiary_container"},
        {label: "$tertiary_fixed_dim", var: "$tertiary_fixed_dim"},
        {label: "$background", var: "$background"},
        {label: "$surface", var: "$surface"},
        {label: "$surface_container", var: "$surface_container"},
        {label: "$outline", var: "$outline"},
        {label: "$outline_variant", var: "$outline_variant"},
        {label: "$on_secondary", var: "$on_secondary"},
        {label: "$scrim", var: "$scrim"}
    ]

    // Available pywal border variables (color0–color15 + foreground/background)
    readonly property var _pywalBorderVars: [
        {label: "$color0",      var: "$color0"},
        {label: "$color1",      var: "$color1"},
        {label: "$color2",      var: "$color2"},
        {label: "$color3",      var: "$color3"},
        {label: "$color4",      var: "$color4"},
        {label: "$color5",      var: "$color5"},
        {label: "$color6",      var: "$color6"},
        {label: "$color7",      var: "$color7"},
        {label: "$color8",      var: "$color8"},
        {label: "$color9",      var: "$color9"},
        {label: "$color10",     var: "$color10"},
        {label: "$color11",     var: "$color11"},
        {label: "$color12",     var: "$color12"},
        {label: "$color13",     var: "$color13"},
        {label: "$color14",     var: "$color14"},
        {label: "$color15",     var: "$color15"},
        {label: "$foreground",  var: "$foreground"},
        {label: "$background",  var: "$background"}
    ]

    // Available wallust border variables (color0–color15)
    readonly property var _wallustBorderVars: [
        {label: "$color0",  var: "$color0"},
        {label: "$color1",  var: "$color1"},
        {label: "$color2",  var: "$color2"},
        {label: "$color3",  var: "$color3"},
        {label: "$color4",  var: "$color4"},
        {label: "$color5",  var: "$color5"},
        {label: "$color6",  var: "$color6"},
        {label: "$color7",  var: "$color7"},
        {label: "$color8",  var: "$color8"},
        {label: "$color9",  var: "$color9"},
        {label: "$color10", var: "$color10"},
        {label: "$color11", var: "$color11"},
        {label: "$color12", var: "$color12"},
        {label: "$color13", var: "$color13"},
        {label: "$color14", var: "$color14"},
        {label: "$color15", var: "$color15"}
    ]

    // Helper: resolve a pywal $varname to a live color via Theme.walColors
    // (Theme.walColors is a JS object populated from ~/.cache/wal/colors-hyprland.conf)
    function _resolvePywalColor(varName) {
        if (typeof Theme.walColors === "object" && Theme.walColors !== null) {
            const key = varName.replace(/^\$/, "")
            const val = Theme.walColors[key]
            if (val) return val
        }
        return Theme.cPrimary
    }

    // Helper: resolve a wallust $colorN to a live color via Theme.wallustColors
    // (Theme.wallustColors is a JS object populated from WallustColors.qml)
    function _resolveWallustColor(varName) {
        if (typeof Theme.wallustColors === "object" && Theme.wallustColors !== null) {
            const key = varName.replace(/^\$/, "")
            const val = Theme.wallustColors[key]
            if (val) return val
        }
        // Fallback to typed cWc* properties when map isn't populated yet
        switch (varName) {
            case "$color0":  return Theme.cWc0
            case "$color1":  return Theme.cWc1
            case "$color2":  return Theme.cWc2
            case "$color3":  return Theme.cWc3
            case "$color4":  return Theme.cWc4
            case "$color5":  return Theme.cWc5
            case "$color6":  return Theme.cWc6
            case "$color7":  return Theme.cWc7
            case "$color8":  return Theme.cWc8
            case "$color9":  return Theme.cWc9
            case "$color10": return Theme.cWc10
            case "$color11": return Theme.cWc11
            case "$color12": return Theme.cWc12
            case "$color13": return Theme.cWc13
            case "$color14": return Theme.cWc14
            case "$color15": return Theme.cWc15
            default:         return Theme.cWc7
        }
    }

    // Helper: resolve a matugen $varname to live Theme color (mirrors Config._cavaThemeColor)
    function _cavaThemeColorLocal(varName) {
        switch (varName) {
            case "$source_color":           return Theme.cPrimary
            case "$primary":                return Theme.cPrimary
            case "$on_primary":             return Theme.cOnPrimary
            case "$primary_container":      return Theme.cPrimaryContainer
            case "$on_primary_container":   return Theme.cOnPrimaryContainer
            case "$primary_fixed":          return Theme.cPrimaryFixed
            case "$primary_fixed_dim":      return Theme.cPrimaryFixedDim
            case "$inverse_primary":        return Theme.cInversePrimary
            case "$secondary":              return Theme.cSecondary
            case "$on_secondary":           return Theme.cOnSecondary
            case "$secondary_container":    return Theme.cSecondaryContainer
            case "$secondary_fixed_dim":    return Theme.cPrimaryFixedDim
            case "$tertiary":               return Theme.cTertiary
            case "$on_tertiary":            return Theme.cOnSurf
            case "$tertiary_container":     return Theme.cTertiaryContainer
            case "$tertiary_fixed_dim":     return Theme.cTertiary
            case "$background":             return Theme.cBackground
            case "$on_background":          return Theme.cOnBackground
            case "$surface":                return Theme.cSurface
            case "$surface_variant":        return Theme.cSurfVariant
            case "$surface_container":      return Theme.cSurfMid
            case "$surface_container_low":  return Theme.cSurfLow
            case "$surface_container_high": return Theme.cSurfHi
            case "$on_surface":             return Theme.cOnSurf
            case "$on_surface_variant":     return Theme.cOnSurfVar
            case "$inverse_surface":        return Theme.cInverseSurface
            case "$outline":                return Theme.cOutline
            case "$outline_variant":        return Theme.cOutVar
            case "$error":                  return Theme.cErr
            case "$scrim":                  return Theme.cScrim
            case "$shadow":                 return Theme.cShadow
            // Wallust colors
            case "$color0":                 return Theme.cWc0
            case "$color1":                 return Theme.cWc1
            case "$color2":                 return Theme.cWc2
            case "$color3":                 return Theme.cWc3
            case "$color4":                 return Theme.cWc4
            case "$color5":                 return Theme.cWc5
            case "$color6":                 return Theme.cWc6
            case "$color7":                 return Theme.cWc7
            case "$color8":                 return Theme.cWc8
            case "$color9":                 return Theme.cWc9
            case "$color10":                return Theme.cWc10
            case "$color11":                return Theme.cWc11
            case "$color12":                return Theme.cWc12
            case "$color13":                return Theme.cWc13
            case "$color14":                return Theme.cWc14
            case "$color15":                return Theme.cWc15
            default:                        return Theme.cPrimary
        }
    }

    // Resolve a "$varname" string → the matching Theme color
    // Used by the cava color pickers to apply matugen vars to Config properties
    // Load dock + rofi + launcher + sddm + hyprland values when CC opens
    Connections {
        target: ControlCenterState
        function onVisibleChanged() {
            if (ControlCenterState.visible) {
                // Force activation tab when not licensed — runs before any
                // other reader so the user always lands on tab 6 first.
                if (!LicenseState.activated) {
                    mainStack.currentIndex = 6
                    ccTabSettings.activeTab = 6
                    return
                }
                _dockValReader.running = true
                _rofiValReader.running = true
                _lcValReader.running   = true
                _sddmValReader.running = true
                _weatherLocReader.running = true
                _hyprlandValReader.running = true
                _layoutReader.running = true
                _hyprStateReader.running = true
                _kbLayoutReader.running  = true
                ccWin._maybereVerify()
            }
        }
    }

    // Kick all readers immediately on component creation (CC uses Loader so
    // Component.onCompleted fires each time the CC opens).
    Component.onCompleted: {
        // Bar autohide state comes from Config — already bound via property defaults above.
        // Run _confReadProc to sync dock values (autohide/layer/margin) from conf file.
        _confReadProc.running      = true
        _hyprlandValReader.running = true
        _layoutReader.running      = true
        _dockValReader.running     = true
        _rofiValReader.running     = true
        _lcValReader.running       = true
        _sddmValReader.running     = true
        _weatherLocReader.running  = true
        _hyprStateReader.running   = true
        _kbLayoutReader.running    = true
        _winBgAlphaReader.running  = true
        // Seed from persisted value immediately; reader overrides only on first-ever launch
        if (ccAppearanceSettings.winBgAlpha > 0)
            ccWin._winBgAlpha = ccAppearanceSettings.winBgAlpha
    }

    // Read hyprland config values
    Process {
        id: _hyprlandValReader
        // Read from the Lua-aware helper. It resolves Control Center state first,
        // then falls back to the migrated/static Hyprland defaults.
        command: ["bash", "-c",
            'h="$HOME/.config/quickshell/bar/scripts/hyprland-lua-state.sh"; ' +
            '"$h" get opacity; ' +
            '"$h" get blur_size; ' +
            '"$h" get blur_passes; ' +
            '"$h" get gaps_in; ' +
            '"$h" get gaps_out; ' +
            '"$h" get border_size; ' +
            '"$h" get rounding; ' +
            '"$h" get active_border; ' +
            '"$h" get inactive_border; ' +
            'hyprctl getoption general:layout -j 2>/dev/null | grep -oP "(?<=\\\"str\\\": \\\")[^\\\"]+" || ' +
            'hyprctl getoption general:layout 2>/dev/null | awk "/^str:/{print \\$2}"']
        running: false
        property string _output: ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _hyprlandValReader._output += l.trim() + "\n" }
        }
        Component.onCompleted: {
            // Restore persisted border colors and modes on startup
            if (ccBorderColorSettings.activeBorderMode !== "")
                ccWin._activeBorderMode = ccBorderColorSettings.activeBorderMode
            if (ccBorderColorSettings.inactiveBorderMode !== "")
                ccWin._inactiveBorderMode = ccBorderColorSettings.inactiveBorderMode
            if (ccBorderColorSettings.activeBorderVar !== "")
                ccWin._activeBorderVar = ccBorderColorSettings.activeBorderVar
            if (ccBorderColorSettings.inactiveBorderVar !== "")
                ccWin._inactiveBorderVar = ccBorderColorSettings.inactiveBorderVar
            if (ccBorderColorSettings.activeBorderPywalVar !== "")
                ccWin._activeBorderPywalVar = ccBorderColorSettings.activeBorderPywalVar
            if (ccBorderColorSettings.inactiveBorderPywalVar !== "")
                ccWin._inactiveBorderPywalVar = ccBorderColorSettings.inactiveBorderPywalVar
            if (ccBorderColorSettings.activeBorderColor !== "")
                ccWin._activeBorderColor = ccBorderColorSettings.activeBorderColor
            if (ccBorderColorSettings.inactiveBorderColor !== "")
                ccWin._inactiveBorderColor = ccBorderColorSettings.inactiveBorderColor
            // Cava color mode/var/binding now owned by Config — no CC-side restore needed
        }
        onExited: {
            const lines = _output.trim().split("\n")
            _output = ""
            // Only update backing properties — let the text: bindings propagate.
            // Direct TI.text assignments break QML bindings permanently.
            if (lines[0] && lines[0].length > 0) _opacEntryVal       = lines[0]
            if (lines[1] && lines[1].length > 0) _blurSizeEntryVal   = lines[1]
            if (lines[2] && lines[2].length > 0) _blurPassesEntryVal = lines[2]
            if (lines.length > 3) _gapsInnerEntryVal = lines[3] || "0"
            if (lines.length > 4) _gapsOuterEntryVal = lines[4] || "0"
            if (lines.length > 5) _borderWEntryVal   = lines[5] || "0"
            if (lines.length > 6) _borderREntryVal   = lines[6] || "0"
            // Parse border colors — detect matugen/pywal variables or hex colors
            if (lines.length > 7) {
                const activeVal = lines[7] ? lines[7].trim() : ""
                if (activeVal.length > 0) {
                    if (activeVal.startsWith("$color") || activeVal === "$foreground" || activeVal === "$background" && lines[7].indexOf("color") < 0) {
                        // Pywal variable detected (color0-color15, foreground, background from wal)
                        // NOTE: "$background" exists in BOTH _matugenBorderVars and _pywalBorderVars,
                        // so the raw value alone can't tell them apart. Fall back to the last
                        // persisted mode/var to break the tie instead of always assuming matugen.
                        const isPywal = /^\$(color\d+|foreground)$/.test(activeVal) ||
                            (activeVal === "$background" &&
                             ccBorderColorSettings.activeBorderMode === "pywal" &&
                             ccBorderColorSettings.activeBorderPywalVar === "$background")
                        if (isPywal) {
                            ccWin._activeBorderMode = "pywal"
                            ccWin._activeBorderPywalVar = activeVal
                        } else if (activeVal.startsWith("$")) {
                            ccWin._activeBorderMode = "matugen"
                            ccWin._activeBorderVar = activeVal
                        }
                    } else if (activeVal.startsWith("$")) {
                        // Matugen variable detected
                        ccWin._activeBorderMode = "matugen"
                        ccWin._activeBorderVar = activeVal
                    } else {
                        // Hex color detected
                        ccWin._activeBorderMode = "matugen"
                        const hex = activeVal.replace(/^#+/, "").replace(/^0x/, "")
                        if (hex.startsWith("ff") && hex.length === 8) {
                            ccWin._activeBorderColor = "#" + hex.substring(2)
                        } else if (hex.length === 8) {
                            ccWin._activeBorderColor = "#" + hex
                        } else {
                            ccWin._activeBorderColor = "#" + hex
                        }
                    }
                }
            }
            if (lines.length > 8) {
                const inactiveVal = lines[8] ? lines[8].trim() : ""
                if (inactiveVal.length > 0) {
                    // NOTE: "$background" exists in BOTH _matugenBorderVars and _pywalBorderVars
                    // (and is the DEFAULT matugen var for inactive border, see _inactiveBorderVar),
                    // so a raw value of "$background" is inherently ambiguous — the regex alone
                    // can't tell whether it came from matugen or pywal. Fall back to the last
                    // persisted mode/var to break the tie instead of always assuming matugen,
                    // which is what was causing pywal's "$background" selection to keep
                    // reverting to matugen every time the panel re-read the config.
                    const isPywal = /^\$(color\d+|foreground)$/.test(inactiveVal) ||
                        (inactiveVal === "$background" &&
                         ccBorderColorSettings.inactiveBorderMode === "pywal" &&
                         ccBorderColorSettings.inactiveBorderPywalVar === "$background")
                    if (isPywal) {
                        ccWin._inactiveBorderMode = "pywal"
                        ccWin._inactiveBorderPywalVar = inactiveVal
                    } else if (inactiveVal.startsWith("$")) {
                        // Matugen variable detected
                        ccWin._inactiveBorderMode = "matugen"
                        ccWin._inactiveBorderVar = inactiveVal
                    } else {
                        // Hex color detected
                        ccWin._inactiveBorderMode = "matugen"
                        const hex = inactiveVal.replace(/^#+/, "").replace(/^0x/, "")
                        if (hex.startsWith("ff") && hex.length === 8) {
                            ccWin._inactiveBorderColor = "#" + hex.substring(2)
                        } else if (hex.length === 8) {
                            ccWin._inactiveBorderColor = "#" + hex
                        } else {
                            ccWin._inactiveBorderColor = "#" + hex
                        }
                    }
                }
            }
            // Parse current layout (line 9 — from hyprctl getoption or grep fallback)
            if (lines.length > 9 && lines[9] && lines[9].trim().length > 0)
                ccWin._currentLayout = lines[9].trim().toLowerCase()
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
            "grep -oP 'borderTopLeftRadius:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP 'borderTopRightRadius:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP 'borderBottomLeftRadius:\\s*\\K[0-9]+' \"$f\" | head -1; " +
            "grep -oP 'borderBottomRightRadius:\\s*\\K[0-9]+' \"$f\" | head -1; " +
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
            const fallbackR   = (ls[3] !== undefined && ls[3]) ? ls[3] : "20"
            _dockBorderTLVal  = (ls[4] !== undefined && ls[4]) ? ls[4] : fallbackR
            _dockBorderTRVal  = (ls[5] !== undefined && ls[5]) ? ls[5] : fallbackR
            _dockBorderBLVal  = (ls[6] !== undefined && ls[6]) ? ls[6] : fallbackR
            _dockBorderBRVal  = (ls[7] !== undefined && ls[7]) ? ls[7] : fallbackR
            _dockIconSizeVal  = (ls[8] !== undefined && ls[8]) ? ls[8] : "24"
            _dockStartIconVal = (ls[9] !== undefined && ls[9]) ? ls[9] : ""
        }
    }
    // ── Shared conf writer for hyprcandy-bar.conf ────────────────────────────
    // All auto-hide and layer writes funnel through this single Process.
    // The caller sets _cmd then starts the process.  If a write is already
    // in-flight, _pendingCmd captures the latest command; it is launched
    // immediately when the current run finishes so no slider value is lost.
    Process {
        id: _confWriteProc
        property string _cmd: ""
        property string _pendingCmd: ""
        command: ["bash", "-c", _confWriteProc._cmd]
        onExited: {
            running = false
            if (_pendingCmd !== "") {
                _cmd = _pendingCmd
                _pendingCmd = ""
                running = true
            }
        }
    }

    // ── Read hyprcandy-bar.conf on CC open ────────────────────────────────────
    Process {
        id: _confReadProc
        command: ["bash", "-c",
            "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
            "[ -f \"$f\" ] || exit 0; " +
            "awk '/^\\[bar\\]/{s=1;next} /^\\[/{s=0} s&&/^autohide=/{print \"BAR_AH=\"$0} s&&/^autohide_delay=/{print \"BAR_DELAY=\"$0}' \"$f\"; " +
            "awk '/^\\[dock\\]/{s=1;next} /^\\[/{s=0} s&&/^autohide=/{print \"DOCK_AH=\"$0} s&&/^autohide_delay=/{print \"DOCK_DELAY=\"$0} s&&/^margin_from_edge=/{print \"DOCK_MARGIN=\"$0}' \"$f\""]
        running: false
        stdout: SplitParser {
            splitMarker: "
"
            onRead: function(l) {
                const kv = l.trim()
                // Bar autohide is now owned by Config.qml — skip BAR_* keys
                if      (kv.startsWith("DOCK_AH=autohide="))         { ccWin._dockAhEnabled = kv.slice(17) === "true";  Config.dockAutoHide      = ccWin._dockAhEnabled }
                else if (kv.startsWith("DOCK_DELAY=autohide_delay=")) { ccWin._dockAhDelay   = kv.slice(26);            Config.dockAutoHideDelay = parseInt(kv.slice(26)) || 5 }
                else if (kv.startsWith("DOCK_MARGIN=margin_from_edge=")){ ccWin._dockMarginVal = parseInt(kv.slice(29)) || 6; Config.dockMargin = ccWin._dockMarginVal }
            }
        }
    }

    // ── Read [hyprland] slider values from hyprcandy-bar.conf ────────────────
    // Values written here take priority over Config.hyprDefault* fallbacks.
    Process {
        id: _hyprStateReader
        command: ["bash", "-c",
            "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
            "[ -f \"$f\" ] || exit 0; " +
            "awk '/^\\[hyprland\\]/{s=1;next} /^\\[/{s=0} s{print}' \"$f\""]
        running: false
        property string _buf: ""
        onRunningChanged: if (running) _buf = ""
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _hyprStateReader._buf += l.trim() + "\n" }
        }
        onExited: {
            const lines = _buf.trim().split("\n")
            _buf = ""
            for (const line of lines) {
                const eq = line.indexOf("=")
                if (eq < 0) continue
                const k = line.slice(0, eq).trim()
                const v = line.slice(eq + 1).trim()
                if      (k === "opacity")     { const f = parseFloat(v); if (!isNaN(f)) ccWin._hyprOpacSlider    = f }
                else if (k === "blur_size")   { const i = parseInt(v);   if (!isNaN(i)) ccWin._hyprBlurSzSlider  = i }
                else if (k === "blur_passes") { const i = parseInt(v);   if (!isNaN(i)) ccWin._hyprBlurPsSlider  = i }
                else if (k === "gaps_in")     { const i = parseInt(v);   if (!isNaN(i)) ccWin._hyprGapsInSlider  = i }
                else if (k === "gaps_out")    { const i = parseInt(v);   if (!isNaN(i)) ccWin._hyprGapsOutSlider = i }
                else if (k === "border_size") { const i = parseInt(v);   if (!isNaN(i)) ccWin._hyprBorderWSlider = i }
                else if (k === "rounding")    { const i = parseInt(v);   if (!isNaN(i)) ccWin._hyprBorderRSlider = i }
                else if (k === "kb_layout"  ) { if (v.length > 0) ccWin._kbLayout = v }
            }
        }
    }

    // ── Read kb_layout from Lua-aware Hyprland state/defaults ─
    Process {
        id: _kbLayoutReader
        command: ["bash", "-c",
            "h=\"$HOME/.config/quickshell/bar/scripts/hyprland-lua-state.sh\"; " +
            "[ -x \"$h\" ] && \"$h\" get kb_layout"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const v = l.trim()
                // Only populate if state file has not set a layout yet
                if (ccWin._kbLayout === "" && v.length > 0)
                    ccWin._kbLayout = v
            }
        }
    }

    // Reads current alpha from gtk4 matugen template so the slider seeds correctly on open.
    Process {
        id: _winBgAlphaReader
        command: ["bash", "-c",
            "grep -oP '(?<=alpha\\(@on_secondary, )\\d+\\.?\\d*(?=\\))'" +
            " \"$HOME/.config/matugen/templates/gtk4.css\" 2>/dev/null | head -1"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const f = parseFloat(l.trim())
                if (!isNaN(f)) ccWin._winBgAlpha = Math.round(f * 20) / 20
            }
        }
        onExited: running = false
    }

    // ── Write one key=value into hyprcandy-bar.conf [hyprland] section ───────
    // Caller sets _key and _val then sets running = true.
    // Uses the same queue pattern as _confWriteProc.
    Process {
        id: _hyprStateWriter
        property string _key: ""
        property string _val: ""
        property string _pendingKey: ""
        property string _pendingVal: ""
        command: ["bash", "-c",
            "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
            "mkdir -p \"$(dirname \"$f\")\"; " +
            // Create file + section if missing
            "grep -q '^\\[hyprland\\]' \"$f\" 2>/dev/null || echo -e '\\n[hyprland]' >> \"$f\"; " +
            // Replace existing key or append under section
            "if grep -q '^" + _hyprStateWriter._key + "=' \"$f\" 2>/dev/null; then " +
            "  sed -i 's|^" + _hyprStateWriter._key + "=.*|" + _hyprStateWriter._key + "=" + _hyprStateWriter._val + "|' \"$f\"; " +
            "else " +
            "  sed -i '/^\\[hyprland\\]/a " + _hyprStateWriter._key + "=" + _hyprStateWriter._val + "' \"$f\"; " +
            "fi"]
        running: false
        onExited: {
            running = false
            if (_pendingKey !== "") {
                _key = _pendingKey; _val = _pendingVal
                _pendingKey = ""; _pendingVal = ""
                running = true
            }
        }
    }

    // Helper: write a hyprland value to both hyprcandy-bar.conf and hyprviz-state.lua.
    // The helper preserves the legacy CC state file while rendering Lua overrides.
    function _writeHyprState(key, val) {
        const safeVal = String(val).replace(/'/g, "'\\''")
        const cmd = "h=\"$HOME/.config/quickshell/bar/scripts/hyprland-lua-state.sh\"; " +
            "[ -x \"$h\" ] && \"$h\" set " + key + " '" + safeVal + "' >/dev/null"
        if (_confWriteProc.running) {
            _confWriteProc._pendingCmd = cmd
        } else {
            _confWriteProc._cmd = cmd
            _confWriteProc.running = true
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
    // Read launcher config directly from launcherConfig.js — the single source
    // of truth. No state file detour: whatever launcherConfig.js holds is what
    // the sliders show, and launcher-config-set.sh writes back into that same file.
    Process {
        id: _lcValReader
        command: ["bash", "-c",
            'lc="$HOME/.hyprcandy/GJS/hyprcandydock/launcherConfig.js"; ' +
            '[ -f "$lc" ] || { echo "{}"; exit 0; }; ' +
            'python3 -c \'' +
            'import re, json, sys\n' +
            't = open(sys.argv[1]).read()\n' +
            'keys = [\n' +
            '  "searchWidthFraction",\n' +
            '  "iconSize",\n' +
            '  "textFontSize",\n' +
            '  "fixedTileWidth",\n' +
            '  "fixedTileHeight",\n' +
            '  "frameWidth",\n' +
            '  "frameHeight",\n' +
            '  "frameWidthVert",\n' +
            '  "frameHeightVert",\n' +
            '  "borderRadius",\n' +
            '  "borderWidth",\n' +
            '  "searchRadius",\n' +
            '  "listRadius",\n' +
            '  "innerBorderWidth",\n' +
            '  "innerPadding",\n' +
            ']\n' +
            'obj = {}\n' +
            'for k in keys:\n' +
            '  m = re.search(rf"\\b{k}:\\s*([0-9][0-9.]*)", t)\n' +
            '  if m: obj[k] = float(m.group(1)) if "." in m.group(1) else int(m.group(1))\n' +
            'print(json.dumps(obj))\n' +
            '\' "$lc"']
        running: false
        // _buf MUST be reset to "" before each run so stale output from a
        // previous CC open cannot corrupt the JSON.parse on the next open.
        property string _buf: ""
        onRunningChanged: { if (running) _buf = "" }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _lcValReader._buf += l }
        }
        onExited: {
            try {
                const obj = JSON.parse(_lcValReader._buf)
                if (obj.searchWidthFraction !== undefined) _lcSearchFracVal   = obj.searchWidthFraction.toFixed(2)
                if (obj.iconSize            !== undefined) _lcIconSizeVal     = Math.round(obj.iconSize).toString()
                if (obj.textFontSize        !== undefined) _lcTextFontSizeVal = Math.round(obj.textFontSize).toString()
                if (obj.fixedTileWidth      !== undefined) _lcFixedTileWVal   = Math.round(obj.fixedTileWidth).toString()
                if (obj.fixedTileHeight     !== undefined) _lcFixedTileHVal   = Math.round(obj.fixedTileHeight).toString()
                if (obj.frameWidth          !== undefined) _lcFrameWidthVal   = Math.round(obj.frameWidth).toString()
                if (obj.frameHeight         !== undefined) _lcFrameHeightVal  = Math.round(obj.frameHeight).toString()
                if (obj.frameWidthVert      !== undefined) _lcFrameWVertVal   = Math.round(obj.frameWidthVert).toString()
                if (obj.frameHeightVert     !== undefined) _lcFrameHVertVal   = Math.round(obj.frameHeightVert).toString()
                if (obj.borderRadius        !== undefined) _lcBorderRadiusVal = Math.round(obj.borderRadius).toString()
                if (obj.borderWidth         !== undefined) _lcBorderWidthVal  = Math.round(obj.borderWidth).toString()
                if (obj.searchRadius        !== undefined) _lcSearchRadiusVal = Math.round(obj.searchRadius).toString()
                if (obj.listRadius          !== undefined) _lcListRadiusVal   = Math.round(obj.listRadius).toString()
                if (obj.innerBorderWidth    !== undefined) _lcInnerBorderWVal = Math.round(obj.innerBorderWidth).toString()
                if (obj.innerPadding        !== undefined) _lcInnerPaddingVal = Math.round(obj.innerPadding).toString()
            } catch(e) { console.warn("[CC] _lcValReader: JSON parse failed:", e, "buf:", _lcValReader._buf) }
            _lcValReader._buf = ""
        }
    }
    // Individual SDDM value readers — mirror the dock pattern so each field
    // reads directly from theme.conf (world-readable, no sudo needed) and
    // updates its property independently before the TextInput renders.
    Process {
        id: _sddmValReader
        command: ["bash", "-c", "true"]   // kept so existing _sddmValReader.running = true calls are harmless
        running: false
    }
    Process {
        id: _sddmReadHeader
        command: ["bash", "-c",
            "sd=\"$HOME/.config/hyprcandy\"; " +
            "[ -f \"$sd/sddm_header.state\" ] && cat \"$sd/sddm_header.state\" || " +
            "  grep -oP '^HeaderText=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | sed -e 's/^\"//' -e 's/\"$//' | head -1"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { const v = l.trim(); if (v) _sddmHeaderVal = v }
        }
    }
    Process {
        id: _sddmReadForm
        command: ["bash", "-c",
            "sd=\"$HOME/.config/hyprcandy\"; " +
            "[ -f \"$sd/sddm_form.state\" ] && cat \"$sd/sddm_form.state\" || " +
            "  grep -oP '^FormPosition=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | sed -e 's/^\"//' -e 's/\"$//' | head -1"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { const v = l.trim(); if (v) _sddmFormVal = v }
        }
    }
    Process {
        id: _sddmReadBlur
        command: ["bash", "-c",
            "sd=\"$HOME/.config/hyprcandy\"; " +
            "[ -f \"$sd/sddm_blur.state\" ] && cat \"$sd/sddm_blur.state\" || " +
            "  grep -oP '^BlurRadius=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | sed -e 's/^\"//' -e 's/\"$//' | head -1"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { const v = l.trim(); if (v && !isNaN(parseInt(v))) _sddmBlurVal = v }
        }
    }
    Process {
        id: _sddmReadWidth
        command: ["bash", "-c",
            "sd=\"$HOME/.config/hyprcandy\"; " +
            "[ -f \"$sd/sddm_width.state\" ] && cat \"$sd/sddm_width.state\" || " +
            "  grep -oP '^ScreenWidth=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | sed -e 's/^\"//' -e 's/\"$//' | head -1"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { const v = l.trim(); if (v) _sddmWidthVal = v }
        }
    }
    Process {
        id: _sddmReadHeight
        command: ["bash", "-c",
            "sd=\"$HOME/.config/hyprcandy\"; " +
            "[ -f \"$sd/sddm_height.state\" ] && cat \"$sd/sddm_height.state\" || " +
            "  grep -oP '^ScreenHeight=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | sed -e 's/^\"//' -e 's/\"$//' | head -1"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { const v = l.trim(); if (v) _sddmHeightVal = v }
        }
    }
    Process {
        id: _sddmReadFont
        command: ["bash", "-c",
            "sd=\"$HOME/.config/hyprcandy\"; " +
            "[ -f \"$sd/sddm_font.state\" ] && cat \"$sd/sddm_font.state\" || " +
            "  grep -oP '^Font=\\K.*' /usr/share/sddm/themes/sugar-candy/theme.conf 2>/dev/null | sed -e 's/^\"//' -e 's/\"$//' | head -1"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { const v = l.trim(); if (v) _sddmFontVal = v }
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
    // Dock background style writer — called from the Bar:Background switch so both
    // bar and dock rect fill stay in sync from a single control.
    Process {
        id: _dockRectBgWrite
        running: false
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
    // Anchor to bar edge (top or bottom); span full width for click-outside dismiss.
    anchors {
        top:    !_barAtBottom
        bottom:  _barAtBottom
        left:    true
        right:   true
    }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }
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
        property int activeBarSubTab: 0  // Remembered Bar sub-tab (default: General)
        property int activeKbSubTab:  0  // Remembered Keybinds sub-tab (0 = View, 1 = Edit)
    }
    Settings {
        id: ccLocSettings
        category: "cc-weather-loc-v1"
        property string pinnedName: ""
        property double pinnedLat: 0.0
        property double pinnedLon: 0.0
    }
    Settings {
        id: ccBorderColorSettings
        category: "cc-border-colors-v1"
        property string activeBorderColor:        ""
        property string inactiveBorderColor:      ""
        property string activeBorderMode:         "matugen"  // "matugen" | "pywal"
        property string inactiveBorderMode:       "matugen"  // "matugen" | "pywal"
        property string activeBorderVar:          "$source_color"
        property string inactiveBorderVar:        "$background"
        property string activeBorderPywalVar:     "$color4"
        property string inactiveBorderPywalVar:   "$color0"
    }
    Settings {
        id: ccThemeSettings
        category: "cc-theme-v1"
        property string currentTheme: "scheme-content"
    }
    // ── Appearance persistence (window alpha) ─────────────────────────────────
    Settings {
        id: ccAppearanceSettings
        category: "cc-appearance-v1"
        property real winBgAlpha: 1.00
    }
    // ── HyprCandy+ licence persistence ───────────────────────────────────────
    Settings {
        id: ccLicenseSettings
        category: "cc-license-v1"
        property string licenseKey:    ""
        property string licenseStatus: ""
        property string licensedEmail: ""
        property string lastVerified:  ""
    }
    // ── Color generation (matugen + pywal) toggle persistence ────────────────
    Settings {
        id: ccColorRegenSettings
        category: "cc-color-regen-v1"
        property bool colorRegenEnabled: true   // default: live colors on
    }

    property string _licKeyInput:    ccLicenseSettings.licenseKey
    property string _licStatus:      ccLicenseSettings.licenseStatus
    property string _licEmail:       ccLicenseSettings.licensedEmail
    property string _licLastChecked: ccLicenseSettings.lastVerified
    property bool   _licVerifying:   false
    property bool   _licDeactivating: false
    property string _licError:       ""
    // Set true by onStreamFinished so the onExited safety-net timer knows
    // the stream was already handled and should not overwrite the result.
    property bool   _licStreamHandled: false

    function _verifyLicense(key, incrementUses) {
        // Resolve the key: prefer the explicit argument, fall back to the
        // persisted value in Settings so background re-verification and
        // first-time activation both read from the same authoritative source.
        const rawKey = (key && !key.trim().startsWith("●")) ? key.trim()
                     : ccLicenseSettings.licenseKey.trim()
        if (_licVerifying || rawKey === "") return
        const cleanKey = rawKey
        _licVerifying      = true
        _licStreamHandled  = false
        _licError          = ""
        // Persist the key immediately so it survives CC close regardless of
        // verify outcome — background re-verify always reads from conf.
        _licKeyInput = cleanKey
        ccLicenseSettings.licenseKey = cleanKey
        _licVerifyProc.command = [
            scriptDir + "/license-verify.sh",
            cleanKey,
            incrementUses ? "true" : "false"
        ]
        // Always cycle through false first — setting running=true on an
        // already-running process is a no-op in Quickshell.
        _licVerifyProc.running = false
        _licVerifyProc.running = true
    }

    function _maybereVerify() {
        if (ccLicenseSettings.licenseKey === "") return
        if (ccLicenseSettings.licenseStatus !== "active") return
        const last = ccLicenseSettings.lastVerified
        if (!last) { _verifyLicense(ccLicenseSettings.licenseKey, false); return }
        const daysSince = (Date.now() - new Date(last).getTime()) / 86400000
        if (daysSince >= 30) _verifyLicense(ccLicenseSettings.licenseKey, false)
    }

    function _deactivateLicense() {
        const key = ccLicenseSettings.licenseKey.trim()
        if (_licDeactivating || _licVerifying || key === "") return
        _licDeactivating = true
        _licError        = ""
        _licDeactivateProc.command = [
            scriptDir + "/license-deactivate.sh",
            key
        ]
        _licDeactivateProc.running = false
        _licDeactivateProc.running = true
    }

    // ── Gumroad licence verification process ─────────────────────────────────
    // Safety-net timer: fires 500 ms after onExited if onStreamFinished has
    // NOT yet handled the result (e.g. the process was killed before writing
    // anything to stdout). This prevents the spinner from locking up forever
    // without racing against a legitimate successful response.
    Timer {
        id: _licExitedFallback
        interval: 500
        repeat: false
        running: false
        onTriggered: {
            if (ccWin._licVerifying && !ccWin._licStreamHandled) {
                ccWin._licVerifying = false
                ccWin._licError     = "Verification failed — check your connection."
                ccWin._licStatus    = "invalid"
                ccLicenseSettings.licenseStatus = "invalid"
                LicenseState.deactivate()
            }
        }
    }
    Process {
        id: _licVerifyProc
        running: false
        // onExited: only start the deferred fallback timer — do NOT touch
        // licenseStatus here because onStreamFinished fires after onExited
        // in Quickshell and would overwrite whatever we set.
        onExited: function(code, status) {
            if (ccWin._licVerifying)
                _licExitedFallback.restart()
        }
        stdout: StdioCollector {
            onStreamFinished: {
                // Mark stream as handled so the fallback timer is a no-op.
                ccWin._licStreamHandled = true
                _licExitedFallback.stop()
                ccWin._licVerifying = false
                try {
                    const raw = text.trim()
                    const obj = JSON.parse(raw)
                    // Gumroad returns success as a JSON boolean; coerce
                    // defensively in case a future API version sends a string.
                    const ok = (obj.success === true || obj.success === "true")
                    if (ok) {
                        const p = obj.purchase || {}
                        if (p.refunded || p.chargebacked) {
                            ccWin._licStatus = "invalid"
                            ccWin._licError  = "Purchase was refunded or chargebacked."
                            ccLicenseSettings.licenseStatus = "invalid"
                            LicenseState.deactivate()
                        } else {
                            const now = new Date().toISOString()
                            ccWin._licStatus      = "active"
                            ccWin._licEmail       = p.email || ""
                            ccWin._licLastChecked = now
                            ccWin._licError       = ""
                            ccLicenseSettings.licenseStatus = "active"
                            ccLicenseSettings.licensedEmail = p.email || ""
                            ccLicenseSettings.lastVerified  = now
                            // Key already persisted in _verifyLicense() before the curl call.
                            LicenseState.activate()
                            _dockValReader.running = true
                            _rofiValReader.running = true
                            _lcValReader.running   = true
                            _sddmValReader.running = true
                            _weatherLocReader.running = true
                            _hyprlandValReader.running = true
                            _layoutReader.running = true
                            _hyprStateReader.running = true
                            _kbLayoutReader.running  = true
                            mainStack.currentIndex = 1
                            ccTabSettings.activeTab = 1
                        }
                    } else {
                        ccWin._licStatus = "invalid"
                        ccWin._licError  = obj.message || "Invalid or expired license key."
                        ccLicenseSettings.licenseStatus = "invalid"
                        LicenseState.deactivate()
                    }
                } catch(e) {
                    ccWin._licStatus = "invalid"
                    ccWin._licError  = "Verification failed — check your connection."
                    ccLicenseSettings.licenseStatus = "invalid"
                    LicenseState.deactivate()
                }
            }   // onStreamFinished
        }       // StdioCollector
    }           // Process

    // ── Gumroad licence deactivation process ─────────────────────────────────
    Process {
        id: _licDeactivateProc
        running: false
        onExited: function(code, status) {
            if (ccWin._licDeactivating) {
                // If the process exits but onStreamFinished didn't run (rare)
                ccWin._licDeactivating = false
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                ccWin._licDeactivating = false
                try {
                    const obj = JSON.parse(text.trim())
                    const ok = (obj.success === true || obj.success === "true")
                    if (ok) {
                        // Deactivation successful
                        ccWin._licStatus      = ""
                        ccWin._licEmail       = ""
                        ccWin._licLastChecked = ""
                        ccWin._licError       = ""
                        ccLicenseSettings.licenseKey    = ""
                        ccLicenseSettings.licenseStatus = ""
                        ccLicenseSettings.licensedEmail = ""
                        ccLicenseSettings.lastVerified  = ""
                        LicenseState.reset()
                    } else {
                        ccWin._licError = obj.message || "Deactivation failed."
                    }
                } catch(e) {
                    ccWin._licError = "Deactivation failed — check your connection."
                }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: ControlCenterState.close()
    }

    // ── The panel itself ───────────────────────────────────────────────────
    Rectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 825//ccWin._panelW

        radius: 20
        color:  Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)
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
                width: 190 + 14  // card width + left padding
                z: 2            // float over the content pane

            Item {
                id: sidebarCard
                anchors {
                    left: parent.left;   leftMargin:   14
                    top: parent.top;     topMargin:    14
                    bottom: parent.bottom; bottomMargin: 14
                    right: parent.right
                }

                MouseArea {
                    anchors.fill: parent
                    onWheel: function(wheel) {
                        // When not activated, scrolling is locked to tab 6 (activation tab)
                        if (!LicenseState.activated) return

                        const tabs = [1, 0, 2, 3, 4, 5, 7, 8, 9]
                        let currIdx = tabs.indexOf(ccTabSettings.activeTab)
                        if (currIdx === -1) currIdx = 0

                        if (wheel.angleDelta.y > 0) {
                            // Scroll up -> Previous tab
                            currIdx = (currIdx - 1 + tabs.length) % tabs.length
                        } else {
                            // Scroll down -> Next tab
                            currIdx = (currIdx + 1) % tabs.length
                        }

                        const nextTab = tabs[currIdx]
                        mainStack.currentIndex = nextTab
                        ccTabSettings.activeTab = nextTab
                    }
                }


                // Full sidebar background — panel.radius rounds all four
                // corners; the clip wrapper above trims the right two.
                Rectangle {
                    anchors.fill: parent
                    radius: 14
                    color: Qt.rgba(Theme.cBackground.r, Theme.cBackground.g,
                                                       Theme.cBackground.b, 0.65)
                                                       
		    border.width: 2
        	    border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
                }

                ColumnLayout {
                    anchors { fill: parent; margins: 14 }
                    spacing: 5

                    // ── User info card ─────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        height: 125
                        radius: 16
                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.82)
                        border.width: 2
                        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g,
                                              Theme.cScrim.b, 0.85)

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 6

                            // User icon circle — click opens wallpaper picker overlay
                            Rectangle {
                                id: userIconCircle
                                Layout.alignment: Qt.AlignHCenter
                                width: 80; height: 80; radius: 99
                                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                               Theme.cInversePrimary.b, 0.32)
                                border.width: 2
                        	border.color: Qt.rgba(Theme.cSurface.r, Theme.cSurface.g,
                                              Theme.cSurface.b, 0.65)
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
                                color: Theme.cOnSecondary
                                font.family: Config.styleFont
                                font.pixelSize: 16
                                font.weight: Font.Bold
                                font.italic: true
                            }
                        }
                    }

                    // ── Nav buttons ───────────────────────────────────────
                    Repeater {
                        model: [
                            { icon: "", label: "Hyprland",  idx: 1 },
                            { icon: "󰇜", label: "Bar",       idx: 0 },
                            { icon: "󰔎", label: "Themes",    idx: 2 },
                            { icon: "󰇜", label: "Dock",      idx: 3 },
                            { icon: "󰮫", label: "Menus",     idx: 4 },
                            { icon: "󰍂", label: "SDDM",      idx: 5 },
                            { icon: "󰌌", label: "Keybinds",  idx: 7 },
                            { icon: "󰗘", label: "Animations", idx: 8 },
                            { icon: "󰍛", label: "System",     idx: 9 }
                        ]

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            // ComponentBehavior: Bound — capture outer id as required property
                            property int _stackIdx: mainStack.currentIndex
                            Layout.fillWidth: true
                            height: 38; radius: 11
                            // Dim the entire button when locked
                            opacity: LicenseState.activated ? 1.0 : 0.35
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            color: _stackIdx === modelData.idx
                                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                          Theme.cPrimary.b, 0.82)
                                : (navHover.containsMouse && LicenseState.activated
                                    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                              Theme.cInversePrimary.b, 0.2)
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
                                    color: (_stackIdx === modelData.idx ? Theme.cOnSecondary : Theme.cWc12); opacity: 0.55
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                Text {
                                    text: modelData.label
                                    font.family: Config.labelFont; font.pixelSize: 13
                                    font.weight: (modelData && _stackIdx === modelData.idx) ? 600 : 400
                                    color: _stackIdx === modelData.idx ? Theme.cOnSecondary : Theme.cPrimary
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                            // Active indicator pill on right
                            Rectangle {
                                anchors { right: parent.right; rightMargin: 4
                                          verticalCenter: parent.verticalCenter }
                                width: 3; height: 20; radius: 2
                                color: Theme.cWc5
                                visible: parent._stackIdx === modelData.idx
                            }

                            MouseArea {
                                id: navHover
                                anchors.fill: parent
                                cursorShape: LicenseState.activated ? Qt.PointingHandCursor : Qt.ForbiddenCursor
                                hoverEnabled: true
                                enabled: LicenseState.activated
                                onClicked: {
                                    mainStack.currentIndex = modelData.idx
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
                            text: "♥️ Support HyprCandy"
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                           Theme.cPrimary.b,
                                           hcTextHov.containsMouse ? 0.85 : 0.65)
                            font.family: Config.labelFont; font.pixelSize: 10
                            Behavior on color { ColorAnimation { duration: 120 } }
                            MouseArea {
                                id: hcTextHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                propagateComposedEvents: true
                                onClicked: function(mouse) {
                                    mainStack.currentIndex = 6
                                    ccTabSettings.activeTab = 6
                                    mouse.accepted = true
                                }
                            }
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
              } // sidebarCard
            } // sidebar

            // ═══════════════════════════════════════════════════════════════
            //  RIGHT CONTENT PANE — own rounded rect, no shared edge with sidebar
            // ═══════════════════════════════════════════════════════════════
            Rectangle {
                anchors {
                    left: sidebar.right; right: parent.right
                    top: parent.top;   bottom: parent.bottom
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
                                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                      Theme.cPrimary.b, 1.00)
                                            : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, 
                                            	      Theme.cOnSecondary.b, 0.15)
                                        border.width: _subIdx === index ? 1 : 0
                                        border.color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                      Theme.cInversePrimary.b, 0.42)
                                        Text {
                                            id: _stLabel; anchors.centerIn: parent
                                            text: modelData; color: (_subIdx === index ? Theme.cOnSecondary : Theme.cPrimary)
                                            font.family: Config.labelFont; font.pixelSize: 12
                                            font.weight: (index !== undefined && _subIdx === index) ? 600 : 400
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                barSubStack.currentIndex = index
                                                ccTabSettings.activeBarSubTab = index
                                            }
                                        }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }
                            }

                            // Separator
                            Rectangle {
                                Layout.fillWidth: true; height: 1
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                            }

                            // Bar sub-tab content
                            StackLayout {
                                id: barSubStack
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndex: ccTabSettings.activeBarSubTab

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
                                                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                               Theme.cInversePrimary.b, 0.15)
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
                                                                   Theme.cPrimary.b, 0.8)
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
                                            options: ["bar", "island", "tri", "shell"]
                                            current: Config.barMode
                                            onPicked: function(v) { Config.barMode = v }
                                        }
                                        CCSegmented {
                                            label: "Position"
                                            options: ["top","bottom"] //,"left","right" (commented currently broken left&right position)
                                            current: Config.barPosition
                                            onPicked: function(v) { Config.barPosition = v }
                                        }

                                        CCSection { text: "Corner Radius" }
                                        // bar / island — single rect corners
                                        CCSlider { visible: Config.barMode !== "tri" && Config.barMode !== "shell"; label:"Top-Left";     from:0;to:90; value:Config.barTopLeftRadius;     onMoved:function(v){Config.barTopLeftRadius=v} }
                                        CCSlider { visible: Config.barMode !== "tri" && Config.barMode !== "shell"; label:"Top-Right";    from:0;to:90; value:Config.barTopRightRadius;    onMoved:function(v){Config.barTopRightRadius=v} }
                                        CCSlider { visible: Config.barMode !== "tri" && Config.barMode !== "shell"; label:"Bottom-Left";  from:0;to:90; value:Config.barBottomLeftRadius;  onMoved:function(v){Config.barBottomLeftRadius=v} }
                                        CCSlider { visible: Config.barMode !== "tri" && Config.barMode !== "shell"; label:"Bottom-Right"; from:0;to:90; value:Config.barBottomRightRadius; onMoved:function(v){Config.barBottomRightRadius=v} }
                                        // tri — per-segment corners (left uses bar*Radius)
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"L.Top-Left";     from:0;to:90; value:Config.barTopLeftRadius;          onMoved:function(v){Config.barTopLeftRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"L.Top-Right";    from:0;to:90; value:Config.triLeftTopRightRadius;    onMoved:function(v){Config.triLeftTopRightRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"L.Bottom-Left";  from:0;to:90; value:Config.barBottomLeftRadius;       onMoved:function(v){Config.barBottomLeftRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"L.Bottom-Right"; from:0;to:90; value:Config.triLeftBottomRightRadius; onMoved:function(v){Config.triLeftBottomRightRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri"; label:"C.Top-Left";     from:0;to:90; value:Config.triCenterTopLeftRadius;     onMoved:function(v){Config.triCenterTopLeftRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri"; label:"C.Top-Right";    from:0;to:90; value:Config.triCenterTopRightRadius;    onMoved:function(v){Config.triCenterTopRightRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri"; label:"C.Bottom-Left";  from:0;to:90; value:Config.triCenterBottomLeftRadius;  onMoved:function(v){Config.triCenterBottomLeftRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri"; label:"C.Bottom-Right"; from:0;to:90; value:Config.triCenterBottomRightRadius; onMoved:function(v){Config.triCenterBottomRightRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"R.Top-Left";     from:0;to:90; value:Config.triRightTopLeftRadius;     onMoved:function(v){Config.triRightTopLeftRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"R.Top-Right";    from:0;to:90; value:Config.barTopRightRadius;       onMoved:function(v){Config.barTopRightRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"R.Bottom-Left";  from:0;to:90; value:Config.triRightBottomLeftRadius;  onMoved:function(v){Config.triRightBottomLeftRadius=v} }
                                        CCSlider { visible: Config.barMode === "tri" || Config.barMode === "shell"; label:"R.Bottom-Right"; from:0;to:90; value:Config.barBottomRightRadius;    onMoved:function(v){Config.barBottomRightRadius=v} }
                                        CCSlider { label:"Island"; from:0;to:90; value:Config.islandRadius; onMoved:function(v){Config.islandRadius=v} }
                                        // Shell-specific geometry
                                         CCSlider { visible: Config.barMode === "shell"; label:"Inner Radii"; from:0;to:90;               value:Config.shellInnerRadius;           onMoved:function(v){Config.shellInnerRadius=v} }
                                         //CCSlider { visible: Config.barMode === "shell"; label:"C.Junction";  from:0;to:90;               value:Config.shellCenterJunctionRadius;  onMoved:function(v){Config.shellCenterJunctionRadius=v} }

                                         CCSection { text: "Dimensions" }
                                         CCSlider { visible: Config.barMode === "shell"; label:"Shell Pad";   from:4;to:120; stepSize:1;  value:Config.shellArmThickness;         onMoved:function(v){Config.shellArmThickness=v} }
                                         CCSlider { label:"Bar Height";    from:20;to:80;  stepSize:2;  value:Config.barHeight;    onMoved:function(v){Config.barHeight=v} }
                                         CCSlider { label:"Module Height";  from:12;to:70;  stepSize:2;  value:Config.moduleHeight;  onMoved:function(v){Config.moduleHeight=v} }

                                         CCSection { text: "Screen Margins" }
                                         CCSlider { label:"Top Margin";    from:0;to:30; value:Config.outerMarginTop;    onMoved:function(v){Config.outerMarginTop=v} }
                                         CCSlider { label:"Bottom Margin"; from:0;to:30; value:Config.outerMarginBottom; onMoved:function(v){Config.outerMarginBottom=v} }
                                         // "tri" and "shell" islands have their own side-margin, split from bar/island's outerMarginSide
                                         CCSlider { visible: Config.barMode !== "tri" && Config.barMode !== "shell"; label:"Side Margin";       from:0;to:200; value:Config.outerMarginSide;      onMoved:function(v){Config.outerMarginSide=v} }
                                         CCSlider { visible: Config.barMode === "tri";                              label:"Side Margin (Tri)";   from:0;to:200; value:Config.triModuleSideMargin;  onMoved:function(v){Config.triModuleSideMargin=v} }
                                         CCSlider { visible: Config.barMode === "shell";                            label:"Side Margin (Shell)"; from:0;to:200; value:Config.shellModuleSideMargin;onMoved:function(v){Config.shellModuleSideMargin=v} }
                                         CCSlider { label:"Edge Pad Left"; from:0;to:30; value:Config.barEdgePaddingLeft; onMoved:function(v){Config.barEdgePaddingLeft=v} }
                                         CCSlider { label:"Edge Pad Right";from:0;to:30; value:Config.barEdgePaddingRight;onMoved:function(v){Config.barEdgePaddingRight=v} }

                                         CCSection { text: "Border" }
                                         CCSlider {
                                             label: "Border W"
                                             from: 0; to: 8
                                             value: Config.barBorderWidth
                                             onMoved: function(v) {
                                                 Config.barBorderWidth = v
                                                 _dockBorderWVal = v.toString()
                                                 if (_barBorderWFromBarWrite.running) {
                                                     _barBorderWFromBarWrite._pending = [scriptDir + "/dock-set.sh", "borderWidth", v.toString()]
                                                 } else {
                                                     _barBorderWFromBarWrite.command = [scriptDir + "/dock-set.sh", "borderWidth", v.toString()]
                                                     _barBorderWFromBarWrite.running = true
                                                 }
                                                 _barBorderWStateWrite.command = ["bash", "-c",
                                                     "f=\"$HOME/.hyprcandy/GJS/hyprcandydock/dock-border-w.state\";" +
                                                     "mkdir -p \"$(dirname \"$f\")\";" +
                                                     "printf '%s\\n' '" + v.toString() + "' > \"$f\""
                                                 ]
                                                 _barBorderWStateWrite.running = true
                                             }
                                         }
                                         Process {
                                             id: _barBorderWFromBarWrite
                                             property var _pending: null
                                             running: false
                                             onExited: {
                                                 running = false
                                                 if (_pending !== null) {
                                                     command = _pending; _pending = null; running = true
                                                 }
                                             }
                                         }
                                         Process { id: _barBorderWStateWrite; running: false; onExited: running = false }
                                         CCSlider { label:"Border 󰀫";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.barBorderAlpha;    onMoved:function(v){Config.barBorderAlpha=v} }
                                         CCSlider {
                                             label: "Island B-W"
                                             from: 0; to: 8
                                             value: Config.islandBorder
                                             onMoved: function(v) {
                                                 Config.islandBorder = v
                                                 if (_islBorderDockWrite.running) {
                                                     _islBorderDockWrite._pending = [scriptDir + "/dock-island-border.sh", "width", v.toString()]
                                                 } else {
                                                     _islBorderDockWrite.command = [scriptDir + "/dock-island-border.sh", "width", v.toString()]
                                                     _islBorderDockWrite.running = true
                                                 }
                                             }
                                         }
                                         CCSlider {
                                             label: "Island B-α"
                                             from: 0; to: 1; stepSize: 0.05; decimals: 2
                                             value: Config.islandBorderAlpha
                                             onMoved: function(v) {
                                                 Config.islandBorderAlpha = v
                                                 if (_islBorderDockWrite.running) {
                                                     _islBorderDockWrite._pending = [scriptDir + "/dock-island-border.sh", "alpha", v.toString()]
                                                 } else {
                                                     _islBorderDockWrite.command = [scriptDir + "/dock-island-border.sh", "alpha", v.toString()]
                                                     _islBorderDockWrite.running = true
                                                 }
                                             }
                                         }

                                        CCSection { text: "Bar Border Color" }
                                        // ── matugen / wallust 2-option pill ─────────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Rectangle {
                                                Layout.preferredWidth: 174; height: 28; radius: 9
                                                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                                    		border.width: 1
                                    		border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                                Row {
                                                    anchors.fill: parent; anchors.margins: 2; spacing: 2
                                                    Repeater {
                                                        model: ["matugen", "wallust"]
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            property bool _sel: Config.barBorderMode === modelData
                                                            width: (parent.width - 4) / 2; height: parent.height; radius: 7
                                                            color: _sel ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.82) : "transparent"
                                                	    border.width: _sel ? 1 : 0
                                                	    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                                color: _sel ? Theme.cOnSecondary : Theme.cPrimary
                                                                font.family: Config.labelFont; font.pixelSize: 12
                                                                font.weight: _sel ? 600 : 400
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    Config.barBorderMode = modelData
                                                                    // Keep the GJS dock border in sync when switching
                                                                    // modes without re-picking a swatch — otherwise the
                                                                    // dock keeps whatever color was last written for
                                                                    // whichever mode was active last time a swatch was
                                                                    // clicked, instead of following the mode you just
                                                                    // switched to.
                                                                    const activeVar = modelData === "matugen"
                                                                        ? Config.barBorderVar
                                                                        : Config.barBorderWallustVar
                                                                    if (activeVar) {
                                                                        const gtk = activeVar.replace(/^\$/, "")
                                                                        if (_barBorderDockWrite.running) {
                                                                            _barBorderDockWrite._pending = [scriptDir + "/dock-border.sh", gtk]
                                                                        } else {
                                                                            _barBorderDockWrite.command = [scriptDir + "/dock-border.sh", gtk]
                                                                            _barBorderDockWrite.running = true
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        // ── Matugen swatches (bar border) ───────────────────────────
                                        Item {
                                            Layout.fillWidth: true
                                            implicitHeight: Config.barBorderMode === "matugen"
                                                ? (_barBorderMatLoader.item ? _barBorderMatLoader.item.height : 0)
                                                : (_barBorderWalLoader.item ? _barBorderWalLoader.item.height : 0)
                                            Loader {
                                                id: _barBorderMatLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.barBorderMode === "matugen"
                                                sourceComponent: Flow {
                                                    width: parent ? parent.width : 0; spacing: 5
                                                    Repeater {
                                                        model: ccWin._matugenBorderVars
                                                        delegate: Item {
                                                            required property var modelData
                                                            width: 28; height: 28
                                                            Rectangle {
                                                                anchors.fill: parent; radius: 6
                                                                color: ccWin._cavaThemeColorLocal(modelData.var)
                                                                border.width: Config.barBorderVar === modelData.var ? 2 : 1
                                                                border.color: Config.barBorderVar === modelData.var
                                                                    ? Theme.cPrimary
                                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                ToolTip.visible: _bbMatHov.containsMouse
                                                                ToolTip.text: modelData.var
                                                                ToolTip.delay: 400
                                                                MouseArea {
                                                                    id: _bbMatHov
                                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                    hoverEnabled: true
                                                                    onClicked: {
                                                                        Config.barBorderVar = modelData.var
                                                                        // Sync dock window border (line 10 of style.css)
                                                                        const gtk = modelData.var.replace(/^\$/, "").replace(/_/g, "_")
                                                                        if (_barBorderDockWrite.running) {
                                                                            _barBorderDockWrite._pending = [scriptDir + "/dock-border.sh", gtk]
                                                                        } else {
                                                                            _barBorderDockWrite.command = [scriptDir + "/dock-border.sh", gtk]
                                                                            _barBorderDockWrite.running = true
                                                                        }
                                                                    }
                                                                }
                                                                Behavior on border.width { NumberAnimation { duration: 100 } }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            // ── Wallust swatches (bar border) ─────────────────────
                                            Loader {
                                                id: _barBorderWalLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.barBorderMode === "wallust"
                                                sourceComponent: Flow {
                                                    width: parent ? parent.width : 0; spacing: 5
                                                    Repeater {
                                                        model: ccWin._wallustBorderVars
                                                        delegate: Item {
                                                            required property var modelData
                                                            width: 28; height: 28
                                                            Rectangle {
                                                                anchors.fill: parent; radius: 6
                                                                color: ccWin._resolveWallustColor(modelData.var)
                                                                border.width: Config.barBorderWallustVar === modelData.var ? 2 : 1
                                                                border.color: Config.barBorderWallustVar === modelData.var
                                                                    ? Theme.cPrimary
                                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                ToolTip.visible: _bbWalHov.containsMouse
                                                                ToolTip.text: modelData.var
                                                                ToolTip.delay: 400
                                                                MouseArea {
                                                                    id: _bbWalHov
                                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                    hoverEnabled: true
                                                                    onClicked: {
                                                                        Config.barBorderWallustVar = modelData.var
                                                                        // Sync dock window border (line 10 of style.css) with wallust colorN name
                                                                        const gtk = modelData.var.replace(/^\$/, "")
                                                                        if (_barBorderDockWrite.running) {
                                                                            _barBorderDockWrite._pending = [scriptDir + "/dock-border.sh", gtk]
                                                                        } else {
                                                                            _barBorderDockWrite.command = [scriptDir + "/dock-border.sh", gtk]
                                                                            _barBorderDockWrite.running = true
                                                                        }
                                                                    }
                                                                }
                                                                Behavior on border.width { NumberAnimation { duration: 100 } }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Process {
                                            id: _barBorderDockWrite
                                            property var _pending: null
                                            running: false
                                            onExited: {
                                                running = false
                                                if (_pending !== null) {
                                                    command = _pending; _pending = null; running = true
                                                }
                                            }
                                        }

                                        CCSection { text: "Island Border Color" }
                                        // ── matugen / wallust 2-option pill ─────────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Rectangle {
                                                Layout.preferredWidth: 174; height: 28; radius: 9
                                                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                                    		border.width: 1
                                    		border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                                Row {
                                                    anchors.fill: parent; anchors.margins: 2; spacing: 2
                                                    Repeater {
                                                        model: ["matugen", "wallust"]
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            property bool _sel: Config.islandBorderMode === modelData
                                                            width: (parent.width - 4) / 2; height: parent.height; radius: 7
                                                            color: _sel ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.82) : "transparent"
                                                	    border.width: _sel ? 1 : 0
                                                	    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                                color: _sel ? Theme.cOnSecondary : Theme.cPrimary
                                                                font.family: Config.labelFont; font.pixelSize: 12
                                                                font.weight: _sel ? 600 : 400
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    Config.islandBorderMode = modelData
                                                                    // Keep the GJS dock island border in sync when
                                                                    // switching modes without re-picking a swatch —
                                                                    // otherwise the dock keeps whatever color was last
                                                                    // written for whichever mode was active last time
                                                                    // a swatch was clicked, instead of following the
                                                                    // mode you just switched to.
                                                                    const activeVar = modelData === "matugen"
                                                                        ? Config.islandBorderVar
                                                                        : Config.islandBorderWallustVar
                                                                    if (activeVar) {
                                                                        const gtk = activeVar.replace(/^\$/, "")
                                                                        if (_islBorderDockWrite.running) {
                                                                            _islBorderDockWrite._pending = [scriptDir + "/dock-island-border.sh", gtk]
                                                                        } else {
                                                                            _islBorderDockWrite.command = [scriptDir + "/dock-island-border.sh", gtk]
                                                                            _islBorderDockWrite.running = true
                                                                        }
                                                                    }
                                                                }
                                                            }
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        // ── Matugen swatches (island border) ────────────────────────
                                        Item {
                                            Layout.fillWidth: true
                                            implicitHeight: Config.islandBorderMode === "matugen"
                                                ? (_islBorderMatLoader.item ? _islBorderMatLoader.item.height : 0)
                                                : (_islBorderWalLoader.item ? _islBorderWalLoader.item.height : 0)
                                            Loader {
                                                id: _islBorderMatLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.islandBorderMode === "matugen"
                                                sourceComponent: Flow {
                                                    width: parent ? parent.width : 0; spacing: 5
                                                    Repeater {
                                                        model: ccWin._matugenBorderVars
                                                        delegate: Item {
                                                            required property var modelData
                                                            width: 28; height: 28
                                                            Rectangle {
                                                                anchors.fill: parent; radius: 6
                                                                color: ccWin._cavaThemeColorLocal(modelData.var)
                                                                border.width: Config.islandBorderVar === modelData.var ? 2 : 1
                                                                border.color: Config.islandBorderVar === modelData.var
                                                                    ? Theme.cPrimary
                                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                ToolTip.visible: _ibMatHov.containsMouse
                                                                ToolTip.text: modelData.var
                                                                ToolTip.delay: 400
                                                                MouseArea {
                                                                    id: _ibMatHov
                                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                    hoverEnabled: true
                                                                    onClicked: {
                                                                        Config.islandBorderVar = modelData.var
                                                                        // Sync dock start/trash border (line 49 of style.css)
                                                                        const gtk = modelData.var.replace(/^\$/, "")
                                                                        if (_islBorderDockWrite.running) {
                                                                            _islBorderDockWrite._pending = [scriptDir + "/dock-island-border.sh", gtk]
                                                                        } else {
                                                                            _islBorderDockWrite.command = [scriptDir + "/dock-island-border.sh", gtk]
                                                                            _islBorderDockWrite.running = true
                                                                        }
                                                                    }
                                                                }
                                                                Behavior on border.width { NumberAnimation { duration: 100 } }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            // ── Wallust swatches (island border) ──────────────────
                                            Loader {
                                                id: _islBorderWalLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.islandBorderMode === "wallust"
                                                sourceComponent: Flow {
                                                    width: parent ? parent.width : 0; spacing: 5
                                                    Repeater {
                                                        model: ccWin._wallustBorderVars
                                                        delegate: Item {
                                                            required property var modelData
                                                            width: 28; height: 28
                                                            Rectangle {
                                                                anchors.fill: parent; radius: 6
                                                                color: ccWin._resolveWallustColor(modelData.var)
                                                                border.width: Config.islandBorderWallustVar === modelData.var ? 2 : 1
                                                                border.color: Config.islandBorderWallustVar === modelData.var
                                                                    ? Theme.cPrimary
                                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                ToolTip.visible: _ibWalHov.containsMouse
                                                                ToolTip.text: modelData.var
                                                                ToolTip.delay: 400
                                                                MouseArea {
                                                                    id: _ibWalHov
                                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                    hoverEnabled: true
                                                                    onClicked: {
                                                                        Config.islandBorderWallustVar = modelData.var
                                                                        // Sync dock start/trash border (line 49 of style.css) with wallust colorN
                                                                        const gtk = modelData.var.replace(/^\$/, "")
                                                                        if (_islBorderDockWrite.running) {
                                                                            _islBorderDockWrite._pending = [scriptDir + "/dock-island-border.sh", gtk]
                                                                        } else {
                                                                            _islBorderDockWrite.command = [scriptDir + "/dock-island-border.sh", gtk]
                                                                            _islBorderDockWrite.running = true
                                                                        }
                                                                    }
                                                                }
                                                                Behavior on border.width { NumberAnimation { duration: 100 } }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Process {
                                            id: _islBorderDockWrite
                                            property var _pending: null
                                            running: false
                                            onExited: {
                                                running = false
                                                if (_pending !== null) {
                                                    command = _pending; _pending = null; running = true
                                                }
                                            }
                                        }

                                        CCSection { text: "Spacing & Padding" }
                                        CCSlider { label:"Island Spacing";  from:0;to:24; value:Config.islandSpacing;  onMoved:function(v){Config.islandSpacing=v} }
                                        CCSlider { label:"Grouped Spacing"; from:0;to:12; value:Config.groupedSpacing; onMoved:function(v){Config.groupedSpacing=v} }
                                        CCSlider { label:"Module Pad H";    from:3;to:20; value:Config.modPadH;        onMoved:function(v){Config.modPadH=v} }

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
                                        CCSlider { label:"Module Text"; from:8;to:20; value:Config.infoFontSize;  onMoved:function(v){Config.infoFontSize=v} }

                                        CCSection { text: "Workspace Icon Glyphs" }
                                        CCIconEntry { label:"Active Dot";     value:Config.wsDotActive;     onApplied:function(v){Config.wsDotActive=v} }
                                        CCSlider { label:"Active Opacity";     from:0;to:1;stepSize:0.05;decimals:2; value:Config.wsActiveOpacity;     onMoved:function(v){Config.wsActiveOpacity=v} }
                                        CCIconEntry { label:"Persistent Dot"; value:Config.wsDotPersistent; onApplied:function(v){Config.wsDotPersistent=v} }
                                        CCSlider { label:"Persistent Opacity"; from:0;to:1;stepSize:0.05;decimals:2; value:Config.wsPersistentOpacity; onMoved:function(v){Config.wsPersistentOpacity=v} }
                                        CCIconEntry { label:"Empty Dot";      value:Config.wsDotEmpty;      onApplied:function(v){Config.wsDotEmpty=v} }
                                        CCSlider { label:"Empty Opacity";      from:0;to:1;stepSize:0.05;decimals:2; value:Config.wsEmptyOpacity;      onMoved:function(v){Config.wsEmptyOpacity=v} }
                                        CCIconEntry { label:"WS Separator";   value:Config.wsSeparatorGlyph;onApplied:function(v){Config.wsSeparatorGlyph=v} }
                                        CCSlider { label:"Separator Opacity";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.wsSeparatorOpacity;  onMoved:function(v){Config.wsSeparatorOpacity=v} }

                                        CCSection { text: "Control Center" }
                                        CCIconEntry {
                                            label:"CC Glyph"
                                            value:Config.ccGlyph
                                            onApplied:function(v){
                                                Config.ccGlyph=v
                                                // Also write to candy-start-icon.txt for hot-update
                                                _ccGlyphWrite.command = ["bash", "-c",
                                                    "echo -n '" + v + "' > \"$HOME/.config/hyprcandy/candy-start-icon.txt\""]
                                                _ccGlyphWrite.running = true
                                            }
                                        }
                                        CCSlider { label:"CC Glyph Opacity"; from:0;to:1;stepSize:0.05;decimals:2; value:Config.ccGlyphOpacity; onMoved:function(v){Config.ccGlyphOpacity=v} }
                                        Process { id:_ccGlyphWrite; running:false }

                                        CCSection { text: "Battery" }
                                        CCToggle { label:"Radial Visible"; value:Config.batteryRadialVisible; onToggled:function(v){Config.batteryRadialVisible=v} }
                                        CCSlider { label:"Radial Size";  from:8;to:32; value:Config.batteryRadialSize;  onMoved:function(v){Config.batteryRadialSize=v} }
                                        CCSlider { label:"Radial Stroke";from:1;to:6;  value:Config.batteryRadialWidth; onMoved:function(v){Config.batteryRadialWidth=v} }

                                        CCSection { text: "Tray" }
                                        //CCSlider { label:"Icon Size";    from:10;to:32; value:Config.trayIconSz;     onMoved:function(v){Config.trayIconSz=v} }
                                        //CCSlider { label:"Item Pad H";   from:0;to:8;   value:Config.trayItemPadH;   onMoved:function(v){Config.trayItemPadH=v} }
                                        CCSlider { label:"Item Spacing"; from:0;to:10;  value:Config.trayItemSpacing; onMoved:function(v){Config.trayItemSpacing=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Workspaces ─────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Workspace Slots" }
                                        CCSlider { label:"Slot Count"; from:1;to:10;stepSize:1;decimals:0; value:Config.wsCount; onMoved:function(v){Config.wsCount=v} }

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
                                        CCSlider { label:"Thumb Size"; from:10;to:40; value:Config.mediaThumbSize; onMoved:function(v){Config.mediaThumbSize=v} }

                                        //CCSection { text: "Controls" }
                                        //CCSlider { label:"Ctl Glyph Size"; from:6;to:24; value:Config.mediaCtlSize; onMoved:function(v){Config.mediaCtlSize=v} }

                                        //CCSection { text: "Padding (0 = true zero)" }
                                        //CCSlider { label:"Pad Left";   from:0;to:16; value:Config.mediaPadLeft;   onMoved:function(v){Config.mediaPadLeft=v} }
                                        //CCSlider { label:"Pad Right";  from:0;to:16; value:Config.mediaPadRight;  onMoved:function(v){Config.mediaPadRight=v} }
                                        //CCSlider { label:"Pad Top";    from:0;to:10; value:Config.mediaPadTop;    onMoved:function(v){Config.mediaPadTop=v} }
                                        //CCSlider { label:"Pad Bottom"; from:0;to:10; value:Config.mediaPadBottom; onMoved:function(v){Config.mediaPadBottom=v} }

                                        Item { height: 10 }
                                    }
                                }

                                // ── Cava ───────────────────────────────────
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
                                                                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                          Theme.cPrimary.b, 0.72)
                                                                : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                                                                          Theme.cOnSecondary.b, 0.15)
                                                            border.width: Config.cavaStyle === modelData ? 1 : 0
                                                            border.color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                          Theme.cInversePrimary.b, 0.5)
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData
                                                                color: Config.cavaStyle === modelData ? Theme.cOnSecondary : Theme.cPrimary
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

                                        CCSection { text: "Dimensions & Behavior" }
                                        CCSlider { label:"Bar Count";   from:5;to:200;stepSize:1;   value:Config.cavaWidth;      onMoved:function(v){Config.cavaWidth=v} }
                                        CCSlider { label:"Bar Spacing"; from:0;to:6;stepSize:0.5;decimals:1; value:Config.cavaBarSpacing; onMoved:function(v){Config.cavaBarSpacing=v} }
                                        //CCToggle { label:"Transparent Inactive"; value:Config.cavaTransparentWhenInactive; onToggled:function(v){Config.cavaTransparentWhenInactive=v} }
                                        CCSlider { label:"Active Opacity";  from:0;to:1;stepSize:0.05;decimals:2; value:Config.cavaActiveOpacity;  onMoved:function(v){Config.cavaActiveOpacity=v} }
                                        CCSlider { label:"Inactive Opacity";from:0;to:1;stepSize:0.05;decimals:2; value:Config.cavaInactiveOpacity;onMoved:function(v){Config.cavaInactiveOpacity=v} }

                                        CCSection { text: "Color" }
                                        CCToggle { label:"Gradient"; value:Config.cavaGradientEnabled; onToggled:function(v){Config.cavaGradientEnabled=v} }

                                        // ── Bar / Start Color ───────────────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text {
                                                text: Config.cavaGradientEnabled ? "Start Color" : "Bar Color"
                                                color: Theme.cPrimary
                                                font.family: Config.labelFont; font.pixelSize: 13
                                                Layout.preferredWidth: 90
                                            }
                                            // Three-button mode selector
                                            Rectangle {
                                                Layout.preferredWidth: 216; height: 28; radius: 9
                                                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                                    		border.width: 1
                                    		border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                                Row {
                                                    anchors.fill: parent; anchors.margins: 2; spacing: 2
                                                    Repeater {
                                                        model: ["matugen", "pywal", "wallust"]
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            property bool _sel: Config.cavaStartMode === modelData
                                                            width: (parent.width - 6) / 3; height: parent.height; radius: 7
                                                            color: _sel ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.82) : "transparent"
                                                	    border.width: _sel ? 1 : 0
                                                	    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                            enabled: Config.cavaGradientEnabled
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                                color: _sel ? Theme.cOnSecondary : Theme.cPrimary
                                                                font.family: Config.labelFont; font.pixelSize: 12
                                                                font.weight: _sel ? 600 : 400
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                onClicked: { Config.cavaStartMode = modelData }
                                                            }
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                            implicitHeight: Config.cavaStartMode === "matugen"
                                                ? (_cavaStartMatugenLoader.item ? _cavaStartMatugenLoader.item.height : 0)
                                                : (Config.cavaStartMode === "pywal"
                                                    ? (_cavaStartPywalLoader.item ? _cavaStartPywalLoader.item.height : 0)
                                                    : (_cavaStartWallustLoader.item ? _cavaStartWallustLoader.item.height : 0))
                                            // Matugen color swatches
                                            Loader {
                                                id: _cavaStartMatugenLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.cavaStartMode === "matugen"
                                                sourceComponent: ColumnLayout {
                                                    spacing: 4
                                                    Flow {
                                                        Layout.fillWidth: true; spacing: 5
                                                        Repeater {
                                                            model: ccWin._matugenBorderVars
                                                            delegate: Item {
                                                                required property var modelData
                                                                width: 28; height: 28
                                                                Rectangle {
                                                                    anchors.fill: parent; radius: 6
                                                                    color: ccWin._cavaThemeColorLocal(modelData.var)
                                                                    border.width: Config.cavaStartVar === modelData.var ? 2 : 1
                                                                    border.color: Config.cavaStartVar === modelData.var
                                                                        ? Theme.cPrimary
                                                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                    ToolTip.visible: _csMatHover.containsMouse
                                                                    ToolTip.text: modelData.var
                                                                    ToolTip.delay: 400
                                                                    MouseArea {
                                                                        id: _csMatHover
                                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                        hoverEnabled: true
                                                                        onClicked: { Config.cavaStartVar = modelData.var }
                                                                    }
                                                                    Behavior on border.width { NumberAnimation { duration: 100 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            // Pywal color swatches
                                            Loader {
                                                id: _cavaStartPywalLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.cavaStartMode === "pywal"
                                                sourceComponent: ColumnLayout {
                                                    spacing: 4
                                                    Flow {
                                                        Layout.fillWidth: true; spacing: 5
                                                        Repeater {
                                                            model: ccWin._pywalBorderVars
                                                            delegate: Item {
                                                                required property var modelData
                                                                width: 28; height: 28
                                                                Rectangle {
                                                                    anchors.fill: parent; radius: 6
                                                                    color: ccWin._resolvePywalColor(modelData.var)
                                                                    border.width: Config.cavaStartPywalVar === modelData.var ? 2 : 1
                                                                    border.color: Config.cavaStartPywalVar === modelData.var
                                                                        ? Theme.cPrimary
                                                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                    ToolTip.visible: _csPywalHover.containsMouse
                                                                    ToolTip.text: modelData.var
                                                                    ToolTip.delay: 400
                                                                    MouseArea {
                                                                        id: _csPywalHover
                                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                        hoverEnabled: true
                                                                        onClicked: { Config.cavaStartPywalVar = modelData.var }
                                                                    }
                                                                    Behavior on border.width { NumberAnimation { duration: 100 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            // Wallust color swatches
                                            Loader {
                                                id: _cavaStartWallustLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.cavaStartMode === "wallust"
                                                sourceComponent: ColumnLayout {
                                                    spacing: 4
                                                    Flow {
                                                        Layout.fillWidth: true; spacing: 5
                                                        Repeater {
                                                            model: ccWin._wallustBorderVars
                                                            delegate: Item {
                                                                required property var modelData
                                                                width: 28; height: 28
                                                                Rectangle {
                                                                    anchors.fill: parent; radius: 6
                                                                    color: ccWin._resolveWallustColor(modelData.var)
                                                                    border.width: Config.cavaStartWallustVar === modelData.var ? 2 : 1
                                                                    border.color: Config.cavaStartWallustVar === modelData.var
                                                                        ? Theme.cPrimary
                                                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                    ToolTip.visible: _csWallustHover.containsMouse
                                                                    ToolTip.text: modelData.var
                                                                    ToolTip.delay: 400
                                                                    MouseArea {
                                                                        id: _csWallustHover
                                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                        hoverEnabled: true
                                                                        onClicked: { Config.cavaStartWallustVar = modelData.var }
                                                                    }
                                                                    Behavior on border.width { NumberAnimation { duration: 100 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        Item { height: 6 }

                                        // ── End Color (gradient only) ───────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            opacity: Config.cavaGradientEnabled ? 1.0 : 0.4
                                            Text {
                                                text: "End Color"
                                                color: Theme.cPrimary
                                                font.family: Config.labelFont; font.pixelSize: 13
                                                Layout.preferredWidth: 90
                                            }
                                            // Three-button mode selector
                                            Rectangle {
                                                Layout.preferredWidth: 216; height: 28; radius: 9
                                                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                                    		border.width: 1
                                    		border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                                Row {
                                                    anchors.fill: parent; anchors.margins: 2; spacing: 2
                                                    Repeater {
                                                        model: ["matugen", "pywal", "wallust"]
                                                        delegate: Rectangle {
                                                            required property string modelData
                                                            property bool _sel: Config.cavaEndMode === modelData
                                                            width: (parent.width - 6) / 3; height: parent.height; radius: 7
                                                            color: _sel ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.82) : "transparent"
                                                	    border.width: _sel ? 1 : 0
                                                	    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                            enabled: Config.cavaGradientEnabled
                                                            Text {
                                                                anchors.centerIn: parent
                                                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                                color: _sel ? Theme.cOnSecondary : Theme.cPrimary
                                                                font.family: Config.labelFont; font.pixelSize: 12
                                                                font.weight: _sel ? 600 : 400
                                                            }
                                                            MouseArea {
                                                                anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    if (!Config.cavaGradientEnabled) return
                                                                    Config.cavaEndMode = modelData
                                                                }
                                                            }
                                                            Behavior on color { ColorAnimation { duration: 120 } }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        Item {
                                            Layout.fillWidth: true
                                            opacity: Config.cavaGradientEnabled ? 1.0 : 0.4
                                            implicitHeight: Config.cavaEndMode === "matugen"
                                                ? (_cavaEndMatugenLoader.item ? _cavaEndMatugenLoader.item.height : 0)
                                                : (Config.cavaEndMode === "pywal"
                                                    ? (_cavaEndPywalLoader.item ? _cavaEndPywalLoader.item.height : 0)
                                                    : (_cavaEndWallustLoader.item ? _cavaEndWallustLoader.item.height : 0))
                                            // Matugen color swatches
                                            Loader {
                                                id: _cavaEndMatugenLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.cavaEndMode === "matugen"
                                                sourceComponent: ColumnLayout {
                                                    spacing: 4
                                                    Flow {
                                                        Layout.fillWidth: true; spacing: 5
                                                        Repeater {
                                                            model: ccWin._matugenBorderVars
                                                            delegate: Item {
                                                                required property var modelData
                                                                width: 28; height: 28
                                                                Rectangle {
                                                                    anchors.fill: parent; radius: 6
                                                                    color: ccWin._cavaThemeColorLocal(modelData.var)
                                                                    border.width: Config.cavaEndVar === modelData.var ? 2 : 1
                                                                    border.color: Config.cavaEndVar === modelData.var
                                                                        ? Theme.cPrimary
                                                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                    ToolTip.visible: _ceMatHover.containsMouse
                                                                    ToolTip.text: modelData.var
                                                                    ToolTip.delay: 400
                                                                    MouseArea {
                                                                        id: _ceMatHover
                                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                        hoverEnabled: true
                                                                        onClicked: {
                                                                            if (!Config.cavaGradientEnabled) return
                                                                            Config.cavaEndVar = modelData.var
                                                                        }
                                                                    }
                                                                    Behavior on border.width { NumberAnimation { duration: 100 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            // Pywal color swatches
                                            Loader {
                                                id: _cavaEndPywalLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.cavaEndMode === "pywal"
                                                sourceComponent: ColumnLayout {
                                                    spacing: 4
                                                    Flow {
                                                        Layout.fillWidth: true; spacing: 5
                                                        Repeater {
                                                            model: ccWin._pywalBorderVars
                                                            delegate: Item {
                                                                required property var modelData
                                                                width: 28; height: 28
                                                                Rectangle {
                                                                    anchors.fill: parent; radius: 6
                                                                    color: ccWin._resolvePywalColor(modelData.var)
                                                                    border.width: Config.cavaEndPywalVar === modelData.var ? 2 : 1
                                                                    border.color: Config.cavaEndPywalVar === modelData.var
                                                                        ? Theme.cPrimary
                                                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                    ToolTip.visible: _cePywalHover.containsMouse
                                                                    ToolTip.text: modelData.var
                                                                    ToolTip.delay: 400
                                                                    MouseArea {
                                                                        id: _cePywalHover
                                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                        hoverEnabled: true
                                                                        onClicked: {
                                                                            if (!Config.cavaGradientEnabled) return
                                                                            Config.cavaEndPywalVar = modelData.var
                                                                        }
                                                                    }
                                                                    Behavior on border.width { NumberAnimation { duration: 100 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            // Wallust color swatches
                                            Loader {
                                                id: _cavaEndWallustLoader
                                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                                active: Config.cavaEndMode === "wallust"
                                                sourceComponent: ColumnLayout {
                                                    spacing: 4
                                                    Flow {
                                                        Layout.fillWidth: true; spacing: 5
                                                        Repeater {
                                                            model: ccWin._wallustBorderVars
                                                            delegate: Item {
                                                                required property var modelData
                                                                width: 28; height: 28
                                                                Rectangle {
                                                                    anchors.fill: parent; radius: 6
                                                                    color: ccWin._resolveWallustColor(modelData.var)
                                                                    border.width: Config.cavaEndWallustVar === modelData.var ? 2 : 1
                                                                    border.color: Config.cavaEndWallustVar === modelData.var
                                                                        ? Theme.cPrimary
                                                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                                    ToolTip.visible: _ceWallustHover.containsMouse
                                                                    ToolTip.text: modelData.var
                                                                    ToolTip.delay: 400
                                                                    MouseArea {
                                                                        id: _ceWallustHover
                                                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                                        hoverEnabled: true
                                                                        onClicked: {
                                                                            if (!Config.cavaGradientEnabled) return
                                                                            Config.cavaEndWallustVar = modelData.var
                                                                        }
                                                                    }
                                                                    Behavior on border.width { NumberAnimation { duration: 100 } }
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        CCSlider {
                                            label: "Color Ratio"
                                            visible: Config.cavaGradientEnabled
                                            from: 0.1; to: 0.9; stepSize: 0.05; decimals: 2
                                            value: Config.cavaGradientSplit
                                            onMoved: function(v) { Config.cavaGradientSplit = v }
                                        }

                                        Item { height: 10 }
                                }

                                // ── Background ─────────────────────────────
                                ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Island Pill Style" }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Background fill style → glass vs gradient tint"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.48)
                                            font.family: Config.labelFont; font.pixelSize: 11
                                            wrapMode: Text.Wrap
                                        }
                                        CCToggle {
                                            label: "Gradient Pills"
                                            value: Config.islandBgStyle === "gradient"
                                            onToggled: function(v) {
                                                Config.islandBgStyle = v ? "gradient" : "flat"
                                                const style = v ? "gradient" : "flat"
                                                const cmd = "sed -i \"s/islandBgStyle: '[^']*'/islandBgStyle: '" + style + "'/;\" " +
                                                      "\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\" && " +
                                                      "pkill -SIGUSR2 -f 'gjs dock-main.js' 2>/dev/null || true"
                                                if (_confWriteProc.running) _confWriteProc._pendingCmd = cmd
                                                else { _confWriteProc._cmd = cmd; _confWriteProc.running = true }
                                            }
                                        }

                                        Item { height: 4 }

                                        CCSection { text: "Bar / Tri + Dock Fill Style" }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "Background fill style for the outer bar strip in 'bar' mode and 'tri'-island mode + dock."
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.48)
                                            font.family: Config.labelFont; font.pixelSize: 11
                                            wrapMode: Text.Wrap
                                        }
                                        CCSegmented {
                                            label: "Background"
                                            options: ["glass", "gradient"]
                                            current: Config.barRectBgStyle
                                            onPicked: function(v) {
                                                Config.barRectBgStyle = v
                                                _dockRectBgStyle = v
                                                // Write rectBgStyle and borderWidth in one sed pass so the dock
                                                // reloads once with both values already in place — no stagger.
                                                // Gradient → border 0.
                                                // Glass → read from dock-border-w.state (written by the Border W
                                                // slider on every non-zero move) so a wallpaper change that resets
                                                // config.js to its template defaults doesn't leave the border at
                                                // zero when switching back to glass. Falls back to _dockBorderWVal
                                                // if the state file doesn't exist yet.
                                                if (v === "gradient") {
                                                    _dockRectBgWrite.command = ["bash", "-c",
                                                        "f=\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\"; " +
                                                        "sed -i \"s/rectBgStyle: '[^']*'/rectBgStyle: 'gradient'/;" +
                                                                 "s/borderWidth: [0-9]*/borderWidth: 0/\" \"$f\" && " +
                                                        "pkill -SIGUSR2 -f 'gjs dock-main.js'"
                                                    ]
                                                } else {
                                                    const fallback = _dockBorderWVal
                                                    _dockRectBgWrite.command = ["bash", "-c",
                                                        "sf=\"$HOME/.hyprcandy/GJS/hyprcandydock/dock-border-w.state\";" +
                                                        "bw=$(cat \"$sf\" 2>/dev/null | tr -dc '0-9' | head -c4);" +
                                                        "[ -z \"$bw\" ] && bw='" + fallback + "';" +
                                                        "f=\"$HOME/.hyprcandy/GJS/hyprcandydock/config.js\"; " +
                                                        "sed -i \"s/rectBgStyle: '[^']*'/rectBgStyle: 'glass'/;" +
                                                                 "s/borderWidth: [0-9]*/borderWidth: $bw/\" \"$f\" && " +
                                                        "pkill -SIGUSR2 -f 'gjs dock-main.js'"
                                                    ]
                                                }
                                                _dockRectBgWrite.running = true
                                            }
                                        }

                                        Item { height: 4 }

                                        CCSection { text: "Per-Group Background Opacity" }
                                        Text {
                                            Layout.fillWidth: true
                                            text: "0.05 = lowest transparency maintaining blur  •  1 = fully opaque"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.48)
                                            font.family: Config.labelFont; font.pixelSize: 11
                                            wrapMode: Text.Wrap
                                        }

                                        CCSlider { label:"Workspaces";    from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.wsBgOpacity;          onMoved:function(v){Config.wsBgOpacity=v} }
                                        CCSlider { label:"Clock & Date";  from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.clockDateBgOpacity;   onMoved:function(v){Config.clockDateBgOpacity=v} }
                                        CCSlider { label:"Weather & Bat"; from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.weatherBatBgOpacity; onMoved:function(v){Config.weatherBatBgOpacity=v} }
                                        CCSlider { label:"Left Group";    from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.leftGroupBgOpacity;  onMoved:function(v){Config.leftGroupBgOpacity=v} }
                                        CCSlider { label:"Right Group";   from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.rightGroupBgOpacity; onMoved:function(v){Config.rightGroupBgOpacity=v} }
                                        CCSlider { label:"Start Menu";    from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.startMenuBgOpacity;    onMoved:function(v){Config.startMenuBgOpacity=v} }
                                        CCSlider { label:"Media";         from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.mediaBgOpacity;        onMoved:function(v){Config.mediaBgOpacity=v} }
                                        CCSlider { label:"Cava";          from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.cavaBgOpacity;         onMoved:function(v){Config.cavaBgOpacity=v} }
                                        CCSlider { label:"Distro";        from:0.05;to:1;stepSize:0.05;decimals:2; value:Config.distroBgOpacity;       onMoved:function(v){Config.distroBgOpacity=v} }

                                        Item { height: 10 }
                                }

                                // ── Visibility ─────────────────────────────
                                CCScrollPane {
                                    ColumnLayout {
                                        width: parent.width; spacing: 5

                                        CCSection { text: "Bar Auto-Hide" }

                                        CCToggle {
                                            id: _barAhToggle
                                            label: "Auto-Hide Bar"
                                            visible: Config.barMode !== "tri" && Config.barMode !== "shell"
                                            value: _barAhEnabled
                                            onToggled: function(v) {
                                                _barAhEnabled = v
                                                Config.barAutoHide = v
                                            }
                                        }

                                        CCSlider {
                                            label: "Delay (s)"
                                            visible: Config.barMode !== "tri" && Config.barMode !== "shell"
                                            from: 1; to: 60; stepSize: 1
                                            value: Config.barAutoHideDelay
                                            opacity: _barAhEnabled ? 1.0 : 0.4
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            onMoved: function(v) {
                                                _barAhDelay = v.toString()
                                                Config.barAutoHideDelay = v
                                            }
                                        }

                                        CCToggle {
                                            id: _triLeftAhToggle
                                            label: "Auto-Hide Left Panel"
                                            visible: Config.barMode === "tri" || Config.barMode === "shell"
                                            value: Config.triLeftAutoHide
                                            onToggled: function(v) {
                                                Config.triLeftAutoHide = v
                                            }
                                        }

                                        CCSlider {
                                            label: "Left Delay (s)"
                                            visible: Config.barMode === "tri" || Config.barMode === "shell"
                                            from: 1; to: 60; stepSize: 1
                                            value: Config.triLeftAutoHideDelay
                                            opacity: Config.triLeftAutoHide ? 1.0 : 0.4
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            onMoved: function(v) {
                                                Config.triLeftAutoHideDelay = v
                                            }
                                        }

                                        CCToggle {
                                            id: _triCenterAhToggle
                                            label: "Auto-Hide Center Panel"
                                            visible: Config.barMode === "tri" //-> || Config.barMode === "shell"
                                            value: Config.triCenterAutoHide
                                            onToggled: function(v) {
                                                Config.triCenterAutoHide = v
                                            }
                                        }

                                        CCSlider {
                                            label: "Center Delay (s)"
                                            visible: Config.barMode === "tri" //-> || Config.barMode === "shell"
                                            from: 1; to: 60; stepSize: 1
                                            value: Config.triCenterAutoHideDelay
                                            opacity: Config.triCenterAutoHide ? 1.0 : 0.4
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            onMoved: function(v) {
                                                Config.triCenterAutoHideDelay = v
                                            }
                                        }

                                        CCToggle {
                                            id: _triRightAhToggle
                                            label: "Auto-Hide Right Panel"
                                            visible: Config.barMode === "tri" || Config.barMode === "shell"
                                            value: Config.triRightAutoHide
                                            onToggled: function(v) {
                                                Config.triRightAutoHide = v
                                            }
                                        }

                                        CCSlider {
                                            label: "Right Delay (s)"
                                            visible: Config.barMode === "tri" || Config.barMode === "shell"
                                            from: 1; to: 60; stepSize: 1
                                            value: Config.triRightAutoHideDelay
                                            opacity: Config.triRightAutoHide ? 1.0 : 0.4
                                            Behavior on opacity { NumberAnimation { duration: 120 } }
                                            onMoved: function(v) {
                                                Config.triRightAutoHideDelay = v
                                            }
                                        }

                                        Item { height: 6 }
                                        CCSection { text: "Show / Hide Modules" }
                                        CCToggle { label:"Clock";          value:Config.showClock;          onToggled:function(v){Config.showClock=v} }
                                        CCToggle { label:"Date";           value:Config.showDate;           onToggled:function(v){Config.showDate=v} }
                                        CCToggle { label:"Workspaces";     value:Config.showWorkspaces;     onToggled:function(v){Config.showWorkspaces=v} }
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
                                        CCToggle { label:"Updates";        value:Config.showUpdates;        onToggled:function(v){Config.showUpdates=v} }
                                        CCToggle { label:"Power Profiles"; value:Config.showPowerProfiles;  onToggled:function(v){Config.showPowerProfiles=v} }
                                        CCToggle { label:"Overview";       value:Config.showOverview;       onToggled:function(v){Config.showOverview=v} }
                                        CCToggle { label:"Notifications";  value:Config.showNotifications;  onToggled:function(v){Config.showNotifications=v} }
                                        CCToggle { label:"Wallpaper Btn";  value:Config.showWallpaper;      onToggled:function(v){Config.showWallpaper=v} }
                                        CCToggle { label:"System Tray";    value:Config.showTray;           onToggled:function(v){Config.showTray=v} }
                                        //CCToggle { label:"Distro Icon";    value:Config.showDistro;         onToggled:function(v){Config.showDistro=v} }

                                        Item { height: 10 }
                                    }
                                }
                            }
                        }
                    }

                    // ── TAB 1: Hyprland ─────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 6

                            CCSection { text: "  Hyprland" }

                            // ── Desktop icon layer ────────────────────────────────
                            CCSection { text: "Desktop" }
                            CCToggle { label:"Show Icons";  value:Config.desktopVisible;   onToggled:function(v){ Config.desktopVisible=v } }
                            CCSlider { label:"Icon Size";  from:24; to:128; stepSize:4;
                                       value:Config.desktopIconSize;
                                       onMoved:function(v){ Config.desktopIconSize=v } }
                            CCSlider { label:"Label Size";   from:8;  to:20;  stepSize:1;
                                       value:Config.desktopLabelSize;
                                       onMoved:function(v){ Config.desktopLabelSize=v } }
                            CCSlider { label:"Label Radius"; from:0;  to:20;  stepSize:1;
                                       value:Config.desktopLabelRadius;
                                       onMoved:function(v){ Config.desktopLabelRadius=v } }

                            // ── Keyboard Layout ───────────────────────────────────
                            CCSection { text: "Keyboard Layout" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text {
                                    text: "Keyboard"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont; font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                Rectangle {
                                    Layout.preferredWidth: 40; height: 28; radius: 7
                                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.4)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                                    TextInput {
                                        id: _kbLayoutTI
                                        anchors { fill: parent; margins: 6 }
                                        text: ccWin._kbLayout
                                        color: Theme.cPrimary
                                        font.family: Config.labelFont; font.pixelSize: 12
                                        verticalAlignment: TextInput.AlignVCenter; clip: true
                                        onAccepted: {
                                            const v = text.trim()
                                            if (v.length === 0) return
                                            ccWin._kbLayout = v
                                            ccWin._writeHyprState("kb_layout", v)
                                            _kbLayoutSetProc.command = ["bash", "-c", "hyprctl reload 2>/dev/null || true"]
                                            _kbLayoutSetProc.running = true
                                        }
                                        Connections {
                                            target: ccWin
                                            function on_KbLayoutChanged() {
                                                if (!_kbLayoutTI.activeFocus) _kbLayoutTI.text = ccWin._kbLayout
                                            }
                                        }
                                    }
                                }
                            }
                            Process { id: _kbLayoutSetProc; running: false }

                            // ── Layout switcher ───────────────────────────────────
                            CCSection { text: "Layout" }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                Repeater {
                                    model: [
                                        { name: "Scrolling", key: "scrolling" },
                                        { name: "Dwindle",   key: "dwindle"   },
                                        { name: "Master",    key: "master"    },
                                        { name: "Monocle",   key: "monocle"   }
                                    ]
                                    delegate: CCPillBtn {
                                        required property var modelData
                                        text:   modelData.name
                                        active: ccWin._currentLayout === modelData.key
                                        onClicked: {
                                            ccWin._currentLayout = modelData.key
                                            _layoutProc.command = ["bash", "-c",
                                                // Persist to hyprviz.lua so the layout survives reload
                                                "f=\"$HOME/.config/hypr/hyprviz.lua\";" +
                                                "[ -f \"$f\" ] && sed -i" +
                                                "  's/\\(layout[[:space:]]*=[[:space:]]*\\)\"[^\"]*\"/\\1\"" + modelData.key + "\"/' \"$f\";" +
                                                // Apply immediately at runtime and reload so the
                                                // persisted value in hyprviz.lua takes effect
                                                "hyprctl keyword general:layout \"" + modelData.key + "\" 2>/dev/null;" +
                                                "hyprctl reload"
                                            ]
                                            _layoutProc.running = true
                                        }
                                    }
                                }
                            }
                            Process {
                                id: _layoutProc
                                running: false
                                onExited: {
                                    running = false
                                    // Re-read live layout after applying so highlight
                                    // always reflects actual Hyprland state
                                    _layoutReader.running = true
                                }
                            }
                            Process {
                                id: _layoutReader
                                command: ["bash", "-c",
                                    "hyprctl getoption general:layout 2>/dev/null | awk '/^str:/{print $2}'"]
                                running: false
                                property string _buf: ""
                                onRunningChanged: if (running) _buf = ""
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const t = l.trim()
                                        if (t) _layoutReader._buf = t
                                    }
                                }
                                onExited: {
                                    const v = _layoutReader._buf.trim().toLowerCase()
                                    if (v) ccWin._currentLayout = v
                                }
                            }

                            CCSection { text: "Color picker & X-Ray" }
                            
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
                            
                            CCSection { text: "Opacity & Blur" }

                            // ── Opacity slider ───────────────────────────────────
                            CCSlider {
                                label: "Opacity"
                                from: 0.0; to: 1.0; stepSize: 0.05; decimals: 2
                                value: ccWin.hyprOpacVal
                                onMoved: function(v) {
                                    ccWin._hyprOpacSlider = v
                                    ccWin._writeHyprState("opacity", v.toFixed(2))
                                    _opacSet.command = [scriptDir + "/hyprland-opacity-set.sh", v.toFixed(2)]
                                    _opacSet.running = true
                                }
                            }
                            Process { id: _opacSet; running: false }

                            // ── Blur Size slider ─────────────────────────────────
                            CCSlider {
                                label: "Blur Size"
                                from: 0; to: 20; stepSize: 1; decimals: 0
                                value: ccWin.hyprBlurSzVal
                                onMoved: function(v) {
                                    ccWin._hyprBlurSzSlider = v
                                    ccWin._writeHyprState("blur_size", Math.round(v).toString())
                                    _blurSizeSet.command = [scriptDir + "/hyprland-blur-size-set.sh", Math.round(v).toString()]
                                    _blurSizeSet.running = true
                                }
                            }
                            Process { id: _blurSizeSet; running: false }

                            // ── Blur Passes slider ───────────────────────────────
                            CCSlider {
                                label: "Blur Passes"
                                from: 0; to: 10; stepSize: 1; decimals: 0
                                value: ccWin.hyprBlurPsVal
                                onMoved: function(v) {
                                    ccWin._hyprBlurPsSlider = v
                                    ccWin._writeHyprState("blur_passes", Math.round(v).toString())
                                    _blurPassesSet.command = [scriptDir + "/hyprland-blur-passes-set.sh", Math.round(v).toString()]
                                    _blurPassesSet.running = true
                                }
                            }
                            Process { id: _blurPassesSet; running: false }

                            // ── Gaps & Border ─────────────────────────────────────
                            CCSection { text: "Gaps & Border" }

                            // Inner Gaps slider
                            CCSlider {
                                label: "Inner Gaps"
                                from: 0; to: 60; stepSize: 1; decimals: 0
                                value: ccWin.hyprGapsInVal
                                onMoved: function(v) {
                                    ccWin._hyprGapsInSlider = v
                                    ccWin._writeHyprState("gaps_in", Math.round(v).toString())
                                    _gapsInnerSet.command = [scriptDir + "/hyprland-gaps-inner-set.sh", Math.round(v).toString()]
                                    _gapsInnerSet.running = true
                                }
                            }
                            Process { id: _gapsInnerSet; running: false; onExited: { running = false; _hyprlandValReader.running = true } }

                            // Outer Gaps slider
                            CCSlider {
                                label: "Outer Gaps"
                                from: 0; to: 80; stepSize: 1; decimals: 0
                                value: ccWin.hyprGapsOutVal
                                onMoved: function(v) {
                                    ccWin._hyprGapsOutSlider = v
                                    ccWin._writeHyprState("gaps_out", Math.round(v).toString())
                                    _gapsOuterSet.command = [scriptDir + "/hyprland-gaps-outer-set.sh", Math.round(v).toString()]
                                    _gapsOuterSet.running = true
                                }
                            }
                            Process { id: _gapsOuterSet; running: false; onExited: { running = false; _hyprlandValReader.running = true } }

                            // Border Width slider
                            CCSlider {
                                label: "Border W"
                                from: 0; to: 10; stepSize: 1; decimals: 0
                                value: ccWin.hyprBorderWVal
                                onMoved: function(v) {
                                    ccWin._hyprBorderWSlider = v
                                    ccWin._writeHyprState("border_size", Math.round(v).toString())
                                    _borderWSet.command = [scriptDir + "/hyprland-border-width-set.sh", Math.round(v).toString()]
                                    _borderWSet.running = true
                                }
                            }
                            Process { id: _borderWSet; running: false; onExited: { running = false; _hyprlandValReader.running = true } }

                            // Border Radius (Rounding) slider
                            CCSlider {
                                label: "Border R"
                                from: 0; to: 90; stepSize: 1; decimals: 0
                                value: ccWin.hyprBorderRVal
                                onMoved: function(v) {
                                    ccWin._hyprBorderRSlider = v
                                    ccWin._writeHyprState("rounding", Math.round(v).toString())
                                    _borderRSet.command = [scriptDir + "/hyprland-border-radius-set.sh", Math.round(v).toString()]
                                    _borderRSet.running = true
                                }
                            }
                            Process { id: _borderRSet; running: false; onExited: { running = false; _hyprlandValReader.running = true } }

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

                            // ── Border Colors ──────────────────────────────────────
                            CCSection { text: "Border Colors" }
                            Text {
                                Layout.fillWidth: true
                                text: "Matugen: follows matugen themes  •  Pywal: follows wal palette"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.48)
                                font.family: Config.labelFont; font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }

                            // ── Active Border ────────────────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text {
                                    text: "Active"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont; font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                // Three-button mode selector: Custom | Matugen | Pywal
                                Rectangle {
                                    Layout.preferredWidth: 144; height: 28; radius: 9
                                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                    Row {
                                        anchors.fill: parent; anchors.margins: 2; spacing: 2
                                        Repeater {
                                            model: ["matugen", "pywal"]
                                            delegate: Rectangle {
                                                required property string modelData
                                                property bool _sel: ccWin._activeBorderMode === modelData
                                                width: (parent.width - 4) / 2; height: parent.height; radius: 7
                                                color: _sel ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.82) 
                                                	    : "transparent"
                                                border.width: _sel ? 1 : 0
                                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                    color: _sel ? Theme.cOnSecondary : Theme.cPrimary
                                                    font.family: Config.labelFont; font.pixelSize: 12
                                                    font.weight: _sel ? 600 : 400
                                                }
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        ccWin._activeBorderMode = modelData
                                                        ccBorderColorSettings.activeBorderMode = modelData
                                                        if (modelData === "matugen") {
                                                            _activeBorderApply.command = [scriptDir + "/hyprland-border-active-set.sh", ccWin._activeBorderVar]
                                                            _activeBorderApply.running = true
                                                        } else if (modelData === "pywal") {
                                                            _activeBorderApply.command = [scriptDir + "/hyprland-border-active-set.sh", ccWin._activeBorderPywalVar]
                                                            _activeBorderApply.running = true
                                                        }
                                                    }
                                                }
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }
                                    }
                                }
                            }

                            // Active border content area — switches based on mode
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: ccWin._activeBorderMode === "matugen"
                                    ? (_activeMatugenLoader.item ? _activeMatugenLoader.item.height : 0)
                                    : (_activePywalLoader.item ? _activePywalLoader.item.height : 0)

                                // Matugen color swatches
                                Loader {
                                    id: _activeMatugenLoader
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    active: ccWin._activeBorderMode === "matugen"
                                    sourceComponent: ColumnLayout {
                                        spacing: 4
                                        //Text {
                                            //text: "  Matugen color:"
                                            //color: Theme.cOnSurfVar
                                            //font.family: Config.labelFont; font.pixelSize: 11
                                        //}
                                        Flow {
                                            Layout.fillWidth: true; spacing: 5
                                            Repeater {
                                                model: ccWin._matugenBorderVars
                                                delegate: Item {
                                                    required property var modelData
                                                    width: 28; height: 28
                                                    Rectangle {
                                                        anchors.fill: parent; radius: 6
                                                        color: ccWin._cavaThemeColorLocal(modelData.var)
                                                        border.width: ccWin._activeBorderVar === modelData.var ? 2 : 1
                                                        border.color: ccWin._activeBorderVar === modelData.var
                                                            ? Theme.cPrimary
                                                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                        ToolTip.visible: _matAHover.containsMouse
                                                        ToolTip.text: modelData.var
                                                        ToolTip.delay: 400
                                                        MouseArea {
                                                            id: _matAHover
                                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            hoverEnabled: true
                                                            onClicked: {
                                                                ccWin._activeBorderVar = modelData.var
                                                                ccBorderColorSettings.activeBorderVar = modelData.var
                                                                _activeBorderApply.command = [scriptDir + "/hyprland-border-active-set.sh", modelData.var]
                                                                _activeBorderApply.running = true
                                                            }
                                                        }
                                                        Behavior on border.width { NumberAnimation { duration: 100 } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Pywal color swatches
                                Loader {
                                    id: _activePywalLoader
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    active: ccWin._activeBorderMode === "pywal"
                                    sourceComponent: ColumnLayout {
                                        spacing: 4
                                        //Text {
                                            //text: "  Pywal color:"
                                            //color: Theme.cOnSurfVar
                                            //font.family: Config.labelFont; font.pixelSize: 11
                                        //}
                                        Flow {
                                            Layout.fillWidth: true; spacing: 5
                                            Repeater {
                                                model: ccWin._pywalBorderVars
                                                delegate: Item {
                                                    required property var modelData
                                                    width: 28; height: 28
                                                    Rectangle {
                                                        anchors.fill: parent; radius: 6
                                                        color: ccWin._resolvePywalColor(modelData.var)
                                                        border.width: ccWin._activeBorderPywalVar === modelData.var ? 2 : 1
                                                        border.color: ccWin._activeBorderPywalVar === modelData.var
                                                            ? Theme.cPrimary
                                                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                        ToolTip.visible: _pywalAHover.containsMouse
                                                        ToolTip.text: modelData.var
                                                        ToolTip.delay: 400
                                                        MouseArea {
                                                            id: _pywalAHover
                                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            hoverEnabled: true
                                                            onClicked: {
                                                                ccWin._activeBorderPywalVar = modelData.var
                                                                ccBorderColorSettings.activeBorderPywalVar = modelData.var
                                                                _activeBorderApply.command = [scriptDir + "/hyprland-border-active-set.sh", modelData.var]
                                                                _activeBorderApply.running = true
                                                            }
                                                        }
                                                        Behavior on border.width { NumberAnimation { duration: 100 } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                            }
                            Process { id: _activeBorderWrite; running: false; onExited: running = false }
                            Process { id: _activeBorderApply; running: false; onExited: running = false }

                            Item { height: 8 }

                            // ── Inactive Border ─────────────────────────────────────
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text {
                                    text: "Inactive"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont; font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                // Three-button mode selector: Custom | Matugen | Pywal
                                Rectangle {
                                    Layout.preferredWidth: 144; height: 28; radius: 9
                                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                    Row {
                                        anchors.fill: parent; anchors.margins: 2; spacing: 2
                                        Repeater {
                                            model: ["matugen", "pywal"]
                                            delegate: Rectangle {
                                                required property string modelData
                                                property bool _sel: ccWin._inactiveBorderMode === modelData
                                                width: (parent.width - 4) / 2; height: parent.height; radius: 7
                                                color: _sel ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.82) 
                                                	    : "transparent"
                                                border.width: _sel ? 1 : 0
                                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                Text {
                                                    anchors.centerIn: parent
                                                    text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                                    color: _sel ? Theme.cOnSecondary : Theme.cPrimary
                                                    font.family: Config.labelFont; font.pixelSize: 12
                                                    font.weight: _sel ? 600 : 400
                                                }
                                                MouseArea {
                                                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        ccWin._inactiveBorderMode = modelData
                                                        ccBorderColorSettings.inactiveBorderMode = modelData
                                                        if (modelData === "matugen") {
                                                            _inactiveBorderApply.command = [scriptDir + "/hyprland-border-inactive-set.sh", ccWin._inactiveBorderVar]
                                                            _inactiveBorderApply.running = true
                                                        } else if (modelData === "pywal") {
                                                            _inactiveBorderApply.command = [scriptDir + "/hyprland-border-inactive-set.sh", ccWin._inactiveBorderPywalVar]
                                                            _inactiveBorderApply.running = true
                                                        }
                                                    }
                                                }
                                                Behavior on color { ColorAnimation { duration: 120 } }
                                            }
                                        }
                                    }
                                }
                            }

                            // Inactive border content area
                            Item {
                                Layout.fillWidth: true
                                implicitHeight: ccWin._inactiveBorderMode === "matugen"
                                    ? (_inactiveMatugenLoader.item ? _inactiveMatugenLoader.item.height : 0)
                                    : (_inactivePywalLoader.item ? _inactivePywalLoader.item.height : 0)

                                // Matugen color swatches
                                Loader {
                                    id: _inactiveMatugenLoader
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    active: ccWin._inactiveBorderMode === "matugen"
                                    sourceComponent: ColumnLayout {
                                        spacing: 4
                                        //Text {
                                            //text: "  Matugen color:"
                                            //color: Theme.cOnSurfVar
                                            //font.family: Config.labelFont; font.pixelSize: 11
                                        //}
                                        Flow {
                                            Layout.fillWidth: true; spacing: 5
                                            Repeater {
                                                model: ccWin._matugenBorderVars
                                                delegate: Item {
                                                    required property var modelData
                                                    width: 28; height: 28
                                                    Rectangle {
                                                        anchors.fill: parent; radius: 6
                                                        color: ccWin._cavaThemeColorLocal(modelData.var)
                                                        border.width: ccWin._inactiveBorderVar === modelData.var ? 2 : 1
                                                        border.color: ccWin._inactiveBorderVar === modelData.var
                                                            ? Theme.cPrimary
                                                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                        ToolTip.visible: _matIHover.containsMouse
                                                        ToolTip.text: modelData.var
                                                        ToolTip.delay: 400
                                                        MouseArea {
                                                            id: _matIHover
                                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            hoverEnabled: true
                                                            onClicked: {
                                                                ccWin._inactiveBorderVar = modelData.var
                                                                ccBorderColorSettings.inactiveBorderVar = modelData.var
                                                                _inactiveBorderApply.command = [scriptDir + "/hyprland-border-inactive-set.sh", modelData.var]
                                                                _inactiveBorderApply.running = true
                                                            }
                                                        }
                                                        Behavior on border.width { NumberAnimation { duration: 100 } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Pywal color swatches
                                Loader {
                                    id: _inactivePywalLoader
                                    anchors { left: parent.left; right: parent.right; top: parent.top }
                                    active: ccWin._inactiveBorderMode === "pywal"
                                    sourceComponent: ColumnLayout {
                                        spacing: 4
                                        //Text {
                                            //text: "  Pywal color:"
                                            //color: Theme.cOnSurfVar
                                            //font.family: Config.labelFont; font.pixelSize: 11
                                        //}
                                        Flow {
                                            Layout.fillWidth: true; spacing: 5
                                            Repeater {
                                                model: ccWin._pywalBorderVars
                                                delegate: Item {
                                                    required property var modelData
                                                    width: 28; height: 28
                                                    Rectangle {
                                                        anchors.fill: parent; radius: 6
                                                        color: ccWin._resolvePywalColor(modelData.var)
                                                        border.width: ccWin._inactiveBorderPywalVar === modelData.var ? 2 : 1
                                                        border.color: ccWin._inactiveBorderPywalVar === modelData.var
                                                            ? Theme.cPrimary
                                                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                                        ToolTip.visible: _pywalIHover.containsMouse
                                                        ToolTip.text: modelData.var
                                                        ToolTip.delay: 400
                                                        MouseArea {
                                                            id: _pywalIHover
                                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                            hoverEnabled: true
                                                            onClicked: {
                                                                ccWin._inactiveBorderPywalVar = modelData.var
                                                                ccBorderColorSettings.inactiveBorderPywalVar = modelData.var
                                                                _inactiveBorderApply.command = [scriptDir + "/hyprland-border-inactive-set.sh", modelData.var]
                                                                _inactiveBorderApply.running = true
                                                            }
                                                        }
                                                        Behavior on border.width { NumberAnimation { duration: 100 } }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                            }
                            Process { id: _inactiveBorderWrite; running: false; onExited: running = false }
                            Process { id: _inactiveBorderApply; running: false; onExited: running = false }
                            Item { height: 10 }
                        }
                    }

                    // ── TAB 2: Themes ────────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            id: _themeTab
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 6
                            CCSection { text: " 󰔎 Matugen Themes" }

                            // ── Color Generation toggle ────────────────────────────
                            CCSection { text: "Color Generation" }
                            RowLayout {
                                Layout.fillWidth: true; spacing: 8

                                Text {
                                    text: "Process Matugen Colors"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont
                                    font.pixelSize: 13
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                }

                                // Pill toggle — mirrors CCPillBtn styling with active/idle states
                                Rectangle {
                                    id: _colorRegenPill
                                    implicitWidth: _colorRegenLabel.implicitWidth + 28
                                    implicitHeight: 28; radius: 9
                                    Layout.alignment: Qt.AlignVCenter

                                    property bool regenEnabled: ccColorRegenSettings.colorRegenEnabled

                                    color: regenEnabled
                                        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                  Theme.cPrimary.b, 0.82)
                                        : (_colorRegenMA.containsMouse
                                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                                            : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.16))
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                          Theme.cPrimary.b, regenEnabled ? 0.55 : 0.2)
                                    Behavior on color     { ColorAnimation { duration: 120 } }
                                    Behavior on border.color { ColorAnimation { duration: 120 } }

                                    Text {
                                        id: _colorRegenLabel
                                        anchors.centerIn: parent
                                        text: _colorRegenPill.regenEnabled ? " ON " : " OFF"
                                        color: _colorRegenPill.regenEnabled ? Theme.cOnSecondary : 
                                            (_colorRegenMA.containsMouse ? Theme.cOnSecondary : Theme.cPrimary)
                                        font.family: Config.labelFont
                                        font.pixelSize: 12
                                    }

                                    MouseArea {
                                        id: _colorRegenMA
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const nowEnabled = !_colorRegenPill.regenEnabled
                                            _colorRegenPill.regenEnabled = nowEnabled
                                            ccColorRegenSettings.colorRegenEnabled = nowEnabled
                                            // sed: comment/uncomment pywal + matugen lines (30-31) in the hook
                                            _colorRegenSedProc.command = [
                                                "bash", "-c",
                                                nowEnabled
                                                    ? 'f="$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh"; ' +
                                                      'sed -i \'33s/^#[[:space:]]*//' + "'" + ' "$f"'
                                                    : 'f="$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh"; ' +
                                                      'sed -i \'33s/^\\([^#]\\)/# \\1/' + "'" + ' "$f"'
                                            ]
                                            _colorRegenSedProc._runAfter = nowEnabled
                                            _colorRegenSedProc.running = true
                                        }
                                    }
                                }
                            }
                            
                            // Hint text — only visible when color generation is on
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                visible: _colorRegenPill.regenEnabled
                                text: " Matugen color palette will be reloaded on all theme and background changes"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.55)
                                font.family: Config.labelFont
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }

                            // Hint text — only visible when color generation is off
                            Text {
                                Layout.fillWidth: true
                                Layout.topMargin: 2
                                visible: !_colorRegenPill.regenEnabled
                                text: " Current color palette generation paused for matugen only"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.55)
                                font.family: Config.labelFont
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }

                            // sed writer — patches lines 30-31 of wallpaper_integration.sh
                            // _runAfter: set true by the click handler when enabling, so onExited
                            // chains into the integration script only after the uncomment lands.
                            Process {
                                id: _colorRegenSedProc
                                running: false
                                property bool _runAfter: false
                                onExited: {
                                    running = false
                                    if (_runAfter) {
                                        _runAfter = false
                                        _colorRegenRunProc.running = true
                                    }
                                }
                            }
                            // Runs the full integration script when re-enabling (live color refresh)
                            Process {
                                id: _colorRegenRunProc
                                command: [Quickshell.env("HOME") + "/.config/hyprcandy/hooks/wallpaper_integration.sh"]
                                running: false
                                onExited: running = false
                            }

                            // ── Light Mode button alone at top ─────────────────────────────────
                            CCSection { text: "Light Mode" }
                            RowLayout { Layout.fillWidth:true; spacing:5
                                CCPillBtn {
                                    text:"☀ Light"
                                    active: ccThemeSettings.currentTheme === "light"
                                    onClicked: {
                                        _themeProc.command = [scriptDir+"/theme-set.sh", "light"]
                                        _themeProc.running = true
                                        ccThemeSettings.currentTheme = "light"
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
                                        active: ccThemeSettings.currentTheme === modelData.scheme
                                        onClicked: {
                                            _themeProc.command = [scriptDir+"/theme-set.sh", modelData.scheme]
                                            _themeProc.running = true
                                            ccThemeSettings.currentTheme = modelData.scheme
                                        }
                                    }
                                }
                            }
                            // Re-read matugen-state after the script exits to catch any
                            // discrepancy between what we set and what the script actually wrote.
                            Process {
                                id: _themeProc
                                running: false
                                onExited: { running = false; _themeRead.running = true }
                            }
                            Process {
                                id: _themeRead
                                command: ["bash", "-c", "cat \"$HOME/.config/hyprcandy/matugen-state\" 2>/dev/null || echo scheme-content"]
                                running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v) ccThemeSettings.currentTheme = v
                                    }
                                }
                            }
                            
                            // ── Smart Mode button alone at top ─────────────────────────────────
                            CCSection { text: "Adaptive" }
                            Text {
                                Layout.fillWidth: true
                                text: "Matugen automatically determines which scheme and mode to apply based on the wallpaper"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.55)
                                font.family: Config.labelFont; font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                            RowLayout { Layout.fillWidth:true; spacing:5
                                CCPillBtn {
                                    text:" Smart"
                                    active: ccThemeSettings.currentTheme === "scheme-smart"
                                    onClicked: {
                                        _themeProc.command = [scriptDir+"/theme-set.sh", "scheme-smart"]
                                        _themeProc.running = true
                                        ccThemeSettings.currentTheme = "scheme-smart"
                                    }
                                }
                            }

                            // ── Window Background Alpha ────────────────────────────────────────
                            // Patches alpha(@on_secondary, N.NN) in both GTK matugen templates.
                            // Also derives the on_secondary RGB from the already-rendered
                            // qt5ct/qt6ct colors/matugen.conf (position 10 = Window role) and
                            // writes a matching rgba() into a window-alpha.qss stylesheet that
                            // qt5ct and qt6ct load via their stylesheets= key — giving Qt apps
                            // the same glass transparency without needing Darkly or KDE globals.
                            CCSection { text: "GTK Background Alpha" }
                            Text {
                                Layout.fillWidth: true
                                text: "GTK app window background color opacity independent from Hyprland opacity setting. Wait around 5 seconds before the next value change"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.55)
                                font.family: Config.labelFont; font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }
                            CCSlider {
                                label: "Window Alpha"
                                from: 0.10; to: 1.00; stepSize: 0.05; decimals: 2
                                value: ccWin._winBgAlpha >= 0 ? ccWin._winBgAlpha : 1.00
                                onMoved: function(v) {
                                    ccWin._winBgAlpha = v
                                    ccAppearanceSettings.winBgAlpha = v
                                    const a = v.toFixed(2)
                                    _winBgAlphaProc.command = ["bash", "-c",
                                        // ── GTK matugen templates ─────────────────────────────
                                        "for f in" +
                                        " \"$HOME/.config/matugen/templates/gtk3.css\"" +
                                        " \"$HOME/.config/matugen/templates/gtk4.css\"; do" +
                                        "  [ -f \"$f\" ] && sed -i -E" +
                                        "    \"s/alpha\\\\(@on_secondary, [0-9]+(\\\\.[0-9]+)?\\\\)/alpha(@on_secondary, " + a + ")/g\"" +
                                        "  \"$f\";" +
                                        "done;" +
                                        // ── Trigger GTK color rebuild ─────────────────────────
                                        "bash \"$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh\""
                                    ]
                                    _winBgAlphaProc.running = true
                                }
                            }
                            Process {
                                id: _winBgAlphaProc
                                running: false
                                onExited: running = false
                            }

                            Item { height:10 }
                        }
                    }

                    // ── TAB 3: Dock (hyprcandy-dock) ─────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 6
                            CCSection { text: " 󰇜 Dock" }

                            CCSection { text: "Screen Margin" }
                            CCSlider {
                                label: "Edge Gap"
                                from: 0; to: 40; stepSize: 1
                                value: _dockMarginVal
                                onMoved: function(v) {
                                    _dockMarginVal = v
                                    Config.dockMargin = v
                                    // Dedicated queued process — decoupled from both
                                    // _confWriteProc (Hyprland Lua state writer) and
                                    // _dockWrite (config.js writer). Queue ensures rapid
                                    // slider drags never drop the final value.
                                    const args = [scriptDir + "/dock-set.sh", "marginFromEdge", v.toString()]
                                    if (_dockMarginWrite.running) {
                                        _dockMarginWrite._pending = args
                                    } else {
                                        _dockMarginWrite.command = args
                                        _dockMarginWrite.running = true
                                    }
                                }
                            }
                            Process {
                                id: _dockMarginWrite
                                property var _pending: null
                                running: false
                                onExited: {
                                    running = false
                                    if (_pending !== null) {
                                        command = _pending
                                        _pending = null
                                        running = true
                                    }
                                }
                            }

                            CCSection { text: "Dock Auto-Hide" }

                            CCToggle {
                                id: _dockAhToggle
                                label: "Auto-Hide Dock"
                                value: _dockAhEnabled
                                onToggled: function(v) {
                                    _dockAhEnabled = v
                                    Config.dockAutoHide = v
                                    const cmd =
                                        "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
                                        "mkdir -p \"$(dirname $f)\"; " +
                                        "[ -f \"$f\" ] || printf '[bar]\nautohide=false\nautohide_delay=5\n\n[dock]\nautohide=false\nautohide_delay=5\nlayer=top\nmargin_from_edge=6\n' > \"$f\"; " +
                                        "grep -q '^\\[dock\\]' \"$f\" || printf '\\n[dock]\\nautohide=false\\nautohide_delay=5\\nlayer=top\\nmargin_from_edge=6\\n' >> \"$f\"; " +
                                        "grep -q '^autohide=' <(awk '/^\\[dock\\]/{s=1;next}/^\\[/{s=0}s' \"$f\") || sed -i '/^\\[dock\\]/a autohide=false' \"$f\"; " +
                                        "sed -i '/^\\[dock\\]/,/^\\[/{s/^autohide=.*/autohide=" + (v ? "true" : "false") + "/}' \"$f\"; " +
                                        "pkill -12 -f 'gjs dock-main.js' 2>/dev/null; true"
                                    if (_confWriteProc.running) {
                                        _confWriteProc._pendingCmd = cmd
                                    } else {
                                        _confWriteProc._cmd = cmd
                                        _confWriteProc.running = true
                                    }
                                }
                            }

                            CCSlider {
                                label: "Delay (s)"
                                from: 1; to: 60; stepSize: 1
                                value: Config.dockAutoHideDelay
                                opacity: _dockAhEnabled ? 1.0 : 0.4
                                Behavior on opacity { NumberAnimation { duration: 120 } }
                                onMoved: function(v) {
                                    _dockAhDelay = v.toString()
                                    Config.dockAutoHideDelay = v
                                    const cmd =
                                        "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
                                        "mkdir -p \"$(dirname $f)\"; " +
                                        "[ -f \"$f\" ] || printf '[bar]\nautohide=false\nautohide_delay=5\n\n[dock]\nautohide=false\nautohide_delay=5\nlayer=top\nmargin_from_edge=6\n' > \"$f\"; " +
                                        "grep -q '^\\[dock\\]' \"$f\" || printf '\\n[dock]\\nautohide=false\\nautohide_delay=5\\nlayer=top\\nmargin_from_edge=6\\n' >> \"$f\"; " +
                                        "grep -q '^autohide_delay=' <(awk '/^\\[dock\\]/{s=1;next}/^\\[/{s=0}s' \"$f\") || sed -i '/^\\[dock\\]/a autohide_delay=5' \"$f\"; " +
                                        "sed -i '/^\\[dock\\]/,/^\\[/{s/^autohide_delay=.*/autohide_delay=" + v + "/}' \"$f\"; " +
                                        "pkill -12 -f 'gjs dock-main.js' 2>/dev/null; true"
                                    if (_confWriteProc.running) {
                                        _confWriteProc._pendingCmd = cmd
                                    } else {
                                        _confWriteProc._cmd = cmd
                                        _confWriteProc.running = true
                                    }
                                }
                            }

                            // Cycle position — calls dock-cycle.sh which setsid-detaches from QS
                            CCPillBtn {
                                text: "󰶘 Cycle Position"
                                onClicked: {
                                    _dockCycle.command = [scriptDir + "/dock-cycle.sh"]
                                    _dockCycle.running = true
                                }
                            }
                            Process { id: _dockCycle; running: false; onExited: running = false }

                            // Spacing — sliders write directly via dock-set.sh
                            CCSlider {
                                label: "Spacing"
                                from: 0; to: 30; stepSize: 1
                                value: parseInt(_dockSpacingVal) || 0
                                onMoved: function(v) {
                                    _dockSpacingVal = v.toString()
                                    _dockWrite.command = [scriptDir + "/dock-set.sh", "buttonSpacing", v.toString()]
                                    _dockWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Padding"
                                from: 0; to: 20; stepSize: 1
                                value: parseInt(_dockPaddingVal) || 0
                                onMoved: function(v) {
                                    _dockPaddingVal = v.toString()
                                    _dockWrite.command = [scriptDir + "/dock-set.sh", "innerPadding", v.toString()]
                                    _dockWrite.running = true
                                }
                            }
                            CCSection { text: "Corner Radius" }
                            CCSlider {
                                label: "Top-Left"
                                from: 0; to: 60; stepSize: 1
                                value: parseInt(_dockBorderTLVal) || 0
                                onMoved: function(v) {
                                    _dockBorderTLVal = v.toString()
                                    _dockWrite.command = [scriptDir + "/dock-set.sh", "borderTopLeftRadius", v.toString()]
                                    _dockWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Top-Right"
                                from: 0; to: 60; stepSize: 1
                                value: parseInt(_dockBorderTRVal) || 0
                                onMoved: function(v) {
                                    _dockBorderTRVal = v.toString()
                                    _dockWrite.command = [scriptDir + "/dock-set.sh", "borderTopRightRadius", v.toString()]
                                    _dockWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Bottom-Left"
                                from: 0; to: 60; stepSize: 1
                                value: parseInt(_dockBorderBLVal) || 0
                                onMoved: function(v) {
                                    _dockBorderBLVal = v.toString()
                                    _dockWrite.command = [scriptDir + "/dock-set.sh", "borderBottomLeftRadius", v.toString()]
                                    _dockWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Bottom-Right"
                                from: 0; to: 60; stepSize: 1
                                value: parseInt(_dockBorderBRVal) || 0
                                onMoved: function(v) {
                                    _dockBorderBRVal = v.toString()
                                    _dockWrite.command = [scriptDir + "/dock-set.sh", "borderBottomRightRadius", v.toString()]
                                    _dockWrite.running = true
                                }
                            }
                            Process {
                                id: _dockWrite
                                property var _pending: null
                                running: false
                                onExited: {
                                    running = false
                                    if (_pending !== null) {
                                        command = _pending
                                        _pending = null
                                        running = true
                                    }
                                }
                            }
                            Process {
                                id: _dockBorderColorWrite
                                property var _pending: null
                                running: false
                                onExited: {
                                    running = false
                                    if (_pending !== null) {
                                        command = _pending
                                        _pending = null
                                        running = true
                                    } else {
                                        _dockReadBorderColor.running = true
                                    }
                                }
                            }

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
                            Process { id: _dockReadBorderTL; command: [scriptDir+"/dock-get.sh", "borderTopLeftRadius"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockBorderTLVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadBorderTR; command: [scriptDir+"/dock-get.sh", "borderTopRightRadius"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockBorderTRVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadBorderBL; command: [scriptDir+"/dock-get.sh", "borderBottomLeftRadius"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockBorderBLVal = v
                                    }
                                }
                            }
                            Process { id: _dockReadBorderBR; command: [scriptDir+"/dock-get.sh", "borderBottomRightRadius"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v && !isNaN(parseInt(v))) _dockBorderBRVal = v
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
                            Process { id: _dockReadBorderColor; command: [scriptDir+"/dock-border-get.sh"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v) _dockBorderColorVar = v
                                    }
                                }
                            }
                            Process { id: _dockReadRectBg; command: [scriptDir+"/dock-get.sh", "rectBgStyle"]; running: false
                                stdout: SplitParser {
                                    splitMarker: "\n"
                                    onRead: function(l) {
                                        const v = l.trim()
                                        if (v === "glass" || v === "gradient") _dockRectBgStyle = v
                                    }
                                }
                            }

                            // Start all dock reads on component complete
                            Timer {
                                interval: 100; running: true; repeat: false
                                onTriggered: {
                                    _dockReadSpacing.running  = true
                                    _dockReadPadding.running  = true
                                    _dockReadBorderW.running  = true
                                    _dockReadBorderTL.running = true
                                    _dockReadBorderTR.running = true
                                    _dockReadBorderBL.running = true
                                    _dockReadBorderBR.running = true
                                    _dockReadBorderColor.running = true
                                    _dockReadIconSize.running = true
                                    _dockReadStartIcon.running = true
                                    _dockReadRectBg.running   = true
                                    _confReadProc.running     = true
                                }
                            }
                            
                            Text {
                                Layout.fillWidth: true
                                text: "Toggle the 'Dock Reload' button when you're done making icon size changes"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.48)
                                font.family: Config.labelFont; font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }

                            CCSlider {
                                label: "Icon Size"
                                from: 18; to: 60; stepSize: 1
                                value: parseInt(_dockIconSizeVal) || 24
                                onMoved: function(v) {
                                    _dockIconSizeVal = v.toString()
                                    _dockIcon.command = [scriptDir + "/dock-icon-size.sh", v.toString()]
                                    _dockIcon.running = true
                                }
                            }
                            Process { id: _dockIcon; running: false; onExited: running = false }
                            
                            CCPillBtn {
                                text: "󰑓 Dock Reload"
                                onClicked: {
                                    _dockReload.command = [scriptDir + "/dock-reload.sh"]
                                    _dockReload.running = true
                                }
                            }
                            Process { id: _dockReload; running: false; onExited: running = false }

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

                    // ── TAB 4: Menus ─────────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 6
                            CCSection { text: " 󰮫 Menus" }

                            // ── Application Launcher ──────────────────────────────
                            CCSection { text: "Application Launcher" }

                            // Search bar width fraction (0.2–1.0) shown as a slider
                            // Sliders bind directly to Config.launcher* — same pattern as
                            // every other CC tab. onMoved sets the Config property (reactive,
                            // survives re-opens) AND calls launcher-config-set.sh to write the
                            // value back into launcherConfig.js for the GJS launcher to pick up.
                            CCSlider {
                                label: "Search Width"
                                from: 0.2; to: 1.0; stepSize: 0.05; decimals: 2
                                value: Config.launcherSearchWidth
                                onMoved: function(v) {
                                    Config.launcherSearchWidth = v
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "searchWidthFraction", v.toFixed(2)]
                                    _lcWrite.running = true
                                }
                            }

                            CCSection { text: "Icon" }
                            CCSlider {
                                label: "Icon Size"
                                from: 24; to: 96; stepSize: 4
                                value: Config.launcherIconSize
                                onMoved: function(v) {
                                    Config.launcherIconSize = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "iconSize", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Text Size"
                                from: 8; to: 16; stepSize: 1
                                value: Config.launcherTextFontSize
                                onMoved: function(v) {
                                    Config.launcherTextFontSize = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "textFontSize", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }

                            CCSection { text: "Tile Size (fixed container)" }
                            CCSlider {
                                label: "Tile Width"
                                from: 60; to: 150; stepSize: 5
                                value: Config.launcherFixedTileWidth
                                onMoved: function(v) {
                                    Config.launcherFixedTileWidth = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "fixedTileWidth", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Tile Height"
                                from: 50; to: 130; stepSize: 5
                                value: Config.launcherFixedTileHeight
                                onMoved: function(v) {
                                    Config.launcherFixedTileHeight = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "fixedTileHeight", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }

                            CCSection { text: "Window Size — Horizontal Dock App Launcher" }
                            CCSlider {
                                label: "Width"
                                from: 320; to: 2000; stepSize: 5
                                value: Config.launcherFrameWidth
                                onMoved: function(v) {
                                    Config.launcherFrameWidth = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "frameWidth", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Height"
                                from: 300; to: 2000; stepSize: 5
                                value: Config.launcherFrameHeight
                                onMoved: function(v) {
                                    Config.launcherFrameHeight = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "frameHeight", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }

                            CCSection { text: "Window Size — Vertical Dock App Launcher" }
                            CCSlider {
                                label: "Width"
                                from: 240; to: 2000; stepSize: 5
                                value: Config.launcherFrameWidthVert
                                onMoved: function(v) {
                                    Config.launcherFrameWidthVert = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "frameWidthVert", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Height"
                                from: 300; to: 2000; stepSize: 5
                                value: Config.launcherFrameHeightVert
                                onMoved: function(v) {
                                    Config.launcherFrameHeightVert = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "frameHeightVert", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }

                            CCSection { text: "Borders" }
                            CCSlider {
                                label: "Outer Radius"
                                from: 0; to: 40
                                value: Config.launcherBorderRadius
                                onMoved: function(v) {
                                    Config.launcherBorderRadius = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "borderRadius", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Outer Width"
                                from: 0; to: 8
                                value: Config.launcherBorderWidth
                                onMoved: function(v) {
                                    Config.launcherBorderWidth = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "borderWidth", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }
                            CCSlider {
                                label: "Search Radius"
                                from: 0; to: 30
                                value: Config.launcherSearchRadius
                                onMoved: function(v) {
                                    Config.launcherSearchRadius = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "searchRadius", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }
                            //CCSlider {
                                //label: "List Radius"
                                //from: 0; to: 30
                                //value: Config.launcherListRadius
                                //onMoved: function(v) {
                                    //Config.launcherListRadius = Math.round(v)
                                    //_lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        //"listRadius", Math.round(v).toString()]
                                    //_lcWrite.running = true
                                //}
                            //}
                            //CCSlider {
                                //label: "Inner Border W"
                                //from: 0; to: 4
                                //value: Config.launcherInnerBorderWidth
                                //onMoved: function(v) {
                                    //Config.launcherInnerBorderWidth = Math.round(v)
                                    //_lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        //"innerBorderWidth", Math.round(v).toString()]
                                    //_lcWrite.running = true
                                //}
                            //}

                            CCSection { text: "Padding" }
                            CCSlider {
                                label: "Inner Padding"
                                from: 0; to: 30
                                value: Config.launcherInnerPadding
                                onMoved: function(v) {
                                    Config.launcherInnerPadding = Math.round(v)
                                    _lcWrite.command = [scriptDir + "/launcher-config-set.sh",
                                        "innerPadding", Math.round(v).toString()]
                                    _lcWrite.running = true
                                }
                            }

                            // Shared writer — calls launcher-config-set.sh which writes
                            // directly into launcherConfig.js (the GJS launcher's source of truth).
                            Process { id: _lcWrite; running: false; onExited: running = false }

                            // ── Rofi (other menus — drun replaced by App Launcher) ──
                            CCSection { text: "Rofi (Other Menus)" }

                            CCSlider {
                                label: "Border"
                                from: 0; to: 10; stepSize: 1
                                value: parseInt(_rofiBorderVal) || 0
                                onMoved: function(v) {
                                    _rofiBorderVal = v.toString()
                                    _rofiBorder.command = [scriptDir + "/rofi-border.sh", v.toString()]
                                    _rofiBorder.running = true
                                }
                            }
                            Process { id: _rofiBorder; running: false }

                            CCSlider {
                                label: "Radius"
                                from: 0; to: 5; stepSize: 0.1; decimals: 1
                                value: parseFloat(_rofiRadiusVal) || 0
                                onMoved: function(v) {
                                    _rofiRadiusVal = v.toFixed(1)
                                    _rofiRadius.command = [scriptDir + "/rofi-radius.sh", v.toFixed(1)]
                                    _rofiRadius.running = true
                                }
                            }
                            Process { id: _rofiRadius; running: false }

                            Item { height: 10 }
                        }
                    }

                    // ── TAB 5: SDDM ──────────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 6
                            CCSection { text: " 󰍂 SDDM" }

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
                                label: "Width"
                                value: _sddmWidthVal
                                onApplied: function(v) {
                                    _sddmWidthVal = v
                                    _sddmWidth.command = [scriptDir + "/sddm-set.sh", "ScreenWidth", v, "sddm_width.state"]
                                    _sddmWidth.running = true
                                }
                            }
                            Process { id: _sddmWidth; running: false }

                            CCEntryRow {
                                label: "Height"
                                value: _sddmHeightVal
                                onApplied: function(v) {
                                    _sddmHeightVal = v
                                    _sddmHeight.command = [scriptDir + "/sddm-set.sh", "ScreenHeight", v, "sddm_height.state"]
                                    _sddmHeight.running = true
                                }
                            }
                            Process { id: _sddmHeight; running: false }

                            CCEntryRow {
                                label: "Font"
                                value: _sddmFontVal
                                onApplied: function(v) {
                                    _sddmFontVal = v
                                    _sddmFont.command = [scriptDir + "/sddm-set.sh", "Font", v, "sddm_font.state"]
                                    _sddmFont.running = true
                                }
                            }
                            Process { id: _sddmFont; running: false }

                            RowLayout {
                                Layout.fillWidth: true; spacing: 8
                                Text {
                                    text: "Form Pos"
                                    color: Theme.cPrimary
                                    font.family: Config.labelFont; font.pixelSize: 13
                                    Layout.preferredWidth: 100
                                }
                                Flow {
                                    spacing: 5
                                    Repeater {
                                        model: ["left", "center", "right"]
                                        delegate: CCPillBtn {
                                            required property string modelData
                                            text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                            active: _sddmFormVal === modelData
                                            onClicked: {
                                                _sddmFormVal = modelData
                                                _sddmForm.command = [scriptDir + "/sddm-set.sh", "FormPosition", modelData, "sddm_form.state"]
                                                _sddmForm.running = true
                                            }
                                        }
                                    }
                                }
                            }
                            Process { id: _sddmForm; running: false }

                            CCSlider {
                                label: "Blur R"
                                from: 0; to: 100; stepSize: 1; decimals: 0
                                value: parseInt(_sddmBlurVal) || 0
                                onMoved: function(v) {
                                    const n = Math.round(v)
                                    _sddmBlurVal = n.toString()
                                    _sddmBlur.command = [scriptDir + "/sddm-set.sh", "BlurRadius", n.toString(), "sddm_blur.state"]
                                    _sddmBlur.running = true
                                }
                            }
                            Process { id: _sddmBlur; running: false }

                            // Start all SDDM reads on tab render — same pattern as dock
                            Timer {
                                interval: 100; running: true; repeat: false
                                onTriggered: {
                                    _sddmReadHeader.running = true
                                    _sddmReadForm.running   = true
                                    _sddmReadBlur.running   = true
                                    _sddmReadWidth.running  = true
                                    _sddmReadHeight.running = true
                                    _sddmReadFont.running   = true
                                }
                            }

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

                    // ── TAB 6: HyprCandy+ ────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 6

                            // ── Status card ───────────────────────────────────
                            Rectangle {
                                Layout.fillWidth: true
                                height: 72; radius: 14
                                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                               Theme.cInversePrimary.b, 0.18)
                                border.width: 1
                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                      Theme.cPrimary.b, 0.22)
                                RowLayout {
                                    anchors { fill: parent; margins: 14 }
                                    spacing: 12
                                    Rectangle {
                                        width: 10; height: 10; radius: 5
                                        color: ccWin._licStatus === "active"  ? "#4caf50"
                                             : ccWin._licStatus === "invalid" ? Theme.cErr
                                             : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                       Theme.cPrimary.b, 0.3)
                                        Behavior on color { ColorAnimation { duration: 300 } }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true; spacing: 2
                                        Text {
                                            text: ccWin._licStatus === "active"  ? "HyprCandy+ Active"
                                                : ccWin._licStatus === "invalid" ? "License Invalid"
                                                : "HyprCandy+"
                                            color: Theme.cPrimary
                                            font.family: Config.labelFont
                                            font.pixelSize: 14; font.weight: Font.Bold
                                        }
                                        Text {
                                            text: ccWin._licStatus === "active"
                                                ? (ccWin._licEmail !== "" ? "Licensed by " + ccWin._licEmail : "Subscription active")
                                                : ccWin._licStatus === "invalid"
                                                    ? (ccWin._licError !== "" ? ccWin._licError : "Key not recognised")
                                                    : "Enter your licence key to activate"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.6)
                                            font.family: Config.labelFont; font.pixelSize: 11
                                            Layout.fillWidth: true; wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }

                            Text {
                                visible: ccWin._licLastChecked !== ""
                                text: "Last verified: " + (ccWin._licLastChecked !== ""
                                    ? new Date(ccWin._licLastChecked).toLocaleDateString() : "—")
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.38)
                                font.family: Config.labelFont; font.pixelSize: 10
                            }

                            Rectangle {
                                visible: ccWin._licKeyInput !== "" && ccWin._licStatus !== "active"
                                height: 28
                                implicitWidth: _clrKeyLbl.implicitWidth + 18
                                radius: 8
                                color: _clrKeyHov.containsMouse
                                    ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.22)
                                    : Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.10)
                                border.width: 1
                                border.color: Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.42)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                Text {
                                    id: _clrKeyLbl; anchors.centerIn: parent
                                    text: "Remove Key"; color: Theme.cErr
                                    font.family: Config.labelFont; font.pixelSize: 11
                                }
                                MouseArea {
                                    id: _clrKeyHov; anchors.fill: parent
                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        ccWin._licKeyInput    = ""
                                        ccWin._licStatus      = ""
                                        ccWin._licEmail       = ""
                                        ccWin._licLastChecked = ""
                                        ccWin._licError       = ""
                                        ccLicenseSettings.licenseKey    = ""
                                        ccLicenseSettings.licenseStatus = ""
                                        ccLicenseSettings.licensedEmail = ""
                                        ccLicenseSettings.lastVerified  = ""
                                        _licKeyTI.text = ""
                                    }
                                }
                            }

                            CCSection { text: "♥️ Support HyprCandy" }

                            Text {
                                Layout.fillWidth: true
                                text: "Enjoying hyprcandy? A Ko-fi tip helps keep development going — thank you!"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.55)
                                font.family: Config.labelFont; font.pixelSize: 11
                                wrapMode: Text.Wrap
                            }

                            Item {
                                Layout.fillWidth: true
                                height: 52
                                Image {
                                    id: _kofiBtnImg
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 44
                                    width: height * (sourceSize.width > 0 && sourceSize.height > 0
                                        ? sourceSize.width / sourceSize.height : 2.6)
                                    fillMode: Image.PreserveAspectFit
                                    smooth: true
                                    source: "file://" + scriptDir + "/../assets/kofi-support.png"
                                }
                                MouseArea {
                                    anchors.fill: _kofiBtnImg
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: _openKofi.running = true
                                }
                            }

                            Process {
                                id: _openKofi
                                command: ["xdg-open", "https://ko-fi.com/ianmking"]
                                running: false
                                onExited: running = false
                            }

                            Item { height: 10 }
                        }
                    }

                    // ── TAB 7: Keybinds ──────────────────────────────────────
                    Item {
                        id: kbTabRoot

                        // ── Keybind data model ─────────────────────────────────────────────
                        // hyprviz binds (read-only from ~/.config/hypr/hyprviz.lua)
                        property var hyprvizBinds: []
                        // custom binds (read/write from ~/.config/custom/custom.lua)
                        property var customBinds:  []
                        // Editor state
                        property int  editingIdx:   -1   // -1 = new entry
                        property string editKeys:   ""
                        property string editCmd:    ""
                        property string editDesc:   ""
                        // Search / filter
                        property string kbFilter:   ""
                        // Sub-tab index (mirrored to/from ccTabSettings)
                        property int kbSubIdx: ccTabSettings.activeKbSubTab

                        // ── Lua line regex helper (pure JS) ─────────────────────────────
                        function parseBindLine(line) {
                            // Match: hl.bind("KEYS", ..., { description = "DESC" })
                            // or hl.bind("KEYS", hl.dsp.exec_cmd("CMD"), { description = "DESC" })
                            // Keys
                            const keysM = line.match(/hl\.bind\s*\(\s*"([^"]+)"/)
                            if (!keysM) return null
                            const keys = keysM[1]
                            // Description
                            const descM = line.match(/description\s*=\s*"([^"]*)"/)
                            const desc  = descM ? descM[1] : ""
                            // Command — try exec_cmd first, then whole second arg
                            let cmd = ""
                            const execM = line.match(/hl\.dsp\.exec_cmd\s*\(\s*"((?:[^"\\]|\\.)*)"\s*\)/)
                            if (execM) {
                                cmd = execM[1].replace(/\\"/g, '"').replace(/\\\\/g, '\\')
                            } else {
                                // Non-exec dispatch — extract the dispatch call text
                                const dispM = line.match(/hl\.bind\s*\(\s*"[^"]+"\s*,\s*(hl\.[^,\)]+)/)
                                if (dispM) cmd = dispM[1].trim()
                            }
                            return { keys: keys, cmd: cmd, desc: desc, raw: line }
                        }

                        // Build hl.bind line for custom.lua
                        function makeBindLine(keys, cmd, desc) {
                            const escapedCmd = cmd.replace(/\\/g, '\\\\').replace(/"/g, '\\"')
                            const escapedDesc = desc.replace(/"/g, '\\"')
                            return 'hl.bind("' + keys + '", hl.dsp.exec_cmd("' + escapedCmd + '"), { description = "' + escapedDesc + '" })'
                        }

                        // Serialise binds to custom.lua content.
                        // Pass an explicit array to avoid QML notification timing issues
                        // (e.g. after splice, the property assignment may not have propagated yet).
                        function buildCustomLua(binds) {
                            const src = binds !== undefined ? binds : kbTabRoot.customBinds
                            let lines = [
                                '--  ██████╗ █████╗ ███╗   ██╗██████╗ ██╗   ██╗',
                                '-- ██╔════╝██╔══██╗████╗  ██║██╔══██╗╚██╗ ██╔╝',
                                '-- ██║     ███████║██╔██╗ ██║██║  ██║ ╚████╔╝ ',
                                '-- ██║     ██╔══██║██║╚██╗██║██║  ██║  ╚██╔╝  ',
                                '-- ╚██████╗██║  ██║██║ ╚████║██████╔╝   ██║   ',
                                '--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝    ╚═╝   ',
                                '-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓',
                                '-- ┃                          User Settings                      ┃',
                                '-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛',
                                '-- [NOTE!!] Your personal settings added here are sourced in hyprland.lua.',
                                '',
                            ]
                            for (let i = 0; i < src.length; i++)
                                lines.push(kbTabRoot.makeBindLine(src[i].keys, src[i].cmd, src[i].desc))
                            lines.push('')
                            lines.push('return true')
                            return lines.join('\n')
                        }

                        // ── Processes ─────────────────────────────────────────────────────
                        // Read hyprviz.lua (keybinds section from line 1808 onwards)
                        Process {
                            id: _kbHyprvizReader
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/hypr/hyprviz.lua\"; " +
                                "[ -f \"$f\" ] && awk '/^-- Keybindings/,0' \"$f\" || true"]
                            running: false
                            property string _buf: ""
                            stdout: SplitParser {
                                splitMarker: "\n"
                                onRead: function(l) { _kbHyprvizReader._buf += l + "\n" }
                            }
                            onExited: {
                                const raw = _buf; _buf = ""
                                const lines = raw.split("\n")
                                const parsed = []
                                for (let i = 0; i < lines.length; i++) {
                                    const b = kbTabRoot.parseBindLine(lines[i].trim())
                                    if (b) parsed.push(b)
                                }
                                kbTabRoot.hyprvizBinds = parsed
                            }
                        }

                        // Read custom.lua
                        Process {
                            id: _kbCustomReader
                            command: ["bash", "-c",
                                "f=\"$HOME/.config/custom/custom.lua\"; " +
                                "[ -f \"$f\" ] && cat \"$f\" || true"]
                            running: false
                            property string _buf: ""
                            stdout: SplitParser {
                                splitMarker: "\n"
                                onRead: function(l) { _kbCustomReader._buf += l + "\n" }
                            }
                            onExited: {
                                const raw = _buf; _buf = ""
                                const lines = raw.split("\n")
                                const parsed = []
                                for (let i = 0; i < lines.length; i++) {
                                    const b = kbTabRoot.parseBindLine(lines[i].trim())
                                    if (b) parsed.push(b)
                                }
                                kbTabRoot.customBinds = parsed
                            }
                        }

                        // Write custom.lua — command is assigned imperatively (not as a
                        // declarative binding) so each call gets the current base64 payload.
                        // Quickshell snapshots declarative bindings at component creation,
                        // so a reactive binding on command would always use the initial empty _b64.
                        // btoa encodes content to base64 (alphanumeric+/+=) making it safe to
                        // single-quote in the shell command with zero escaping concerns.
                        // Atomic tmp→mv ensures no partial writes reach the file.
                        Process {
                            id: _kbCustomWriter
                            running: false
                            onExited: {
                                running = false
                                _kbReloadProc.running = true
                            }
                        }

                        // Reload Hyprland so new/edited/removed custom binds take effect immediately
                        Process {
                            id: _kbReloadProc
                            command: ["hyprctl", "reload"]
                            running: false
                            onExited: running = false
                        }

                        function saveToCustomLua(content) {
                            if (_kbCustomWriter.running) return
                            const b64 = Qt.btoa(content)
                            _kbCustomWriter.command = ["bash", "-c",
                                "mkdir -p \"$HOME/.config/custom\" && " +
                                "t=\"$(mktemp \"$HOME/.config/custom/.custom.lua.XXXXXX\")\" && " +
                                "printf '%s' '" + b64 + "' | base64 -d > \"$t\" && " +
                                "mv \"$t\" \"$HOME/.config/custom/custom.lua\""]
                            _kbCustomWriter.running = true
                        }

                        // Trigger reads when this tab becomes active
                        Connections {
                            target: ccTabSettings
                            function onActiveTabChanged() {
                                if (ccTabSettings.activeTab === 7) {
                                    _kbHyprvizReader.running = true
                                    _kbCustomReader.running  = true
                                }
                            }
                        }

                        // ── Layout ─────────────────────────────────────────────────────────
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6

                            // Sub-tab header row
                            Row {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: ["󰈈 View", "󰏫 Edit"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        required property int index
                                        property int _subIdx: kbSubStack.currentIndex
                                        height: 30
                                        implicitWidth: _kbStLabel.implicitWidth + 18
                                        radius: 9
                                        color: _subIdx === index
                                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                      Theme.cPrimary.b, 0.82)
                                            : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, 
                                            	      Theme.cOnSecondary, 0.15)
                                        border.width: _subIdx === index ? 1 : 0
                                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.42)
                                        Text {
                                            id: _kbStLabel; anchors.centerIn: parent
                                            text: modelData; color: _subIdx === index ? Theme.cOnSecondary : Theme.cPrimary
                                            font.family: Config.labelFont; font.pixelSize: 12
                                            font.weight: (index !== undefined && _subIdx === index) ? 600 : 400
                                        }
                                        MouseArea {
                                            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                kbSubStack.currentIndex = index
                                                ccTabSettings.activeKbSubTab = index
                                                kbTabRoot.kbSubIdx = index
                                            }
                                        }
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                    }
                                }

                                // Search field (only on View sub-tab)
                                Item { width: 10; visible: kbSubStack.currentIndex === 0 }
                                Rectangle {
                                    visible: kbSubStack.currentIndex === 0
                                    height: 30
                                    width: 180
                                    radius: 9
                                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                   Theme.cInversePrimary.b, 0.3)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                          Theme.cPrimary.b, 0.18)
                                    Row {
                                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                        spacing: 5
                                        Text {
                                            text: "󰍉"
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.5)
                                            font.family: Config.fontFamily; font.pixelSize: 13
                                            anchors.verticalCenter: parent.verticalCenter
                                        }
                                        Item {
                                            width: 140; height: 20
                                            TextInput {
                                                id: kbSearchInput
                                                anchors.fill: parent
                                                color: Theme.cPrimary
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                onTextChanged: kbTabRoot.kbFilter = text.toLowerCase()
                                                verticalAlignment: TextInput.AlignVCenter
                                            }
                                            Text {
                                                anchors.fill: parent
                                                text: "Search binds..."
                                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.8)
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                verticalAlignment: Text.AlignVCenter
                                                visible: kbSearchInput.text.length === 0
                                            }
                                        }
                                    }
                                }
                            }

                            // Separator
                            Rectangle {
                                Layout.fillWidth: true; height: 1
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                            }

                            // Sub-tab content
                            StackLayout {
                                id: kbSubStack
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                currentIndex: ccTabSettings.activeKbSubTab

                                // ── VIEW sub-tab ─────────────────────────────────
                                Item {
                                    Flickable {
                                        anchors.fill: parent
                                        contentWidth: width
                                        contentHeight: kbViewCol.implicitHeight + 20
                                        clip: true
                                        boundsBehavior: Flickable.StopAtBounds
                                        ScrollBar.vertical: ScrollBar {
                                            policy: ScrollBar.AsNeeded
                                            contentItem: Rectangle {
                                                implicitWidth: 3
                                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                                                radius: 2
                                            }
                                            background: Rectangle { color: "transparent" }
                                        }

                                        ColumnLayout {
                                            id: kbViewCol
                                            width: parent.width - 8
                                            anchors { left: parent.left; leftMargin: 2; top: parent.top; topMargin: 8 }
                                            spacing: 0

                                            // hyprviz.lua section
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 4; Layout.bottomMargin: 4
                                                Text {
                                                    text: "󰌌 hyprviz.lua"
                                                    color: Theme.cSurfaceTint
            					    opacity: 0.85
                                                    font.family: Config.labelFont
                                                    font.pixelSize: 15; font.weight: Font.Bold
                                                    font.letterSpacing: 0.5
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true; height: 1
                                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
                                                }
                                                Text {
                                                    text: "read-only"
                                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.42)
                                                    font.family: Config.labelFont; font.pixelSize: 10
                                                }
                                            }

                                            Repeater {
                                                model: {
                                                    const f = kbTabRoot.kbFilter
                                                    if (!f) return kbTabRoot.hyprvizBinds
                                                    return kbTabRoot.hyprvizBinds.filter(function(b) {
                                                        return b.keys.toLowerCase().indexOf(f) !== -1 ||
                                                               b.desc.toLowerCase().indexOf(f) !== -1 ||
                                                               b.cmd.toLowerCase().indexOf(f) !== -1
                                                    })
                                                }
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    height: 44; radius: 9
                                                    color: index % 2 === 0
                                                        ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                  Theme.cInversePrimary.b, 0.09)
                                                        : "transparent"
                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                                        spacing: 8
                                                        // Key badge
                                                        Rectangle {
                                                            height: 24
                                                            implicitWidth: _kbKeyLbl.implicitWidth + 16
                                                            radius: 6
                                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                           Theme.cPrimary.b, 0.14)
                                                            border.width: 1
                                                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                                  Theme.cPrimary.b, 0.28)
                                                            Text {
                                                                id: _kbKeyLbl
                                                                anchors.centerIn: parent
                                                                text: modelData.keys
                                                                color: Theme.cPrimary
                                                                font.family: Config.labelFont
                                                                font.pixelSize: 11; font.weight: Font.Medium
                                                            }
                                                        }
                                                        // Description
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.desc !== "" ? modelData.desc : modelData.cmd
                                                            color: Theme.cPrimary
                                                            font.family: Config.labelFont; font.pixelSize: 12
                                                            elide: Text.ElideRight
                                                            opacity: 0.85
                                                        }
                                                    }
                                                }
                                            }

                                            // custom.lua section
                                            RowLayout {
                                                Layout.fillWidth: true
                                                Layout.topMargin: 14; Layout.bottomMargin: 4
                                                Text {
                                                    text: "󰏫 custom.lua"
                                                    color: Theme.cSurfaceTint
            					    opacity: 0.85
                                                    font.family: Config.labelFont
                                                    font.pixelSize: 15; font.weight: Font.Bold
                                                    font.letterSpacing: 0.5
                                                }
                                                Rectangle {
                                                    Layout.fillWidth: true; height: 1
                                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
                                                }
                                                Text {
                                                    text: "editable"
                                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.42)
                                                    font.family: Config.labelFont; font.pixelSize: 10
                                                }
                                            }

                                            // Empty state for custom
                                            Text {
                                                visible: kbTabRoot.customBinds.length === 0
                                                Layout.fillWidth: true
                                                text: "No custom keybinds yet — add some in the Edit tab."
                                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.38)
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                horizontalAlignment: Text.AlignHCenter
                                                topPadding: 6; bottomPadding: 6
                                            }

                                            Repeater {
                                                model: {
                                                    const f = kbTabRoot.kbFilter
                                                    if (!f) return kbTabRoot.customBinds
                                                    return kbTabRoot.customBinds.filter(function(b) {
                                                        return b.keys.toLowerCase().indexOf(f) !== -1 ||
                                                               b.desc.toLowerCase().indexOf(f) !== -1 ||
                                                               b.cmd.toLowerCase().indexOf(f) !== -1
                                                    })
                                                }
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    Layout.fillWidth: true
                                                    height: 44; radius: 9
                                                    color: index % 2 === 0
                                                        ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                  Theme.cInversePrimary.b, 0.12)
                                                        : "transparent"
                                                    RowLayout {
                                                        anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                                        spacing: 8
                                                        // Key badge (accent for custom)
                                                        Rectangle {
                                                            height: 24
                                                            implicitWidth: _ckbKeyLbl.implicitWidth + 16
                                                            radius: 6
                                                            color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                           Theme.cInversePrimary.b, 0.38)
                                                            border.width: 1
                                                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                                  Theme.cPrimary.b, 0.40)
                                                            Text {
                                                                id: _ckbKeyLbl
                                                                anchors.centerIn: parent
                                                                text: modelData.keys
                                                                color: Theme.cPrimary
                                                                font.family: Config.labelFont
                                                                font.pixelSize: 11; font.weight: Font.Medium
                                                            }
                                                        }
                                                        // Description
                                                        Text {
                                                            Layout.fillWidth: true
                                                            text: modelData.desc !== "" ? modelData.desc : modelData.cmd
                                                            color: Theme.cPrimary
                                                            font.family: Config.labelFont; font.pixelSize: 12
                                                            elide: Text.ElideRight
                                                            opacity: 0.85
                                                        }
                                                        // Quick-edit button
                                                        Rectangle {
                                                            width: 26; height: 26; radius: 7
                                                            color: _qeHov.containsMouse
                                                                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                          Theme.cInversePrimary.b, 0.38)
                                                                : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                          Theme.cPrimary.b, 0.08)
                                                            Behavior on color { ColorAnimation { duration: 100 } }
                                                            Text {
                                                                anchors.centerIn: parent; text: "󰏫"
                                                                font.family: Config.fontFamily; font.pixelSize: 13
                                                                color: Theme.cPrimary
                                                            }
                                                            MouseArea {
                                                                id: _qeHov; anchors.fill: parent
                                                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                                onClicked: {
                                                                    kbTabRoot.editingIdx = index
                                                                    kbTabRoot.editKeys   = modelData.keys
                                                                    kbTabRoot.editCmd    = modelData.cmd
                                                                    kbTabRoot.editDesc   = modelData.desc
                                                                    kbSubStack.currentIndex = 1
                                                                    ccTabSettings.activeKbSubTab = 1
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Item { height: 12 }
                                        }
                                    }
                                }

                                // ── EDIT sub-tab ─────────────────────────────────
                                Item {
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 4
                                        spacing: 8

                                        // List of custom binds for selection/deletion
                                        Rectangle {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 180
                                            radius: 11
                                            color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                           Theme.cInversePrimary.b, 0.10)
                                            border.width: 1
                                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                  Theme.cPrimary.b, 0.16)
                                            clip: true

                                            Flickable {
                                                anchors { fill: parent; margins: 4 }
                                                contentWidth: width
                                                contentHeight: kbEditList.implicitHeight
                                                clip: true
                                                boundsBehavior: Flickable.StopAtBounds
                                                ScrollBar.vertical: ScrollBar {
                                                    policy: ScrollBar.AsNeeded
                                                    contentItem: Rectangle {
                                                        implicitWidth: 3
                                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                                                        radius: 2
                                                    }
                                                    background: Rectangle { color: "transparent" }
                                                }

                                                ColumnLayout {
                                                    id: kbEditList
                                                    width: parent.width - 8
                                                    spacing: 2

                                                    Text {
                                                        visible: kbTabRoot.customBinds.length === 0
                                                        text: "No custom binds — create one below"
                                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.38)
                                                        font.family: Config.labelFont; font.pixelSize: 11
                                                        Layout.fillWidth: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        topPadding: 8
                                                    }

                                                    Repeater {
                                                        model: kbTabRoot.customBinds
                                                        delegate: Rectangle {
                                                            required property var modelData
                                                            required property int index
                                                            Layout.fillWidth: true
                                                            height: 36; radius: 8
                                                            color: kbTabRoot.editingIdx === index
                                                                ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                          Theme.cInversePrimary.b, 0.50)
                                                                : (_kbRowHov.hovered
                                                                    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                              Theme.cInversePrimary.b, 0.22)
                                                                    : "transparent")
                                                            Behavior on color { ColorAnimation { duration: 100 } }

                                                            RowLayout {
                                                                anchors { fill: parent; leftMargin: 8; rightMargin: 6 }
                                                                spacing: 6
                                                                Text {
                                                                    text: modelData.keys
                                                                    color: Theme.cPrimary
                                                                    font.family: Config.labelFont
                                                                    font.pixelSize: 11; font.weight: Font.Medium
                                                                    Layout.preferredWidth: 130
                                                                    elide: Text.ElideRight
                                                                }
                                                                Text {
                                                                    Layout.fillWidth: true
                                                                    text: modelData.desc !== "" ? modelData.desc : modelData.cmd
                                                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.70)
                                                                    font.family: Config.labelFont; font.pixelSize: 11
                                                                    elide: Text.ElideRight
                                                                }
                                                                // Delete button
                                                                Rectangle {
                                                                    width: 22; height: 22; radius: 6
                                                                    color: _delHov.containsMouse
                                                                        ? Qt.rgba(1, 0.3, 0.3, 0.35)
                                                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.06)
                                                                    Behavior on color { ColorAnimation { duration: 100 } }
                                                                    Text {
                                                                        anchors.centerIn: parent; text: "󰅙"
                                                                        font.family: Config.fontFamily; font.pixelSize: 11
                                                                        color: _delHov.containsMouse ? "#ff6e6e" : Theme.cPrimary
                                                                    }
                                                                    MouseArea {
                                                                        id: _delHov; anchors.fill: parent
                                                                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                                        onClicked: {
                                                                            let arr = kbTabRoot.customBinds.slice()
                                                                            arr.splice(index, 1)
                                                                            // saveToCustomLua MUST be called before customBinds = arr.
                                                                            // Assigning customBinds triggers the Repeater to synchronously
                                                                            // destroy delegates — including this one — tearing down the JS
                                                                            // execution context so any code after the assignment never runs.
                                                                            kbTabRoot.saveToCustomLua(kbTabRoot.buildCustomLua(arr))
                                                                            kbTabRoot.customBinds = arr
                                                                            if (kbTabRoot.editingIdx === index) {
                                                                                kbTabRoot.editingIdx = -1
                                                                                kbTabRoot.editKeys = ""
                                                                                kbTabRoot.editCmd  = ""
                                                                                kbTabRoot.editDesc = ""
                                                                            }
                                                                        }
                                                                    }
                                                                }
                                                            }

                                                            // TapHandler on the delegate itself — fires only when the click
                                                            // is NOT handled by a child item (e.g. the delete button's MouseArea).
                                                            // Replaces the full-row MouseArea which sat above _delHov in z-order
                                                            // and swallowed every click before the delete button could see it.
                                                            TapHandler {
                                                                onTapped: {
                                                                    kbTabRoot.editingIdx = index
                                                                    kbTabRoot.editKeys   = modelData.keys
                                                                    kbTabRoot.editCmd    = modelData.cmd
                                                                    kbTabRoot.editDesc   = modelData.desc
                                                                }
                                                            }
                                                            HoverHandler { id: _kbRowHov }
                                                        }
                                                    }
                                                }
                                            }
                                        }

                                        // ── Entry form ─────────────────────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Text {
                                                text: kbTabRoot.editingIdx >= 0 ? "Editing #" + (kbTabRoot.editingIdx + 1) : "New Bind"
                                                color: Theme.cPrimary
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                font.weight: Font.Bold
                                            }
                                            Item { Layout.fillWidth: true }
                                            // Clear / new button
                                            Rectangle {
                                                height: 26
                                                implicitWidth: _newBtnLbl.implicitWidth + 18
                                                radius: 8
                                                color: _newBtnHov.containsMouse
                                                    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                              Theme.cInversePrimary.b, 0.38)
                                                    : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                              Theme.cInversePrimary.b, 0.18)
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Text {
                                                    id: _newBtnLbl; anchors.centerIn: parent
                                                    text: "󰐕 New"
                                                    color: Theme.cPrimary
                                                    font.family: Config.labelFont; font.pixelSize: 11
                                                }
                                                MouseArea {
                                                    id: _newBtnHov; anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        kbTabRoot.editingIdx = -1
                                                        kbTabRoot.editKeys = ""
                                                        kbTabRoot.editCmd  = ""
                                                        kbTabRoot.editDesc = ""
                                                    }
                                                }
                                            }
                                        }

                                        // Keys field
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text {
                                                text: "Keys"
                                                color: Theme.cPrimary
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                Layout.preferredWidth: 64
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true; height: 30; radius: 8
                                                color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, 
                                            	      Theme.cScrim.b, 0.15)
                                                border.width: kbKeysInput.activeFocus ? 1 : 0
                                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
                                                Item {
                                                    anchors { left: parent.left; right: parent.right
                                                              leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                                    height: 20
                                                    TextInput {
                                                        id: kbKeysInput
                                                        anchors.fill: parent
                                                        text: kbTabRoot.editKeys
                                                        color: Theme.cPrimary
                                                        font.family: Config.labelFont; font.pixelSize: 12
                                                        onTextChanged: kbTabRoot.editKeys = text
                                                        verticalAlignment: TextInput.AlignVCenter
                                                    }
                                                    Text {
                                                        anchors.fill: parent
                                                        text: "e.g. SUPER + T"
                                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.8)
                                                        font.family: Config.labelFont; font.pixelSize: 12
                                                        verticalAlignment: Text.AlignVCenter
                                                        visible: kbKeysInput.text.length === 0
                                                    }
                                                }
                                            }
                                        }

                                        // Command field
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text {
                                                text: "Command"
                                                color: Theme.cPrimary
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                Layout.preferredWidth: 64
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true; height: 30; radius: 8
                                                color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, 
                                            	      Theme.cScrim.b, 0.15)
                                                border.width: kbCmdInput.activeFocus ? 1 : 0
                                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
                                                Item {
                                                    anchors { left: parent.left; right: parent.right
                                                              leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                                    height: 20
                                                    TextInput {
                                                        id: kbCmdInput
                                                        anchors.fill: parent
                                                        text: kbTabRoot.editCmd
                                                        color: Theme.cPrimary
                                                        font.family: Config.labelFont; font.pixelSize: 12
                                                        onTextChanged: kbTabRoot.editCmd = text
                                                        verticalAlignment: TextInput.AlignVCenter
                                                    }
                                                    Text {
                                                        anchors.fill: parent
                                                        text: "e.g. kitty"
                                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.8)
                                                        font.family: Config.labelFont; font.pixelSize: 12
                                                        verticalAlignment: Text.AlignVCenter
                                                        visible: kbCmdInput.text.length === 0
                                                    }
                                                }
                                            }
                                        }

                                        // Description field
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 8
                                            Text {
                                                text: "Describe"
                                                color: Theme.cPrimary
                                                font.family: Config.labelFont; font.pixelSize: 12
                                                Layout.preferredWidth: 64
                                            }
                                            Rectangle {
                                                Layout.fillWidth: true; height: 30; radius: 8
                                                color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, 
                                            	      Theme.cScrim.b, 0.15)
                                                border.width: kbDescInput.activeFocus ? 1 : 0
                                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
                                                Item {
                                                    anchors { left: parent.left; right: parent.right
                                                              leftMargin: 8; rightMargin: 8; verticalCenter: parent.verticalCenter }
                                                    height: 20
                                                    TextInput {
                                                        id: kbDescInput
                                                        anchors.fill: parent
                                                        text: kbTabRoot.editDesc
                                                        color: Theme.cPrimary
                                                        font.family: Config.labelFont; font.pixelSize: 12
                                                        onTextChanged: kbTabRoot.editDesc = text
                                                        verticalAlignment: TextInput.AlignVCenter
                                                    }
                                                    Text {
                                                        anchors.fill: parent
                                                        text: "What does this do?"
                                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.8)
                                                        font.family: Config.labelFont; font.pixelSize: 12
                                                        verticalAlignment: Text.AlignVCenter
                                                        visible: kbDescInput.text.length === 0
                                                    }
                                                }
                                            }
                                        }

                                        // Save / Cancel row
                                        RowLayout {
                                            Layout.fillWidth: true; spacing: 6

                                            Item { Layout.fillWidth: true }

                                            // Save button
                                            Rectangle {
                                                height: 32
                                                implicitWidth: _saveBtnLbl.implicitWidth + 22
                                                radius: 9
                                                color: _saveBtnHov.containsMouse
                                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.70)
                                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                              Theme.cPrimary.b, 0.45)
                                                border.width: 1
                                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                      Theme.cPrimary.b, 0.18)
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                Text {
                                                    id: _saveBtnLbl; anchors.centerIn: parent
                                                    text: kbTabRoot.editingIdx >= 0 ? "󰏫 Update" : "󰐕 Add Bind"
                                                    color: Theme.cOnSecondary
                                                    font.family: Config.labelFont; font.pixelSize: 12
                                                    font.weight: Font.Medium
                                                }
                                                MouseArea {
                                                    id: _saveBtnHov; anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const k = kbTabRoot.editKeys.trim()
                                                        const c = kbTabRoot.editCmd.trim()
                                                        const d = kbTabRoot.editDesc.trim()
                                                        if (k === "" || c === "") return
                                                        let arr = kbTabRoot.customBinds.slice()
                                                        const entry = { keys: k, cmd: c, desc: d, raw: "" }
                                                        if (kbTabRoot.editingIdx >= 0) {
                                                            arr[kbTabRoot.editingIdx] = entry
                                                        } else {
                                                            arr.push(entry)
                                                        }
                                                        // Build from arr before assigning to avoid notification timing issues
                                                        const content = kbTabRoot.buildCustomLua(arr)
                                                        kbTabRoot.customBinds = arr
                                                        kbTabRoot.editingIdx  = -1
                                                        kbTabRoot.editKeys    = ""
                                                        kbTabRoot.editCmd     = ""
                                                        kbTabRoot.editDesc    = ""
                                                        kbTabRoot.saveToCustomLua(content)
                                                    }
                                                }
                                            }
                                        }

                                        Item { Layout.fillHeight: true }
                                    }
                                }
                            }
                        }
                    }

                    // ── TAB 8: Animations ───────────────────────────────────
                    Item {
                        id: animationsTabRoot

                        property var animations: []
                        property string currentAnimation: ""
                        property string applyingAnimation: ""
                        property string statusText: ""
                        property bool applyBusy: _animApplyProc.running

                        function reloadAnimations() {
                            if (_animListProc.running) _animListProc.running = false
                            Qt.callLater(function() { _animListProc.running = true })
                        }

                        Process {
                            id: _animListProc
                            command: [scriptDir + "/hyprcandy-animations.sh", "list"]
                            running: false
                            property var _buf: []
                            stdout: SplitParser {
                                splitMarker: "\n"
                                onRead: function(l) {
                                    const t = l.trim()
                                    if (t) _animListProc._buf.push(t)
                                }
                            }
                            onRunningChanged: if (running) _buf = []
                            onExited: function() {
                                const parsed = []
                                let current = ""
                                for (let i = 0; i < _buf.length; i++) {
                                    const parts = _buf[i].split("|")
                                    if (parts.length < 4) continue
                                    const row = {
                                        file: parts[0],
                                        label: parts[1],
                                        desc: parts[2],
                                        current: parts[3] === "true"
                                    }
                                    if (row.current) current = row.file
                                    parsed.push(row)
                                }
                                animationsTabRoot.animations = parsed
                                animationsTabRoot.currentAnimation = current
                                if (parsed.length === 0)
                                    animationsTabRoot.statusText = "No animation presets found in ~/.config/hypr/conf/animations."
                                else if (animationsTabRoot.statusText.indexOf("Applied ") !== 0)
                                    animationsTabRoot.statusText = "Select a preset to write ~/.config/hypr/animations.lua and reload Hyprland."
                            }
                        }

                        Process {
                            id: _animApplyProc
                            running: false
                            property string _target: ""
                            onExited: function(code) {
                                running = false
                                if (code === 0) {
                                    animationsTabRoot.currentAnimation = _target
                                    animationsTabRoot.statusText = "Applied " + _target + "."
                                } else {
                                    animationsTabRoot.statusText = "Failed to apply " + _target + "."
                                }
                                animationsTabRoot.applyingAnimation = ""
                                animationsTabRoot.reloadAnimations()
                            }
                        }

                        function applyAnimation(file) {
                            if (!file || _animApplyProc.running) return
                            applyingAnimation = file
                            statusText = "Applying " + file + "..."
                            _animApplyProc._target = file
                            _animApplyProc.command = [scriptDir + "/hyprcandy-animations.sh", "apply", file]
                            _animApplyProc.running = true
                        }

                        Connections {
                            target: ccTabSettings
                            function onActiveTabChanged() {
                                if (ccTabSettings.activeTab === 8)
                                    animationsTabRoot.reloadAnimations()
                            }
                        }

                        Component.onCompleted: reloadAnimations()

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 14
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    text: " 󰗘 Animations"
                                    color: Theme.cSurfaceTint
				    opacity: 0.85
                                    font.family: Config.labelFont
                                    font.pixelSize: 15
                                    font.weight: Font.Bold
                                }

                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 1
                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
                                }

                                Rectangle {
                                    height: 30
                                    implicitWidth: _animRefreshLbl.implicitWidth + 18
                                    radius: 9
                                    color: _animRefreshHov.containsMouse
                                        ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                  Theme.cInversePrimary.b, 0.38)
                                        : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                  Theme.cInversePrimary.b, 0.16)
                                    border.width: 1
                                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                          Theme.cPrimary.b, 0.20)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                    Text {
                                        id: _animRefreshLbl
                                        anchors.centerIn: parent
                                        text: _animListProc.running ? "󰔟 Loading" : "󰑐 Refresh"
                                        color: Theme.cPrimary
                                        font.family: Config.labelFont
                                        font.pixelSize: 12
                                    }
                                    MouseArea {
                                        id: _animRefreshHov
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: animationsTabRoot.reloadAnimations()
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: 1
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                            }

                            Text {
                                Layout.fillWidth: true
                                text: animationsTabRoot.statusText
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                               Theme.cPrimary.b, 0.55)
                                font.family: Config.labelFont
                                font.pixelSize: 11
                                wrapMode: Text.Wrap
                                bottomPadding: 4
                            }

                            Item {
                                Layout.fillWidth: true
                                Layout.fillHeight: true

                                Flickable {
                                    anchors.fill: parent
                                    contentWidth: width
                                    contentHeight: animationsListCol.implicitHeight + 20
                                    clip: true
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                        contentItem: Rectangle {
                                            implicitWidth: 3
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                                            radius: 2
                                        }
                                        background: Rectangle { color: "transparent" }
                                    }

                                    ColumnLayout {
                                        id: animationsListCol
                                        width: parent.width - 8
                                        anchors { left: parent.left; leftMargin: 2; top: parent.top; topMargin: 8 }
                                        spacing: 0

                                        Text {
                                            visible: animationsTabRoot.animations.length === 0
                                            Layout.fillWidth: true
                                            text: _animListProc.running
                                                ? "Loading animation presets..."
                                                : "No .conf animation presets were found."
                                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                           Theme.cPrimary.b, 0.38)
                                            font.family: Config.labelFont
                                            font.pixelSize: 12
                                            horizontalAlignment: Text.AlignHCenter
                                            topPadding: 18
                                            bottomPadding: 10
                                        }

                                        Repeater {
                                            model: animationsTabRoot.animations
                                            delegate: Rectangle {
                                                required property var modelData
                                                required property int index
                                                Layout.fillWidth: true
                                                height: 46
                                                radius: 9
                                                color: modelData.current
                                                    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                              Theme.cInversePrimary.b, 0.46)
                                                    : (_animRowHov.containsMouse
                                                        ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                  Theme.cInversePrimary.b, 0.22)
                                                        : (index % 2 === 0
                                                            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                      Theme.cInversePrimary.b, 0.10)
                                                            : "transparent"))
                                                border.width: modelData.current ? 1 : 0
                                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                      Theme.cPrimary.b, 0.38)
                                                Behavior on color { ColorAnimation { duration: 100 } }

                                                RowLayout {
                                                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                                                    spacing: 8

                                                    Rectangle {
                                                        height: 26
                                                        implicitWidth: _animNameLbl.implicitWidth + 16
                                                        radius: 7
                                                        color: modelData.current
                                                            ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                                      Theme.cInversePrimary.b, 0.50)
                                                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                      Theme.cPrimary.b, 0.14)
                                                        border.width: 1
                                                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                              Theme.cPrimary.b, 0.30)
                                                        Text {
                                                            id: _animNameLbl
                                                            anchors.centerIn: parent
                                                            text: modelData.label
                                                            color: Theme.cPrimary
                                                            font.family: Config.labelFont
                                                            font.pixelSize: 11
                                                            font.weight: Font.Medium
                                                        }
                                                    }

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: modelData.desc
                                                        color: Theme.cPrimary
                                                        font.family: Config.labelFont
                                                        font.pixelSize: 12
                                                        elide: Text.ElideRight
                                                        opacity: 0.85
                                                    }

                                                    Text {
                                                        visible: animationsTabRoot.applyingAnimation === modelData.file
                                                        text: "󰔟"
                                                        color: Theme.cPrimary
                                                        font.family: Config.fontFamily
                                                        font.pixelSize: 14
                                                        opacity: 0.7
                                                    }

                                                    Text {
                                                        visible: modelData.current && animationsTabRoot.applyingAnimation !== modelData.file
                                                        text: "current"
                                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                                       Theme.cPrimary.b, 0.50)
                                                        font.family: Config.labelFont
                                                        font.pixelSize: 10
                                                    }
                                                }

                                                MouseArea {
                                                    id: _animRowHov
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: _animApplyProc.running ? Qt.ForbiddenCursor : Qt.PointingHandCursor
                                                    enabled: !_animApplyProc.running
                                                    onClicked: animationsTabRoot.applyAnimation(modelData.file)
                                                }
                                            }
                                        }

                                        Item { height: 12 }
                                    }
                                }
                            }
                        }
                    }

                    // ── TAB 9: System ────────────────────────────────────────
                    CCScrollPane {
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.margins: 14
                            spacing: 10

                            CCSection { text: " 󰍛 System" }

                            // ── Fetch system info once when this tab becomes active ──
                            Item {
                                id: sysInfoRoot
                                Layout.fillWidth: true
                                Layout.preferredHeight: 1

                                property var info: ({})
                                property bool loaded: false

                                // Resolves distro PNG icon path from standard icon locations.
                                // Priority: /usr/share/pixmaps distro logo →
                                //           /usr/share/icons/hicolor/*/apps/distributor-logo →
                                //           /usr/share/icons/hicolor/*/places/distributor-logo →
                                //           "" (empty → Image falls back to visible-none)
                                // The LOGOICON field from /etc/os-release is tried first when present.
                                property string _distroIconPath: ""

                                // Fetched once alongside the rest of sysinfo; stored in info.LOGOICON
                                // and info.OSID so we can search systematically.

                                Process {
                                    id: sysInfoProc
                                    property var _buf: []
                                    running: false
                                    command: ["bash", "-c",
                                        // ── OS identity ──
                                        ". /etc/os-release 2>/dev/null; " +
                                        "OS_ID=${ID:-}; OS_NAME=${PRETTY_NAME:-Unknown}; LOGO=${LOGO:-}; " +
                                        "printf 'OSID:%s\n' \"$OS_ID\"; " +
                                        "printf 'OS:%s\n' \"$OS_NAME\"; " +
                                        // ── Distro PNG icon: search pixmaps + hicolor by OS_ID and LOGO hint ──
                                        "ICON_PATH=''; " +
                                        "ID_LOWER=$(echo \"${OS_ID}\" | tr '[:upper:]' '[:lower:]'); " +
                                        // Candidates: $LOGO hint → ID-based names → Arch fallback (CachyOS etc) → generic
                                        "for cand in \"$LOGO\" \"distributor-logo-${ID_LOWER}\" \"${ID_LOWER}-logo\" \"${ID_LOWER}\" \"distributor-logo-archlinux\" \"archlinux-logo\" \"distributor-logo\" \"logo\"; do " +
                                        "  [ -z \"$cand\" ] && continue; " +
                                        "  for ext in png svg; do f=\"/usr/share/pixmaps/${cand}.${ext}\"; [ -f \"$f\" ] && ICON_PATH=\"$f\" && break 2; done; " +
                                        "  for sz in 256x256 128x128 64x64 48x48 scalable; do " +
                                        "    for cat in apps places; do " +
                                        "      for ext in png svg; do f=\"/usr/share/icons/hicolor/${sz}/${cat}/${cand}.${ext}\"; [ -f \"$f\" ] && ICON_PATH=\"$f\" && break 3; done; " +
                                        "    done; " +
                                        "  done; " +
                                        "done; " +
                                        "printf 'LOGOICON:%s\n' \"$ICON_PATH\"; " +
                                        // ── System facts ──
                                        "printf 'HOST:%s\n' \"$(cat /sys/class/dmi/id/product_name 2>/dev/null || hostname)\"; " +
                                        "printf 'USERHOST:%s@%s\n' \"$(whoami)\" \"$(hostname)\"; " +
                                        "printf 'KERNEL:%s\n' \"$(uname -r)\"; " +
                                        "printf 'UPTIME:%s\n' \"$(cut -d. -f1 /proc/uptime)\"; " +
                                        "printf 'SHELL:%s\n' \"$(basename $SHELL)\"; " +
                                        "WMVER=$(hyprctl version 2>/dev/null | head -1 | grep -oP 'v[0-9.]+'); " +
                                        "printf 'WM:Hyprland %s\n' \"$WMVER\"; " +
                                        "printf 'CPU:%s\n' \"$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | sed 's/^ *//;s/(R)//g;s/(TM)//g;s/CPU//;s/  */ /g')\"; " +
                                        // ── GPUs: enumerate all cards with iGPU/dGPU heuristic (~ separator) ──
                                        // NVIDIA first
                                        "command -v nvidia-smi >/dev/null 2>&1 && " +
                                        "  nvidia-smi --query-gpu=name --format=csv,noheader,nounits 2>/dev/null " +
                                        "  | while read gname; do printf 'GPUINFO:%s~%s\n' \"${gname# }\" '0'; done; " +
                                        // AMD/Intel via driver symlinks — same heuristic as SystemMonitorPopup
                                        "for dp in /sys/class/drm/card*/device/driver; do " +
                                        "  [ -L \"$dp\" ] || continue; " +
                                        "  card=$(echo \"$dp\" | grep -oE 'card[0-9]+'); " +
                                        "  drv=$(readlink -f \"$dp\" 2>/dev/null | grep -oE '[^/]+$'); " +
                                        "  echo \"$drv\" | grep -qE '^(amdgpu|radeon|i915|xe)$' || continue; " +
                                        "  pci=$(cat /sys/class/drm/$card/device/address 2>/dev/null); " +
                                        "  pname=$(cat /sys/class/drm/$card/device/product_name 2>/dev/null); " +
                                        "  if [ -z \"$pname\" ] && [ -n \"$pci\" ]; then pname=$(lspci -D -s \"$pci\" 2>/dev/null | sed 's/.*: //'); fi; " +
                                        "  [ -z \"$pname\" ] && pname=$drv; " +
                                        "  is_igpu=0; " +
                                        "  if echo \"$drv\" | grep -qE '^(i915|xe)$'; then is_igpu=1; echo \"$pname\" | grep -qiE '\\bArc\\b|\\bAlchemist\\b|\\bBattlemage\\b' && is_igpu=0; fi; " +
                                        "  echo \"$pname\" | grep -qiE 'Radeon Graphics|RENOIR|CEZANNE|REMBRANDT|RAPHAEL|PHOENIX|BARCELO|MENDOCINO|HAWK.?POINT|STRIX.?POINT|780M|760M|740M|VEGA|Radeon RX Vega [0-9]' && is_igpu=1; " +
                                        "  printf 'GPUINFO:%s~%s\n' \"$pname\" \"$is_igpu\"; " +
                                        "done; " +
                                        "printf 'RAM:%s\n' \"$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%.1f / %.1f GiB\", (t-a)/1048576, t/1048576}' /proc/meminfo)\"; " +
                                        "printf 'RAMPCT:%s\n' \"$(awk '/MemTotal/{t=$2} /MemAvailable/{a=$2} END{printf \"%.0f\", (t-a)/t*100}' /proc/meminfo)\"; " +
                                        "printf 'DISK:%s\n' \"$(df -h / 2>/dev/null | awk 'NR==2{printf \"%s / %s\", $3, $2}')\"; " +
                                        "printf 'DISKPCT:%s\n' \"$(df -h / 2>/dev/null | awk 'NR==2{gsub(\"%\",\"\",$5); printf \"%s\", $5}')\"; " +
                                        "printf 'PKGS:%s\n' \"$(command -v pacman >/dev/null && pacman -Qq 2>/dev/null | wc -l || (command -v dpkg >/dev/null && dpkg -l 2>/dev/null | grep -c '^ii') || echo '?')\"; " +
                                        // ── Displays: all monitors, one DISPLAY:name|WxH@hz line each ──
                                        "hyprctl monitors 2>/dev/null | awk '" +
                                        "/^Monitor /{name=$2} " +
                                        "/^[[:space:]]+[0-9]+x[0-9]+@/{match($0,/([0-9]+x[0-9]+@[0-9.]+)/,a); printf \"DISPLAY:%s|%s\\n\",name,a[1]}'"
                                    ]
                                    stdout: SplitParser {
                                        splitMarker: "\n"
                                        onRead: function(line) {
                                            const i = line.indexOf(":")
                                            if (i < 0) return
                                            sysInfoProc._buf.push([line.slice(0, i), line.slice(i + 1)])
                                        }
                                    }
                                    onRunningChanged: if (running) _buf = []
                                    onExited: function() {
                                        const m = {}
                                        const gpus = []        // [{name, isIgpu}]
                                        const displays = []    // [{name, res}]
                                        for (const [k, v] of sysInfoProc._buf) {
                                            if (k === "GPUINFO") {
                                                // v = "name~is_igpu"  (~ tilde separator)
                                                const sep = v.indexOf("~")
                                                const gname   = sep >= 0 ? v.slice(0, sep) : v
                                                const isIgpu  = sep >= 0 && v.slice(sep + 1) === "1"
                                                // Clean verbose vendor prefixes (mirrors SystemMonitorPopup)
                                                const clean = gname
                                                    .replace(/Advanced Micro Devices[^,]*,?\s*/i, "")
                                                    .replace(/\bAMD\s+/i, "")
                                                    .replace(/ATI(\s+Technologies\s+Inc\.?)?\s*/i, "")
                                                    .replace(/Intel\s+Corporation\s*/i, "")
                                                    .replace(/\bIntel\s+/i, "")
                                                    .replace(/NVIDIA\s*GeForce\s*/i, "")
                                                    .replace(/\[([^\]]+)\]/g, "$1")
                                                    .replace(/\s+/g, " ").trim()
                                                gpus.push({ name: clean || gname || "GPU", isIgpu })
                                            } else if (k === "DISPLAY") {
                                                // v = "monitorName|WxH@hz"
                                                const bar = v.indexOf("|")
                                                const dname = bar >= 0 ? v.slice(0, bar) : v
                                                const res   = bar >= 0 ? v.slice(bar + 1) : v
                                                displays.push({ name: dname, res })
                                            } else {
                                                m[k] = v
                                            }
                                        }
                                        m._gpus    = gpus
                                        m._displays = displays
                                        sysInfoRoot.info = m
                                        sysInfoRoot._distroIconPath = m.LOGOICON || ""
                                        sysInfoRoot.loaded = true
                                    }
                                }

                                function _fmtUptime(sec) {
                                    sec = parseInt(sec) || 0
                                    const d = Math.floor(sec / 86400)
                                    const h = Math.floor((sec % 86400) / 3600)
                                    const m = Math.floor((sec % 3600) / 60)
                                    return d > 0 ? d+"d "+h+"h "+m+"m" : h > 0 ? h+"h "+m+"m" : m+"m"
                                }

                                Connections {
                                    target: ccTabSettings
                                    function onActiveTabChanged() {
                                        if (ccTabSettings.activeTab === 9 && !sysInfoRoot.loaded && !sysInfoProc.running)
                                            sysInfoProc.running = true
                                    }
                                }
                                Component.onCompleted: {
                                    if (ccTabSettings.activeTab === 9) sysInfoProc.running = true
                                }
                            }

                            // ── Header banner: distro icon + identity ────────────
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.preferredHeight: 92
                                radius: 18
                                clip: true
                                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                               Theme.cInversePrimary.b, 0.25)
                                border.width: 1
                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.20)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 22
                                    anchors.rightMargin: 18
                                    spacing: 18

                                    // Distro icon: PNG/SVG image when found, Nerd Font glyph fallback
                                    Item {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: 44
                                        implicitHeight: 44

                                        Image {
                                            id: distroImg
                                            anchors.fill: parent
                                            // Only set source when we have a path — empty source avoids
                                            // QML's broken-image ghost placeholder entirely.
                                            source: sysInfoRoot._distroIconPath.length > 0
                                                    ? "file://" + sysInfoRoot._distroIconPath
                                                    : ""
                                            visible: source.length > 0 && status === Image.Ready
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            // Clear path on load failure so fallback glyph takes over
                                            onStatusChanged: {
                                                if (status === Image.Error)
                                                    sysInfoRoot._distroIconPath = ""
                                            }
                                        }

                                        // Fallback Nerd Font glyph — shown whenever no image loaded
                                        Text {
                                            anchors.centerIn: parent
                                            visible: !distroImg.visible
                                            text: {
                                                const id = (sysInfoRoot.info.OSID || "").toLowerCase()
                                                const m = {
                                                    "arch": "", "cachyos": "",
                                                    "archcraft": "", "endeavouros": "",
                                                    "manjaro": "", "garuda": "",
                                                    "ubuntu": "", "debian": "",
                                                    "fedora": "", "linuxmint": "",
                                                    "opensuse": "", "opensuse-tumbleweed": "",
                                                    "gentoo": "", "void": "",
                                                    "nixos": "", "pop": "",
                                                    "alpine": "", "centos": "",
                                                    "rhel": "", "kali": "",
                                                    "raspbian": "", "artix": "",
                                                }
                                                return m[id] || ""
                                            }
                                            font.family: Config.fontFamily
                                            font.pixelSize: 44
                                            color: Theme.cWc6
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 3
                                        Text {
                                            text: sysInfoRoot.info.USERHOST || "—"
                                            color: Theme.cWc5
                                            font.family: Config.labelFont
                                            font.pixelSize: 17
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            text: sysInfoRoot.info.OS || "Loading…"
                                            color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.75)
                                            font.family: Config.labelFont
                                            font.pixelSize: 12
                                        }
                                        Text {
                                            text: (sysInfoRoot.info.WM || "Hyprland") +
                                                  "  ·  " + (sysInfoRoot.info.KERNEL || "—")
                                            color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.55)
                                            font.family: Config.labelFont
                                            font.pixelSize: 11
                                        }
                                    }

                                    // Uptime pill
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: upRow.implicitWidth + 24
                                        implicitHeight: 32
                                        radius: 16
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                                        RowLayout {
                                            id: upRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            Text {
                                                text: ""
                                                font.family: Config.fontFamily
                                                font.pixelSize: 13
                                                color: Theme.cPrimary
                                            }
                                            Text {
                                                text: sysInfoRoot.loaded ? sysInfoRoot._fmtUptime(sysInfoRoot.info.UPTIME) : "—"
                                                font.family: Config.labelFont
                                                font.pixelSize: 12
                                                font.weight: Font.DemiBold
                                                color: Theme.cPrimary
                                            }
                                        }
                                    }

                                    // Refresh button
                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: 32; implicitHeight: 32
                                        radius: 16
                                        color: refreshHov.containsMouse
                                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.10)
                                        Behavior on color { ColorAnimation { duration: 120 } }
                                        Text {
                                            id: refreshGlyph
                                            anchors.centerIn: parent
                                            text: "󰑐"
                                            font.family: Config.fontFamily
                                            font.pixelSize: 15
                                            color: Theme.cWc6
                                            RotationAnimator {
                                                target: refreshGlyph
                                                from: 0; to: 360
                                                duration: 900
                                                loops: Animation.Infinite
                                                running: sysInfoProc.running
                                            }
                                        }
                                        MouseArea {
                                            id: refreshHov
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (!sysInfoProc.running) sysInfoProc.running = true
                                        }
                                    }
                                }
                            }

                                // ── Bento grid: hardware stat cards ───────────────────
                            GridLayout {
                                Layout.fillWidth: true
                                columns: 2
                                columnSpacing: 10
                                rowSpacing: 10

                                SysStatCard {
                                    glyph: ""
                                    title: "Processor"
                                    value: sysInfoRoot.info.CPU || "—"
                                }

                                // GPU cards — one per detected GPU (iGPU and dGPU shown separately)
                                // Falls back to a single "Graphics" card with lspci output if _gpus is empty
                                Repeater {
                                    model: (sysInfoRoot.info._gpus && sysInfoRoot.info._gpus.length > 0)
                                           ? sysInfoRoot.info._gpus
                                           : [{ name: "—", isIgpu: false }]
                                    SysStatCard {
                                        required property var modelData
                                        glyph:  modelData.isIgpu ? "󱤓" : "󰢮"
                                        title:  modelData.isIgpu ? "GPU Driver" : "dGPU Driver"
                                        value:  modelData.name || "—"
                                    }
                                }

                                SysStatCard {
                                    glyph: ""
                                    title: "Memory"
                                    value: sysInfoRoot.info.RAM || "—"
                                    progress: parseInt(sysInfoRoot.info.RAMPCT || "0") / 100
                                }
                                SysStatCard {
                                    glyph: "󰉋"
                                    title: "Storage"
                                    value: sysInfoRoot.info.DISK || "—"
                                    progress: parseInt(sysInfoRoot.info.DISKPCT || "0") / 100
                                }
                            }

                            // ── Detail strip: smaller chip-style facts ────────────
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                spacing: 8

                                SysChip { glyph: "";  label: "Shell";    value: sysInfoRoot.info.SHELL || "—" }

                                // Display chips — one per monitor (name + resolution@hz)
                                Repeater {
                                    model: (sysInfoRoot.info._displays && sysInfoRoot.info._displays.length > 0)
                                           ? sysInfoRoot.info._displays
                                           : [{ name: "Display", res: sysInfoRoot.info.RES || "—" }]
                                    SysChip {
                                        required property var modelData
                                        glyph: "󰍹"
                                        label: modelData.name || "Display"
                                        value: modelData.res  || "—"
                                    }
                                }

                                SysChip { glyph: "󰏖"; label: "Packages"; value: sysInfoRoot.info.PKGS || "—" }
                                SysChip { glyph: "󰟀"; label: "Host";     value: sysInfoRoot.info.HOST || "—" }
                            }

                            Item { height: 4 }
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

        // Block all mouse/wheel events from reaching the CC panel behind this overlay.
        // Without this, scroll and drag gestures on the picker pass through to whatever
        // slider happens to sit at the same screen position, silently changing settings.
        MouseArea {
            anchors.fill: parent
            enabled: wpPickerOverlay.visible
            // Accept all buttons + wheel so nothing leaks through
            acceptedButtons: Qt.AllButtons
            onWheel: function(e) { e.accepted = true }
        }

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
                "   -fill white -draw 'roundrectangle 0,0 159,99 9,9' \\) " +
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
                            implicitWidth: 3; radius: 2
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
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
                                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                                   			Theme.cOnSecondary.b, 0.50)
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
                                        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                                   Theme.cInversePrimary.b, 0.18)
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
                                        // Open the avatar crop overlay instead of applying directly,
                                        // so the user can pan/position the image before committing.
                                        avatarCropOverlay.openWith(wpThumbItem.modelData)
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
    //  Avatar Crop Overlay
    //  Opens ABOVE the control center (z:11) after the user picks an image
    //  in the wallpaper picker.  Displays the full image inside a Flickable
    //  so the user can drag to pan, with a fixed circular 96×96 "aperture"
    //  that shows exactly what will become the avatar.
    //  "Set as avatar" computes the NorthWest-gravity offsets that reproduce
    //  the visible crop position and passes them to set-user-icon.sh.
    // ═══════════════════════════════════════════════════════════════════════
    Rectangle {
        id: avatarCropOverlay
        anchors.fill: panel
        z: 11
        visible: false
        radius: 20
        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                       Theme.cOnSecondary.b, 0.97)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g,
                              Theme.cOutVar.b, 0.40)
        clip: true

        scale: visible ? 1.0 : 0.94
        transformOrigin: Item.Top
        opacity: visible ? 1.0 : 0.0
        Behavior on scale   { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 140 } }

        // Block all mouse/wheel events from reaching the CC panel behind this overlay.
        MouseArea {
            anchors.fill: parent
            enabled: avatarCropOverlay.visible
            acceptedButtons: Qt.AllButtons
            onWheel: function(e) { e.accepted = true }
        }

        // ── Internal state ──────────────────────────────────────────────
        property string _srcPath: ""   // absolute path of source image
        property real   _imgNatW: 1    // natural (original) image dimensions
        property real   _imgNatH: 1
        // Scale factor applied by -resize 96x96^ (covers 96 px on shorter axis)
        // We mirror this in QML: the Flickable content is rendered at _scaledW × _scaledH
        // so that one display pixel = one ImageMagick pixel after the resize step.
        // The aperture is always 96×96 display px, matching the output size exactly.
        readonly property int   _aperture: 240          // display size of circular viewport
        readonly property real  _scaleFactor: {
            // Same maths as IM -resize 96x96^ : scale so the smaller dimension = 96
            // but we render bigger for a comfortable preview, so we use _aperture instead.
            if (_imgNatW <= 0 || _imgNatH <= 0) return 1
            return _aperture / Math.min(_imgNatW, _imgNatH)
        }
        readonly property real  _scaledW: _imgNatW * _scaleFactor
        readonly property real  _scaledH: _imgNatH * _scaleFactor

        // ── API ─────────────────────────────────────────────────────────
        function openWith(path) {
            _srcPath = path
            visible  = true
            // Reset pan to centre (mirrors IM -gravity center -extent 96x96)
            Qt.callLater(function() {
                // Centre the flickable so the middle of the image is inside
                // the aperture at startup — matches the old "centre crop" default.
                const maxX = Math.max(0, _scaledW - _aperture)
                const maxY = Math.max(0, _scaledH - _aperture)
                cropFlick.contentX = maxX / 2
                cropFlick.contentY = maxY / 2
            })
        }
        function _close() { visible = false; _srcPath = "" }

        // ── Probe image dimensions when src changes ─────────────────────
        // We use a hidden Image to read naturalWidth/naturalHeight.
        Image {
            id: _dimProbe
            source: avatarCropOverlay._srcPath
                ? ("file://" + avatarCropOverlay._srcPath)
                : ""
            visible: false
            fillMode: Image.Pad
            asynchronous: true
            cache: false
            onStatusChanged: {
                if (status === Image.Ready) {
                    avatarCropOverlay._imgNatW = sourceSize.width  || 1
                    avatarCropOverlay._imgNatH = sourceSize.height || 1
                }
            }
        }

        // ── Layout ──────────────────────────────────────────────────────
        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 12

            // ── Header ─────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Text {
                    text: "Crop Avatar"
                    color: Theme.cPrimary
                    font.family: Config.labelFont
                    font.pixelSize: 16; font.weight: Font.Bold
                }
                Item { Layout.fillWidth: true }
                // Close / cancel
                Rectangle {
                    width: 28; height: 28; radius: 14
                    color: _cropCloseHov.containsMouse
                        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.07)
                    Text {
                        anchors.centerIn: parent; text: "󰅙"
                        font.family: Config.fontFamily; font.pixelSize: 15
                        color: Theme.cPrimary
                    }
                    MouseArea {
                        id: _cropCloseHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: avatarCropOverlay._close()
                    }
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
            }

            // Hint
            Text {
                Layout.fillWidth: true
                text: "Drag the image to frame your avatar. The circle shows what will be saved."
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                font.family: Config.labelFont; font.pixelSize: 11
                wrapMode: Text.Wrap
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                               Theme.cPrimary.b, 0.18)
            }

            // ── Crop viewport — centred ─────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Flickable sits behind the aperture mask
                Flickable {
                    id: cropFlick
                    anchors.centerIn: parent
                    // Viewport is exactly aperture × aperture; clip hides what's outside
                    width:  avatarCropOverlay._aperture
                    height: avatarCropOverlay._aperture
                    clip: true

                    contentWidth:  avatarCropOverlay._scaledW
                    contentHeight: avatarCropOverlay._scaledH

                    // Clamp panning so the aperture never shows outside the image
                    boundsBehavior: Flickable.StopAtBounds
                    flickDeceleration: 3000

                    // The full image scaled to _scaledW × _scaledH
                    Image {
                        id: _cropImg
                        width:  avatarCropOverlay._scaledW
                        height: avatarCropOverlay._scaledH
                        source: avatarCropOverlay._srcPath
                            ? ("file://" + avatarCropOverlay._srcPath)
                            : ""
                        fillMode: Image.Stretch   // already sized explicitly
                        smooth: true; mipmap: true; asynchronous: true; cache: false
                    }
                }

                // ── Circular aperture mask (drawn over the Flickable) ───
                // Outer dim — darkens everything outside the circle
                Canvas {
                    id: _apertureCanvas
                    anchors.centerIn: parent
                    width:  avatarCropOverlay._aperture + 4   // tiny bleed for antialiasing
                    height: avatarCropOverlay._aperture + 4
                    // Redraws whenever theme changes
                    property color dimColor: Qt.rgba(0, 0, 0, 0.52)
                    onPaint: {
                        const ctx = getContext("2d")
                        const cx  = width  / 2
                        const cy  = height / 2
                        const r   = avatarCropOverlay._aperture / 2
                        ctx.clearRect(0, 0, width, height)
                        // Fill everything
                        ctx.fillStyle = Qt.rgba(0, 0, 0, 0.52)
                        ctx.fillRect(0, 0, width, height)
                        // Cut out the circle (destination-out)
                        ctx.globalCompositeOperation = "destination-out"
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, Math.PI * 2)
                        ctx.fill()
                        ctx.globalCompositeOperation = "source-over"
                    }
                    onDimColorChanged: requestPaint()
                }

                // Circle border ring drawn on top
                Rectangle {
                    anchors.centerIn: parent
                    width:  avatarCropOverlay._aperture
                    height: avatarCropOverlay._aperture
                    radius: avatarCropOverlay._aperture / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                         Theme.cPrimary.b, 0.75)
                }

                // Crosshair centre guides (subtle)
                Rectangle {
                    anchors.centerIn: parent
                    width: avatarCropOverlay._aperture; height: 1
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                   Theme.cPrimary.b, 0.15)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 1; height: avatarCropOverlay._aperture
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                   Theme.cPrimary.b, 0.15)
                }
            }

            // ── Confirm button ──────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 10
                Item { Layout.fillWidth: true }
                // Reset to centre button (secondary action)
                Rectangle {
                    height: 36
                    implicitWidth: _resetLbl.implicitWidth + 22; radius: 10
                    color: _resetHov.containsMouse
                        ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                  Theme.cInversePrimary.b, 0.38)
                        : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                  Theme.cInversePrimary.b, 0.16)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                          Theme.cPrimary.b, 0.28)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        id: _resetLbl; anchors.centerIn: parent
                        text: "󰒔  Reset"; color: Theme.cPrimary
                        font.family: Config.labelFont; font.pixelSize: 12
                    }
                    MouseArea {
                        id: _resetHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            const maxX = Math.max(0, avatarCropOverlay._scaledW - avatarCropOverlay._aperture)
                            const maxY = Math.max(0, avatarCropOverlay._scaledH - avatarCropOverlay._aperture)
                            cropFlick.contentX = maxX / 2
                            cropFlick.contentY = maxY / 2
                        }
                    }
                }
                // Primary confirm button
                Rectangle {
                    height: 36
                    implicitWidth: _setLbl.implicitWidth + 28; radius: 10
                    color: _setHov.containsMouse
                        ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                  Theme.cInversePrimary.b, 0.82)
                        : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                  Theme.cInversePrimary.b, 0.55)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                          Theme.cPrimary.b, 0.55)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        id: _setLbl; anchors.centerIn: parent
                        text: "󰀄  Set as avatar"; color: Theme.cPrimary
                        font.family: Config.labelFont; font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: _setHov; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // Compute NorthWest pixel offsets in the IM-resized image.
                            // cropFlick.contentX/Y are display pixels in our _scaledW×_scaledH
                            // coordinate space.  Divide by _scaleFactor to get the pixel
                            // position in the IM-resized 96×96^ image (same scale IM uses),
                            // then multiply back to the native IM output coordinate.
                            // IM -resize 96x96^ produces an image where min(w,h)=96;
                            // our _scaleFactor = _aperture / min(natW, natH) with _aperture=240.
                            // So the IM scale is 96 / min(natW, natH) = _scaleFactor * (96/_aperture).
                            const imScale = 96.0 / Math.min(
                                avatarCropOverlay._imgNatW,
                                avatarCropOverlay._imgNatH)
                            // Convert display-pixel pan → IM-output-pixel offset
                            const xOff = Math.round(cropFlick.contentX / avatarCropOverlay._scaleFactor * imScale)
                            const yOff = Math.round(cropFlick.contentY / avatarCropOverlay._scaleFactor * imScale)
                            _wpAsIcon.command = [
                                scriptDir + "/set-user-icon.sh",
                                avatarCropOverlay._srcPath,
                                xOff.toString(),
                                yOff.toString()
                            ]
                            _wpAsIcon.running = true
                            avatarCropOverlay._close()
                        }
                    }
                }
                Item { Layout.fillWidth: true }
            }
        }

        // Keyboard dismiss
        FocusScope {
            visible: avatarCropOverlay.visible
            Keys.onEscapePressed: avatarCropOverlay._close()
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
    // ── Fastfetch-style info row (icon + label + value) ───────────────────
    // ── Bento-style stat card with optional progress bar ───────────────────
    component SysStatCard: Rectangle {
        id: _card
        property string glyph: ""
        property string title: ""
        property string value: ""
        property real   progress: -1   // -1 = no bar shown

        Layout.fillWidth: true
        Layout.preferredHeight: 78
        radius: 14
        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.35)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    text: _card.glyph
                    font.family: Config.fontFamily
                    font.pixelSize: 16
                    color: Theme.cWc4
                }
                Text {
                    text: _card.title
                    font.family: Config.labelFont
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.55)
                    Layout.fillWidth: true
                }
            }

            Text {
                text: _card.value
                font.family: Config.labelFont
                font.pixelSize: 12
                font.weight: Font.Medium
                color: Theme.cOnSurf
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.topMargin: 2
            }

            Item { Layout.fillHeight: true }

            // Progress bar — only rendered when progress >= 0
            Rectangle {
                visible: _card.progress >= 0
                Layout.fillWidth: true
                Layout.preferredHeight: 4
                radius: 2
                color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.10)
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: parent.width * Math.max(0, Math.min(1, _card.progress))
                    radius: 2
                    color: _card.progress > 0.85 ? Theme.cTertiary : Theme.cPrimary
                    Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
                }
            }
        }
    }

    // ── Small chip — glyph + label + value, used for secondary facts ───────
    component SysChip: Rectangle {
        id: _chip
        property string glyph: ""
        property string label: ""
        property string value: ""

        implicitWidth: _chipRow.implicitWidth + 24
        implicitHeight: 34
        radius: 12
        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.2)
        border.width: 1
        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)

        RowLayout {
            id: _chipRow
            anchors.centerIn: parent
            spacing: 7
            Text {
                text: _chip.glyph
                font.family: Config.fontFamily
                font.pixelSize: 13
                color: Theme.cWc5
            }
            Text {
                text: _chip.label + ":"
                font.family: Config.labelFont
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.55)
            }
            Text {
                text: _chip.value
                font.family: Config.labelFont
                font.pixelSize: 11
                color: Theme.cOnSurf
            }
        }
    }

    component CCSection: RowLayout {
        property alias text: _sh.text
        Layout.fillWidth: true
        Layout.topMargin: 12
        Layout.bottomMargin: 4
        Text {
            id: _sh
            color: Theme.cSurfaceTint
            opacity: 0.85
            font.family: Config.labelFont
            font.pixelSize: 15
            font.weight: Font.Bold
            font.letterSpacing: 0.5
        }
        Rectangle {
            Layout.fillWidth: true; height: 2
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
                    color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.15)
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
                            GradientStop { position: 1.0; color: Theme.cOnSecondary }
                        }
                    }
                }

                // Dot-glyph thumb (󰟃) — matches startmenu
                Text {
                    text: "󰟃"
                    font.family: "Symbols Nerd Font Mono"
                    font.pixelSize: _trough.iH + 2
                    color: Theme.cWc4
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
                      Theme.cInversePrimary.b, 0.82)
                : Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.15)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                  Theme.cPrimary.b, value ? 0.6 : 0.6)

            Rectangle {
                width: 20; height: 20; radius: 10
                color: value ? Theme.cWc6 : Theme.cWc5
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
            color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
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
                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                      Theme.cPrimary.b, 0.82)
                            : "transparent"
                        border.width: _isCurrent ? 1 : 0
                        border.color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                              Theme.cInversePrimary.b, 0.45)

                        Text {
                            anchors.centerIn: parent
                            text: modelData; color: _isCurrent ? Theme.cOnSecondary : Theme.cPrimary
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
            ? (pbma.containsMouse
            	? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                          Theme.cOnSecondary.b, 1.0)
                : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                          Theme.cPrimary.b, 0.82))
            : (pbma.containsMouse
                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                          Theme.cPrimary.b, 0.55)
                : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g,
                          Theme.cOnSecondary.b, 0.15))
        border.width: 1
	border.color: active 
	    ? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, pbma.containsMouse ? 0.55 : 0.2) 
	    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, pbma.containsMouse ? 0.55 : 0.2)
	Behavior on color     { ColorAnimation { duration: 120 } }
	Behavior on border.color { ColorAnimation { duration: 120 } }

        Text {
            id: _pbt; anchors.centerIn: parent
            color: active 
                ? (pbma.containsMouse ? Theme.cPrimary : Theme.cOnSecondary)
                : (pbma.containsMouse ? Theme.cOnSecondary : Theme.cPrimary)
            font.family: Config.labelFont; font.pixelSize: 12
        }
        MouseArea {
            id: pbma; anchors.fill: parent
            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            onClicked: _pb.clicked()
        }
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
            Layout.preferredWidth: 40; height: 28; radius: 7
            color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.4)
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
        id: _cerRoot
        property alias label: _erl.text
        property string value: ""
        signal applied(string val)
        // Re-sync the TextInput whenever the backing property is updated
        // by an async process reader (QML breaks text: binding on user interaction)
        onValueChanged: _cerInput.text = value

        Layout.fillWidth: true; spacing: 8

        Text {
            id: _erl
            Layout.preferredWidth: 100
            color: Theme.cPrimary
            font.family: Config.labelFont; font.pixelSize: 13
            elide: Text.ElideRight
        }
        Rectangle {
            Layout.preferredWidth: 100; height: 28; radius: 7
            color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.4)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
            TextInput {
                id: _cerInput
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
