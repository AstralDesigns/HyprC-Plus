import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: icon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    property bool _active: false

    IdleInhibitor {
        id: inhibitor
        window: QsWindow.window
        enabled: root._active
    }

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
        onClicked: root._active = !root._active
    }
}
