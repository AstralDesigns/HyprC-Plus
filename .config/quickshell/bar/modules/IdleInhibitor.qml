import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// The IdleInhibitor Wayland protocol object lives in InhibitorAnchor (shell.qml),
// which is always mapped regardless of bar autohide state.  This widget only
// drives InhibitorState.active — it owns no inhibitor object of its own.
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: icon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    // Mirror the shared state so the icon stays in sync.
    readonly property bool _active: InhibitorState.active

    Text {
        id: icon
        anchors.centerIn: parent
        text: root._active ? "󰅶" : "󰾪"
        color: root._active ? Config.rightGroupColor : Theme.cOnSurf
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
        onClicked: InhibitorState.toggle()
    }
}
