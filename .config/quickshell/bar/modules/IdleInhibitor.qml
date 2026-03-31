import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: icon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    property bool _active: false

    readonly property string _script: Config.barDir + "/idle-inhibitor.sh"

    Process {
        id: statusProc
        command: [root._script, "status"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                try { root._active = (JSON.parse(l).class === "activated") } catch(e) {}
            }
        }
    }
    Process {
        id: toggleProc
        command: [root._script, "toggle"]
        onExited: if (!statusProc.running) statusProc.running = true
    }
    Component.onCompleted: statusProc.running = true

    Text {
        id: icon
        anchors.centerIn: parent
        text: root._active ? "󰅶" : "󰾪"
        color: root._active ? Theme.cPrimary : Theme.cOnSurfVar
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
        font.weight: Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!toggleProc.running) toggleProc.running = true
    }
}
