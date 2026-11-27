pragma Singleton
import QtQuick

QtObject {
    property bool darkmode: true
    property color m3sourceColor: "#4b656f"
    property color m3primary: "#b3c3ca"
    property color m3onPrimary: "#0f1619"
    property color m3primaryContainer: "#404d51"
    property color m3onPrimaryContainer: "#ffffff"
    property color m3onPrimaryFixedVariant: "#2a353a"
    property color m3secondary: "#b9c2c6"
    property color m3secondaryFixed: "#d8e1e5"
    property color m3onSecondary: "#121618"
    property color m3onSecondaryTransparent: Qt.rgba(
        Qt.color("#121618").r,
        Qt.color("#121618").g,
        Qt.color("#121618").b,
        0.4)
    property color m3secondaryContainer: "#444c4f"
    property color m3onSecondaryContainer: "#ffffff"
    property color m3background: "#121618"
    property color m3onBackground: "#e0dfdf"
    property color m3surface: "#000000"
    property color m3surfaceTint: "#b3c3ca"
    property color m3surfaceContainerLow: "#050505"
    property color m3surfaceContainer: "#0b0b0c"
    property color m3surfaceContainerHigh: "#171717"
    property color m3surfaceContainerHighest: "#232323"
    property color m3onSurface: "#e0dfdf"
    property color m3surfaceVariant: "#333434"
    property color m3onSurfaceVariant: "#c1c0c0"
    property color m3inversePrimary: "#3f4b50"
    property color m3inverseSurface: "#e0dfdf"
    property color m3inverseOnSurface: "#1b1b1c"
    property color m3outline: "#858585"
    property color m3outlineVariant: "#4a4a4b"
    property color m3shadow: "#000000"
    property color m3primaryFixed:           "#d2e2e8"
    property color m3primaryFixedDim:         "#b3c3ca"
    property color m3onPrimaryFixed:          "#020405"
    property color m3tertiary: "#adc4cd"
    property color m3onTertiary: "#0b161a"
    property color m3tertiaryContainer: "#3b4d54"
    property color m3onTertiaryContainer: "#ffffff"
    property color m3tertiaryFixed: "#cce3ec"
    property color m3tertiaryFixedDim: "#adc4cd"
}
