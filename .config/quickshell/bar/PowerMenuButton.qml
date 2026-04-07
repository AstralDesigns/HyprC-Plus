import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: pmb
    required property var modelData
    Layout.fillWidth: true; height: 52; radius: 12
    color: ph.containsMouse ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
        : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.6)
    border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.40)
    Behavior on color { ColorAnimation { duration: 120 } }

    ColumnLayout { anchors.centerIn: parent; spacing: 2
        Text { Layout.alignment: Qt.AlignHCenter
            text: pmb.modelData.i
            font.pixelSize: 18; font.family: "Symbols Nerd Font Mono"
            color: ph.containsMouse ? Theme.cPrimary : Theme.cOnSurfVar
            Behavior on color { ColorAnimation { duration: 120 } }
        }
        Text { Layout.alignment: Qt.AlignHCenter
            text: pmb.modelData.l
            color: Theme.cOnSurfVar; font.pixelSize: 9 }
    }

    MouseArea {
        id: ph; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: {
            StartMenuState.menuVisible = false
            powerProc._cmd = pmb.modelData.cmd
            if (!powerProc.running) powerProc.running = true
        }
    }
}
