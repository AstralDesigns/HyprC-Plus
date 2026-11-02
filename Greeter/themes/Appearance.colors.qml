pragma Singleton
import QtQuick

QtObject {
    property bool darkmode: true
    property color m3sourceColor: "#a57c44"
    property color m3primary: "#e5b67b"
    property color m3onPrimary: "#150d00"
    property color m3primaryContainer: "#a37c48"
    property color m3onPrimaryContainer: "#000000"
    property color m3onPrimaryFixedVariant: "#402a08"
    property color m3secondary: "#d4bb9e"
    property color m3secondaryFixed: "#f5dabc"
    property color m3onSecondary: "#181108"
    property color m3onSecondaryTransparent: Qt.rgba(
        Qt.color("#181108").r,
        Qt.color("#181108").g,
        Qt.color("#181108").b,
        0.4)
    property color m3secondaryContainer: "#574633"
    property color m3onSecondaryContainer: "#ffffff"
    property color m3background: "#181108"
    property color m3onBackground: "#e6ded6"
    property color m3surface: "#000000"
    property color m3surfaceTint: "#e5b67b"
    property color m3surfaceContainerLow: "#040403"
    property color m3surfaceContainer: "#0c0b09"
    property color m3surfaceContainerHigh: "#181614"
    property color m3surfaceContainerHighest: "#25221f"
    property color m3onSurface: "#e6ded6"
    property color m3surfaceVariant: "#39322a"
    property color m3onSurfaceVariant: "#ccbeaf"
    property color m3inversePrimary: "#5b4017"
    property color m3inverseSurface: "#e6ded6"
    property color m3inverseOnSurface: "#1d1b18"
    property color m3outline: "#8e8376"
    property color m3outlineVariant: "#52493f"
    property color m3shadow: "#000000"
    property color m3primaryFixed:           "#fad9b2"
    property color m3primaryFixedDim:         "#e5b67b"
    property color m3onPrimaryFixed:          "#000000"
    property color m3tertiary: "#a0c4e8"
    property color m3onTertiary: "#001522"
    property color m3tertiaryContainer: "#6689a9"
    property color m3onTertiaryContainer: "#000000"
    property color m3tertiaryFixed: "#cae2fc"
    property color m3tertiaryFixedDim: "#a0c4e8"
}
