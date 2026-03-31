import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// Control-center launcher button.
// ccGlyph is the default; reads ~/.config/hyprcandy/waybar-start-icon.txt if present.
// Left-click → toggle control center
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: ccIcon.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    property string _glyph: Config.ccGlyph

    // Live state file (same source as waybar distro icon)
    FileView {
        path: Quickshell.env("HOME") + "/.config/hyprcandy/waybar-start-icon.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const g = text().trim()
            if (g.length > 0) root._glyph = g
        }
    }

    Text {
        id: ccIcon
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
        onClicked: ControlCenterState.toggle()
    }
}
