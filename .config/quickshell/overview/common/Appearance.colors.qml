pragma Singleton
import QtQuick

QtObject {
    property bool darkmode: true
    property color m3primary: "#efbf82"
    property color m3onPrimary: "#180f00"
    property color m3primaryContainer: "#cda168"
    property color m3onPrimaryContainer: "#000000"
    property color m3secondary: "#d4bb9e"
    property color m3onSecondary: "#130d06"
    property color m3onSecondaryTransparent: Qt.rgba(
        Qt.color("#130d06").r,
        Qt.color("#130d06").g,
        Qt.color("#130d06").b,
        0.4)
    property color m3secondaryContainer: "#61503b"
    property color m3onSecondaryContainer: "#ffffff"
    property color m3background: "#130d06"
    property color m3onBackground: "#e6ded6"
    property color m3surface: "#000000"
    property color m3surfaceContainerLow: "#050404"
    property color m3surfaceContainer: "#0d0b0a"
    property color m3surfaceContainerHigh: "#191715"
    property color m3surfaceContainerHighest: "#26231f"
    property color m3onSurface: "#ece2db"
    property color m3surfaceVariant: "#39322a"
    property color m3onSurfaceVariant: "#ccbeaf"
    property color m3inversePrimary: "#573c15"
    property color m3inverseSurface: "#e6ded6"
    property color m3inverseOnSurface: "#1d1b18"
    property color m3outline: "#95897c"
    property color m3outlineVariant: "#5c5348"
    property color m3shadow: "#000000"
}
