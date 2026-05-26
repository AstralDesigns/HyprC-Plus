import QtQuick
import "."

Rectangle {
    id: btn
    signal activated()
    property bool  accent: true
    property alias label:  lbl.text

    implicitWidth:  lbl.implicitWidth + 56
    implicitHeight: 34
    radius:         10

    color: ma.containsMouse
        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
        : Qt.rgba(Theme.cSurfHi.r,  Theme.cSurfHi.g,  Theme.cSurfHi.b,  0.35)
    border.color: accent
        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, ma.containsMouse ? 0.85 : 0.45)
        : Qt.rgba(Theme.cOutVar.r,  Theme.cOutVar.g,  Theme.cOutVar.b,  ma.containsMouse ? 0.55 : 0.25)
    border.width: 1

    Behavior on color        { ColorAnimation { duration: 100 } }
    Behavior on border.color { ColorAnimation { duration: 100 } }

    Text {
        id: lbl
        anchors.centerIn: parent
        color:          ma.containsMouse ? Theme.cOnPrimary : Theme.text
        font.family:    Config.labelFont
        font.pixelSize: Config.infoFontSize
        font.weight:    Font.Medium
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    opacity: ma.pressed ? 0.75 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked:    btn.activated()
    }
}
