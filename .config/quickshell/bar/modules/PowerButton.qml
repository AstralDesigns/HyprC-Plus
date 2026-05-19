import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: Config.moduleHeight
    implicitHeight: Config.moduleHeight

    // Tracks whether the spin animation is in flight
    property bool _spinning: false

    // Rotation target — incremented by 360 on each click to chain cleanly
    property real _rotationTarget: 0

    Process {
        id: smProc
        command: [Config.scriptsDir + "/startmenu.sh"]
        running: false
    }

    Text {
        id: powerText
        anchors.centerIn: parent
        text: ""
        color: Config.powerGlyphColor
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize

        transformOrigin: Item.Center
        rotation: 0

        Behavior on rotation {
            RotationAnimation {
                duration: 420
                direction: RotationAnimation.Clockwise
                easing.type: Easing.InOutCubic
                onRunningChanged: if (!running) root._spinning = false
            }
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            root._spinning = true
            root._rotationTarget += 360
            powerText.rotation = root._rotationTarget
            if (!smProc.running) smProc.running = true
        }
    }
}
