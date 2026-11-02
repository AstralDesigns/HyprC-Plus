import QtQuick
import "../hyprcandy-shared"

// Color bridge for hyprcandy greeter themes.
// Reads the matugen (M3) and wallust palettes synced into
// ../hyprcandy-shared by greeter-sync.sh and exposes bar-style
// aliases (cPrimary, cOnSurface, ...) plus a few computed alpha tints.
QtObject {
    id: root

    // ── Matugen M3 ──────────────────────────────────────────────────────
    readonly property color cSource:          Colors.m3sourceColor
    readonly property color cPrimary:         Colors.m3primary
    readonly property color cOnPrimary:       Colors.m3onPrimary
    readonly property color cPrimaryContainer: Colors.m3primaryContainer
    readonly property color cOnPrimaryContainer: Colors.m3onPrimaryContainer
    readonly property color cSecondary:       Colors.m3secondary
    readonly property color cOnSecondary:     Colors.m3onSecondary
    readonly property color cSecondaryContainer: Colors.m3secondaryContainer
    readonly property color cOnSecondaryContainer: Colors.m3onSecondaryContainer
    readonly property color cBackground:      Colors.m3background
    readonly property color cOnBackground:    Colors.m3onBackground
    readonly property color cSurface:         Colors.m3surface
    readonly property color cSurfaceTint:     Colors.m3surfaceTint
    readonly property color cSurfaceContainerLow:    Colors.m3surfaceContainerLow
    readonly property color cSurfaceContainer:       Colors.m3surfaceContainer
    readonly property color cSurfaceContainerHigh:   Colors.m3surfaceContainerHigh
    readonly property color cSurfaceContainerHighest: Colors.m3surfaceContainerHighest
    readonly property color cOnSurface:       Colors.m3onSurface
    readonly property color cSurfaceVariant:  Colors.m3surfaceVariant
    readonly property color cOnSurfaceVariant: Colors.m3onSurfaceVariant
    readonly property color cInversePrimary:  Colors.m3inversePrimary
    readonly property color cOutline:         Colors.m3outline
    readonly property color cOutlineVariant:  Colors.m3outlineVariant
    readonly property color cError:           "#d3372f"
    readonly property bool  darkmode:         Colors.darkmode

    // ── Wallust accents (color0–15) ─────────────────────────────────────
    readonly property color cWc0:  Wallust.m3color0
    readonly property color cWc1:  Wallust.m3color1
    readonly property color cWc2:  Wallust.m3color2
    readonly property color cWc3:  Wallust.m3color3
    readonly property color cWc4:  Wallust.m3color4
    readonly property color cWc5:  Wallust.m3color5
    readonly property color cWc6:  Wallust.m3color6
    readonly property color cWc7:  Wallust.m3color7
    readonly property color cWc8:  Wallust.m3color8
    readonly property color cWc9:  Wallust.m3color9
    readonly property color cWc10: Wallust.m3color10
    readonly property color cWc11: Wallust.m3color11
    readonly property color cWc12: Wallust.m3color12
    readonly property color cWc13: Wallust.m3color13
    readonly property color cWc14: Wallust.m3color14
    readonly property color cWc15: Wallust.m3color15

    // ── Computed greeter tints ──────────────────────────────────────────
    readonly property color panelGlass: Qt.rgba(cSurfaceContainerHigh.r,
        cSurfaceContainerHigh.g, cSurfaceContainerHigh.b, 0.62)
    readonly property color fieldGlass: Qt.rgba(cInversePrimary.r,
        cInversePrimary.g, cInversePrimary.b, 0.34)
    // Outer form: InversePrimary glass. Alpha is driven live from Main.qml
    // (bound to config.BlurRadius via the CC "Blur R" slider), not static.
    property real formAlpha: 0.45
    readonly property color formGlass: Qt.rgba(cInversePrimary.r,
        cInversePrimary.g, cInversePrimary.b, formAlpha)
    // Inner sub-cards (candylock layering)
    readonly property color innerCard: Qt.rgba(cOnSecondary.r,
        cOnSecondary.g, cOnSecondary.b, 0.65)
    readonly property color innerCardAlt: Qt.rgba(cOnSecondary.r,
        cOnSecondary.g, cOnSecondary.b, 0.65)
    // Power pill
    readonly property color pill: Qt.rgba(cSurfaceTint.r,
        cSurfaceTint.g, cSurfaceTint.b, 0.75)
    readonly property color pillBtn: Qt.rgba(cOnSecondary.r,
        cOnSecondary.g, cOnSecondary.b, 0.90)
    readonly property color hoverTint: Qt.rgba(cPrimary.r,
        cPrimary.g, cPrimary.b, 0.16)
    readonly property color outlineSoft: Qt.rgba(cOutline.r,
        cOutline.g, cOutline.b, 0.42)
}
