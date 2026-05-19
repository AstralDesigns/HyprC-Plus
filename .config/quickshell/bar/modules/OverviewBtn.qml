import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: icon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    Text {
        id: icon
        anchors.centerIn: parent
        text: "󰋶"
        color: Config.glyphColor
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    Process { id: ovProc; command: [Config.scriptsDir + "/overview.sh"]; running: false }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!ovProc.running) ovProc.running = true
    }
}
