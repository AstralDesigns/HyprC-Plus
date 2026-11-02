pragma Singleton
import QtQuick 2.15

QtObject {
    property bool darkmode: true
    property color m3sourceColor: "#b6ddc2"
    property color m3primary: "#cff6db"
    property color m3onPrimary: "#08160e"
    property color m3primaryContainer: "#b0d6bc"
    property color m3onPrimaryContainer: "#0b1c13"
    property color m3onPrimaryFixedVariant: "#1c3427"
    property color m3secondary: "#b4c3b7"
    property color m3secondaryFixed: "#d3e2d5"
    property color m3onSecondary: "#0e1410"
    property color m3onSecondaryTransparent: Qt.rgba(
        Qt.color("#0e1410").r,
        Qt.color("#0e1410").g,
        Qt.color("#0e1410").b,
        0.4)
    property color m3secondaryContainer: "#414c44"
    property color m3onSecondaryContainer: "#ffffff"
    property color m3background: "#0e1410"
    property color m3onBackground: "#dfe0dc"
    property color m3surface: "#000000"
    property color m3surfaceTint: "#a2c8ae"
    property color m3surfaceContainerLow: "#040504"
    property color m3surfaceContainer: "#0b0b0b"
    property color m3surfaceContainerHigh: "#161716"
    property color m3surfaceContainerHighest: "#222322"
    property color m3onSurface: "#dfe0dc"
    property color m3surfaceVariant: "#2f3430"
    property color m3onSurfaceVariant: "#bbc1bb"
    property color m3inversePrimary: "#304c3b"
    property color m3inverseSurface: "#dfe0dc"
    property color m3inverseOnSurface: "#1a1b1a"
    property color m3outline: "#7f8680"
    property color m3outlineVariant: "#454b46"
    property color m3shadow: "#000000"
    property color m3primaryFixed:           "#c0e7cb"
    property color m3primaryFixedDim:         "#a2c8ae"
    property color m3onPrimaryFixed:          "#000000"
    property color m3tertiary: "#fde9e9"
    property color m3onTertiary: "#2c1617"
    property color m3tertiaryContainer: "#fac1c3"
    property color m3onTertiaryContainer: "#321a1c"
    property color m3tertiaryFixed: "#fcd7d7"
    property color m3tertiaryFixedDim: "#eab3b5"
}
