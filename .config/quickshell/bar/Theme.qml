pragma Singleton

import QtQuick
import QtCore
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  Theme.qml — Live matugen M3 + wallust + pywal color bridge for the qs bar
//
//  Matugen colors are read from MatugenColors.qml (written by matugen on
//  wallpaper change) and re-parsed whenever that file changes.
//
//  Wallust colors (color0–color15) are read from WallustColors.qml (written
//  by wallust on wallpaper change) and exposed as cWc0…cWc15 typed colors
//  plus a wallustColors JS object { color0: "#hex", … } for lookups.
//
//  Pywal colors are read from ~/.cache/wal/colors-hyprland.conf and exposed
//  via the walColors JS object.
//
//  Color naming follows the waybar colors.css convention so porting styles
//  is mechanical: @primary → cPrimary, @inverse_primary → cInversePrimary, etc.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    // ── Raw hex strings (writable, parsed from file) ──────────────────────
    property string _sourceColor:               "#a57c44"
    property string _primary:                   "#8ec8ea"
    property string _onPrimary:                 "#000f16"
    property string _primaryContainer:          "#346985"
    property string _onPrimaryContainer:        "#ffffff"
    property string _secondary:                 "#aec4d2"
    property string _secondaryFixed:            "#dbe0e3"
    property string _onSecondary:               "#091218"
    property string _secondaryContainer:        "#455763"
    property string _onSecondaryContainer:      "#ffffff"
    property string _background:                "#091218"
    property string _onBackground:              "#dedfe2"
    property string _surface:                   "#000000"
    property string _surfaceTint:               "#e3b57a"
    property string _surfaceContainerLow:       "#050606"
    property string _surfaceContainer:          "#0b0c0d"
    property string _surfaceContainerHigh:      "#171819"
    property string _surfaceContainerHighest:   "#232526"
    property string _onSurface:                 "#e2e4e7"
    property string _surfaceVariant:            "#2f3539"
    property string _onSurfaceVariant:          "#bac1c8"
    property string _inversePrimary:            "#134861"
    property string _inverseSurface:            "#dedfe2"
    property string _inverseOnSurface:          "#1a1c1d"
    property string _outline:                   "#868c92"
    property string _outlineVariant:            "#4f555a"
    property string _shadow:                    "#000000"
    property string _scrim:                     "#000000"
    property string _error:                     "#f8afa6"
    property string _errorContainer:            "#9d1b19"
    property string _onError:                   "#160000"
    property string _tertiary:                  "#e0b3eb"
    property string _tertiaryContainer:         "#7d5a88"
    property string _tertiaryFixedDim:          "#dcb9ab"
    property string _onTertiary:                "#230f2b"
    property string _onTertiaryContainer:       "#f7d8ff"
    property string _primaryFixed:              "#c6e7ff"
    property string _primaryFixedDim:           "#8ec8ea"
    property string _onPrimaryFixed:            "#001e2d"
    property string _onPrimaryFixedVariant:     "#1b4d65"

    // ── Typed color properties (reactive to string changes) ───────────────
    readonly property color cSourceColor:	   Qt.color(_sourceColor)
    readonly property color cPrimary:              Qt.color(_primary)
    readonly property color cOnPrimary:            Qt.color(_onPrimary)
    readonly property color cPrimaryContainer:     Qt.color(_primaryContainer)
    readonly property color cOnPrimaryContainer:   Qt.color(_onPrimaryContainer)
    readonly property color cSecondary:            Qt.color(_secondary)
    readonly property color cSecondaryFixed:       Qt.color(_secondaryFixed)
    readonly property color cOnSecondary:          Qt.color(_onSecondary)
    readonly property color cSecondaryContainer:   Qt.color(_secondaryContainer)
    readonly property color cOnSecondaryContainer: Qt.color(_onSecondaryContainer)
    readonly property color cBackground:           Qt.color(_background)
    readonly property color cOnBackground:         Qt.color(_onBackground)
    readonly property color cSurface:              Qt.color(_surface)
    readonly property color cSurfaceTint:          Qt.color(_surfaceTint)
    readonly property color cSurfLow:              Qt.color(_surfaceContainerLow)
    readonly property color cSurfMid:              Qt.color(_surfaceContainer)
    readonly property color cSurfHi:               Qt.color(_surfaceContainerHigh)
    readonly property color cSurfHighest:          Qt.color(_surfaceContainerHighest)
    readonly property color cOnSurf:               Qt.color(_onSurface)
    readonly property color cSurfVariant:          Qt.color(_surfaceVariant)
    readonly property color cOnSurfVar:            Qt.color(_onSurfaceVariant)
    readonly property color cInversePrimary:       Qt.color(_inversePrimary)
    readonly property color cInverseSurface:       Qt.color(_inverseSurface)
    readonly property color cInverseOnSurface:     Qt.color(_inverseOnSurface)
    readonly property color cOutline:              Qt.color(_outline)
    readonly property color cOutVar:               Qt.color(_outlineVariant)
    readonly property color cShadow:               Qt.color(_shadow)
    readonly property color cScrim:                Qt.color(_scrim)
    readonly property color cErr:                  Qt.color(_error)
    readonly property color cErrContainer:         Qt.color(_errorContainer)
    readonly property color cTertiary:             Qt.color(_tertiary)
    readonly property color cTertiaryContainer:    Qt.color(_tertiaryContainer)
    readonly property color cTertiaryFixedDim:    Qt.color(_tertiaryFixedDim)
    readonly property color cOnTertiaryContainer:   Qt.color(_onTertiaryContainer)
    readonly property color cPrimaryFixed:         Qt.color(_primaryFixed)
    readonly property color cPrimaryFixedDim:      Qt.color(_primaryFixedDim)
    readonly property color cOnPrimaryFixed:       Qt.color(_onPrimaryFixed)
    readonly property color cOnPrimaryFixedVariant: Qt.color(_onPrimaryFixedVariant)

    // ── Semantic composites ────────────────────────────────────────────────
    // blur_background: matches waybar colors.css  alpha(rgba(bg), 0.30)
    readonly property color blurBackground: Qt.rgba(
        Qt.color(_onSecondary).r, Qt.color(_onSecondary).g, Qt.color(_onSecondary).b, 0.30)

    // Desktop icon label background — onSecondary @ 0.35 opacity.
    // Blurred by Hyprland layerrule on quickshell:desktop so labels stay
    // readable against any wallpaper color.
    readonly property color cPanelBg: Qt.rgba(
        Qt.color(_onSecondary).r, Qt.color(_onSecondary).g, Qt.color(_onSecondary).b, 0.30)

    // Island gradient: inverse_primary → scrim  (matches waybar island CSS)
    // Use in ShaderEffect or as gradient stops in a LinearGradient
    readonly property color gradientTop:    cInversePrimary
    readonly property color gradientBottom: cScrim

    // ── Legacy API aliases (existing modules keep compiling) ───────────────
    readonly property color cPrim:      cPrimary   // shorthand
    readonly property color cOnPrim:    cOnPrimary
    readonly property color cBg:        cBackground

    // Old starter-kit names
    readonly property color background:  blurBackground
    readonly property color text:        cOnSurf
    readonly property color separator:   cOutVar
    readonly property color warning:     cErr
    readonly property color caution:     cSurfHi
    readonly property color accent:      cPrimary
    readonly property color highlight:   cPrimary
    readonly property color misc:        cOnSurfVar
    readonly property color process:     cPrimary

    // ── Font ──────────────────────────────────────────────────────────────
    readonly property string fontFamily: "Symbols Nerd Font Mono"
    readonly property int    fontSize:   12
    readonly property int    fontWeight: Font.Normal

    // ── Dimensions fallbacks (Config.qml is authoritative) ────────────────
    readonly property int barHeight:     32
    readonly property int margin:        6
    readonly property int borderRadius:  14
    readonly property int modulePadding: 8

    // ── Wallust colors (from ~/.cache/quickshell/wallpaper/WallustColors.qml) ───
    // wallustColors is a JS object: { color0: "#rrggbb", color1: ..., color15: ... }
    // Typed color properties cWc0–cWc15 are reactive to string changes.
    // Re-parsed whenever WallustColors.qml changes (wallust runs on wallpaper change).
    property var wallustColors: ({})

    // ── Raw wallust hex strings ───────────────────────────────────────────────
    property string _wc0:  "#0B0000"
    property string _wc1:  "#803E23"
    property string _wc2:  "#86472F"
    property string _wc3:  "#A14C23"
    property string _wc4:  "#924A29"
    property string _wc5:  "#AA682E"
    property string _wc6:  "#CA7847"
    property string _wc7:  "#DCD5D0"
    property string _wc8:  "#9A9592"
    property string _wc9:  "#803E23"
    property string _wc10: "#86472F"
    property string _wc11: "#A14C23"
    property string _wc12: "#924A29"
    property string _wc13: "#AA682E"
    property string _wc14: "#CA7847"
    property string _wc15: "#DCD5D0"

    // ── Typed wallust color properties (reactive to string changes) ────────
    readonly property color cWc0:  Qt.color(_wc0)
    readonly property color cWc1:  Qt.color(_wc1)
    readonly property color cWc2:  Qt.color(_wc2)
    readonly property color cWc3:  Qt.color(_wc3)
    readonly property color cWc4:  Qt.color(_wc4)
    readonly property color cWc5:  Qt.color(_wc5)
    readonly property color cWc6:  Qt.color(_wc6)
    readonly property color cWc7:  Qt.color(_wc7)
    readonly property color cWc8:  Qt.color(_wc8)
    readonly property color cWc9:  Qt.color(_wc9)
    readonly property color cWc10: Qt.color(_wc10)
    readonly property color cWc11: Qt.color(_wc11)
    readonly property color cWc12: Qt.color(_wc12)
    readonly property color cWc13: Qt.color(_wc13)
    readonly property color cWc14: Qt.color(_wc14)
    readonly property color cWc15: Qt.color(_wc15)

    property var _wallustColorFile: FileView {
        path: root._home + "/.cache/quickshell/wallpaper/WallustColors.qml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyWallustColors(text())
        Component.onCompleted: reload()
    }

    // Parse WallustColors.qml — extracts: property color m3colorN: "#hex"
    function _applyWallustColors(t) {
        if (!t || t.length === 0) return
        const result = {}
        const re = /property color m3color(\d+):\s*"(#[0-9a-fA-F]{6,8})"/g
        let m
        while ((m = re.exec(t)) !== null) {
            const n = parseInt(m[1])
            const hex = m[2]
            result["color" + n] = hex
            switch (n) {
                case 0:  root._wc0  = hex; break
                case 1:  root._wc1  = hex; break
                case 2:  root._wc2  = hex; break
                case 3:  root._wc3  = hex; break
                case 4:  root._wc4  = hex; break
                case 5:  root._wc5  = hex; break
                case 6:  root._wc6  = hex; break
                case 7:  root._wc7  = hex; break
                case 8:  root._wc8  = hex; break
                case 9:  root._wc9  = hex; break
                case 10: root._wc10 = hex; break
                case 11: root._wc11 = hex; break
                case 12: root._wc12 = hex; break
                case 13: root._wc13 = hex; break
                case 14: root._wc14 = hex; break
                case 15: root._wc15 = hex; break
            }
        }
        wallustColors = result
    }

    // ── Pywal colors (from ~/.cache/wal/colors-hyprland.conf) ────────────────
    // walColors is a JS object: { color0: "#rrggbb", color1: ..., foreground: ..., background: ... }
    // It is re-parsed whenever the pywal file changes (wal runs on wallpaper change).
    property var walColors: ({})

    property var _pywalColorFile: FileView {
        path: root._home + "/.cache/wal/colors-hyprland.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyPywalColors(text())
        Component.onCompleted: reload()
    }

    // Parse ~/.cache/wal/colors-hyprland.conf
    // Format: $color0 = rgba(r,g,b,a)  or  $foreground = rgba(...)
    function _applyPywalColors(t) {
        if (!t || t.length === 0) return
        const result = {}
        const re = /^\$(\w+)\s*=\s*rgba\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)\s*,[\d.]+\s*\)/gm
        let m
        while ((m = re.exec(t)) !== null) {
            const key = m[1]
            const r = parseInt(m[2]).toString(16).padStart(2, "0")
            const g = parseInt(m[3]).toString(16).padStart(2, "0")
            const b = parseInt(m[4]).toString(16).padStart(2, "0")
            result[key] = "#" + r + g + b
        }
        walColors = result
    }

    // ── Live file watcher ─────────────────────────────────────────────────
    // HOME resolved via StandardPaths — no Process needed, no startup-path warning.
    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation)

    property var _colorFile: FileView {
        path: root._home + "/.cache/quickshell/wallpaper/MatugenColors.qml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root._applyColors(text())
        Component.onCompleted: reload()
    }

    // Parse MatugenColors.qml — handles both hex strings and Qt.rgba() blocks
    function _applyColors(t) {
        // Match:  property color m3foo: "#hexhex"
        const hexRe = /property color m3(\w+):\s*"(#[0-9a-fA-F]{6,8})"/g
        let m
        while ((m = hexRe.exec(t)) !== null) {
            const key = m[1], hex = m[2]
            switch (key) {
                case "sourceColor":               root._sourceColor = hex; break
                case "primary":                   root._primary = hex; break
                case "onPrimary":                 root._onPrimary = hex; break
                case "primaryContainer":          root._primaryContainer = hex; break
                case "onPrimaryContainer":        root._onPrimaryContainer = hex; break
                case "secondary":                 root._secondary = hex; break
                case "secondaryFixed":            root._secondaryFixed = hex; break
                case "onSecondary":               root._onSecondary = hex; break
                case "secondaryContainer":        root._secondaryContainer = hex; break
                case "onSecondaryContainer":      root._onSecondaryContainer = hex; break
                case "background":                root._background = hex; break
                case "onBackground":              root._onBackground = hex; break
                case "surface":                   root._surface = hex; break
                case "surfaceTint":               root._surfaceTint = hex; break
                case "surfaceContainerLow":       root._surfaceContainerLow = hex; break
                case "surfaceContainer":          root._surfaceContainer = hex; break
                case "surfaceContainerHigh":      root._surfaceContainerHigh = hex; break
                case "surfaceContainerHighest":   root._surfaceContainerHighest = hex; break
                case "onSurface":                 root._onSurface = hex; break
                case "surfaceVariant":            root._surfaceVariant = hex; break
                case "onSurfaceVariant":          root._onSurfaceVariant = hex; break
                case "inversePrimary":            root._inversePrimary = hex; break
                case "inverseSurface":            root._inverseSurface = hex; break
                case "inverseOnSurface":          root._inverseOnSurface = hex; break
                case "outline":                   root._outline = hex; break
                case "outlineVariant":            root._outlineVariant = hex; break
                case "shadow":                    root._shadow = hex; break
                case "error":                     root._error = hex; break
                case "errorContainer":            root._errorContainer = hex; break
                case "tertiary":                  root._tertiary = hex; break
                case "tertiaryContainer":         root._tertiaryContainer = hex; break
                case "tertiaryFixedDim":          root._tertiaryFixedDim = hex; break
                case "onTertiary":                root._onTertiary = hex; break
                case "primaryFixed":               root._primaryFixed = hex; break
                case "primaryFixedDim":            root._primaryFixedDim = hex; break
                case "onPrimaryFixed":             root._onPrimaryFixed = hex; break
                case "onPrimaryFixedVariant":      root._onPrimaryFixedVariant = hex; break
            }
        }
    }
}
