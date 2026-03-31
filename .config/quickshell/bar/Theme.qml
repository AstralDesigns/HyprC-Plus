pragma Singleton

import QtQuick
import QtCore
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  Theme.qml — Live matugen M3 color bridge for the qs bar
//
//  Colors are read from MatugenColors.qml (written by matugen on wallpaper
//  change) and re-parsed whenever that file changes.  All values below are
//  defaults matching the current wallpaper; they are overwritten at runtime.
//
//  Color naming follows the waybar colors.css convention so porting styles
//  is mechanical: @primary → cPrimary, @inverse_primary → cInversePrimary, etc.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    // ── Raw hex strings (writable, parsed from file) ──────────────────────
    property string _primary:                   "#8ec8ea"
    property string _onPrimary:                 "#000f16"
    property string _primaryContainer:          "#346985"
    property string _onPrimaryContainer:        "#ffffff"
    property string _secondary:                 "#aec4d2"
    property string _onSecondary:               "#091218"
    property string _secondaryContainer:        "#455763"
    property string _onSecondaryContainer:      "#ffffff"
    property string _background:                "#091218"
    property string _onBackground:              "#dedfe2"
    property string _surface:                   "#000000"
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
    property string _onTertiary:                "#230f2b"
    property string _onTertiaryContainer:       "#f7d8ff"
    property string _primaryFixed:              "#c6e7ff"
    property string _primaryFixedDim:           "#8ec8ea"
    property string _onPrimaryFixed:            "#001e2d"
    property string _onPrimaryFixedVariant:     "#1b4d65"

    // ── Typed color properties (reactive to string changes) ───────────────
    readonly property color cPrimary:              Qt.color(_primary)
    readonly property color cOnPrimary:            Qt.color(_onPrimary)
    readonly property color cPrimaryContainer:     Qt.color(_primaryContainer)
    readonly property color cOnPrimaryContainer:   Qt.color(_onPrimaryContainer)
    readonly property color cSecondary:            Qt.color(_secondary)
    readonly property color cOnSecondary:          Qt.color(_onSecondary)
    readonly property color cSecondaryContainer:   Qt.color(_secondaryContainer)
    readonly property color cOnSecondaryContainer: Qt.color(_onSecondaryContainer)
    readonly property color cBackground:           Qt.color(_background)
    readonly property color cOnBackground:         Qt.color(_onBackground)
    readonly property color cSurface:              Qt.color(_surface)
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
    readonly property color cOnTertiaryContainer:   Qt.color(_onTertiaryContainer)
    readonly property color cPrimaryFixed:         Qt.color(_primaryFixed)
    readonly property color cPrimaryFixedDim:      Qt.color(_primaryFixedDim)
    readonly property color cOnPrimaryFixed:       Qt.color(_onPrimaryFixed)
    readonly property color cOnPrimaryFixedVariant: Qt.color(_onPrimaryFixedVariant)

    // ── Semantic composites ────────────────────────────────────────────────
    // blur_background: matches waybar colors.css  alpha(rgba(bg), 0.4)
    readonly property color blurBackground: Qt.rgba(
        Qt.color(_onSecondary).r, Qt.color(_onSecondary).g, Qt.color(_onSecondary).b, 0.45)

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
                case "primary":                   root._primary = hex; break
                case "onPrimary":                 root._onPrimary = hex; break
                case "primaryContainer":          root._primaryContainer = hex; break
                case "onPrimaryContainer":        root._onPrimaryContainer = hex; break
                case "secondary":                 root._secondary = hex; break
                case "onSecondary":               root._onSecondary = hex; break
                case "secondaryContainer":        root._secondaryContainer = hex; break
                case "onSecondaryContainer":      root._onSecondaryContainer = hex; break
                case "background":                root._background = hex; break
                case "onBackground":              root._onBackground = hex; break
                case "surface":                   root._surface = hex; break
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
                case "onTertiary":                root._onTertiary = hex; break
                case "primaryFixed":               root._primaryFixed = hex; break
                case "primaryFixedDim":            root._primaryFixedDim = hex; break
                case "onPrimaryFixed":             root._onPrimaryFixed = hex; break
                case "onPrimaryFixedVariant":      root._onPrimaryFixedVariant = hex; break
            }
        }
    }
}
