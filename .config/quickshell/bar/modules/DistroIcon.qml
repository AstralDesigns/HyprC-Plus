import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

Item {
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: distroText.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    Text {
        id: distroText
        anchors.centerIn: parent
        text: DistroState.icon
        color: Theme.text
        font.family: Theme.fontFamily
        font.pixelSize: 18
        font.weight: Theme.fontWeight
    }

    opacity: mouseArea.containsMouse ? 0.6 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        onClicked: LauncherState.toggle()
    }
}
