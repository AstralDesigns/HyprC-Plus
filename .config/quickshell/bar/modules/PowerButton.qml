import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: powerText.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    // Local toggle state — flips on every click; self-corrects on next interaction.
    property bool _menuOpen: false

    Process {
        id: smProc
        command: [Config.scriptsDir + "/startmenu.sh"]
        running: false
        onExited: function(code) {
            if (code !== 0) root._menuOpen = false
        }
    }

    Text {
        id: powerText
        anchors.centerIn: parent
        // Down = closed (click to open), Up = open (click to close)
        text: root._menuOpen ? "" : ""   // nf-fa-chevron_circle_up / _down
        color: Config.powerGlyphColor
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root._menuOpen = !root._menuOpen
            if (!smProc.running) smProc.running = true
        }
    }
}
