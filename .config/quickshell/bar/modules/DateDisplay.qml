import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// Date-only module — sits right of the ControlCenter button in center island.
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: dateText.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    property string _date: Qt.formatDateTime(new Date(), "MM-dd")

    Row {
        id: dateText
        anchors.centerIn: parent
        spacing: Config.iconTextGap
        Text {
            text: "󰸗"
            color: Config.dateIconColor
            font.family: Config.fontFamily
            font.pixelSize: Config.infoGlyphSize
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root._date
            color: Config.dateTextColor
            font.family: Config.labelFont
            font.pixelSize: Config.infoFontSize
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    Process { id: calProc; command: ["gnome-calendar"]; running: false }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!calProc.running) calProc.running = true
    }

    // Update at midnight
    Timer {
        interval: { const n = new Date();
            return ((23 - n.getHours()) * 3600 + (59 - n.getMinutes()) * 60 + (60 - n.getSeconds())) * 1000
        }
        running: true; repeat: false
        onTriggered: { root._date = Qt.formatDateTime(new Date(), "MM-dd"); dayTick.start() }
    }
    Timer {
        id: dayTick; interval: 86400000; running: false; repeat: true
        onTriggered: root._date = Qt.formatDateTime(new Date(), "MM-dd")
    }
}
