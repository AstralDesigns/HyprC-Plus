pragma Singleton
import QtQuick

QtObject {
    property bool darkmode: true
    property color m3primary: "#f8afa7"
    property color m3onPrimary: "#170001"
    property color m3primaryContainer: "#a71f1f"
    property color m3onPrimaryContainer: "#ffffff"
    property color m3secondary: "#f8afa7"
    property color m3onSecondary: "#1b0102"
    property color m3onSecondaryTransparent: Qt.rgba(
        Qt.color("#1b0102").r,
        Qt.color("#1b0102").g,
        Qt.color("#1b0102").b,
        0.4)
    property color m3secondaryContainer: "#8e3832"
    property color m3onSecondaryContainer: "#ffffff"
    property color m3background: "#1b0102"
    property color m3onBackground: "#f7d9d5"
    property color m3surface: "#000000"
    property color m3surfaceContainerLow: "#080505"
    property color m3surfaceContainer: "#120b0b"
    property color m3surfaceContainerHigh: "#201615"
    property color m3surfaceContainerHighest: "#2e2220"
    property color m3onSurface: "#fbddda"
    property color m3surfaceVariant: "#432f2d"
    property color m3onSurfaceVariant: "#ddb8b4"
    property color m3inversePrimary: "#810810"
    property color m3inverseSurface: "#f7d9d5"
    property color m3inverseOnSurface: "#241918"
    property color m3outline: "#a58480"
    property color m3outlineVariant: "#694f4c"
    property color m3shadow: "#000000"
}
