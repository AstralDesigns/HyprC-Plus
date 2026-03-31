import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// Time-only module — sits left of the ControlCenter button in center island.
// DateDisplay sits on the right.
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: timeText.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    property string _time: Qt.formatDateTime(new Date(), "HH:mm")

    // ── Hour-based clock icon ─────────────────────────────────────────────
    //  nf-md-clock_time_one … clock_time_twelve = U+F144B … U+F1456 (1-based)
    //  All hours use the filled variant (more legible at small sizes).
    function _clockIcon() {
        const h12 = new Date().getHours() % 12 || 12   // 1–12
        return String.fromCodePoint(0xF144A + h12 - 1)
    }

    property string _icon: _clockIcon()

    Row {
        id: timeText
        anchors.centerIn: parent
        spacing: Config.iconTextGap
        Text {
            text: root._icon
            color: Config.clockIconColor
            font.family: Config.fontFamily
            font.pixelSize: Config.infoGlyphSize
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root._time
            color: Config.clockTextColor
            font.family: Config.labelFont
            font.pixelSize: Config.infoFontSize
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    Process { id: ttyClockProc; command: [Config.candyHyprScripts + "/tty-clock.sh"]; running: false }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: if (!ttyClockProc.running) ttyClockProc.running = true
    }

    // Sync to next minute boundary, then tick every 60 s
    Timer {
        interval: { const n = new Date(); return (60 - n.getSeconds()) * 1000 - n.getMilliseconds() }
        running: true; repeat: false
        onTriggered: {
            root._time = Qt.formatDateTime(new Date(), "HH:mm")
            root._icon = root._clockIcon()
            minuteTick.start()
        }
    }
    Timer {
        id: minuteTick; interval: 60000; running: false; repeat: true
        onTriggered: {
            root._time = Qt.formatDateTime(new Date(), "HH:mm")
            root._icon = root._clockIcon()
        }
    }
}
