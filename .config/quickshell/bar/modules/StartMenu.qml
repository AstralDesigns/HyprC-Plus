import QtQuick
import Quickshell
import ".."

// Start-menu / power button.
// Left-click → toggle start menu
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: smIcon.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    property string _glyph: Config.ccGlyph

    Text {
        id: smIcon
        anchors.centerIn: parent
        text: root._glyph
        color: Config.ccGlyphColor
        font.family: Config.fontFamily
        font.pixelSize: Config.glyphSize + 2
        Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: StartMenuState.toggle()
    }
}
