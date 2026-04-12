import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: row.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    property string _icon:    "󰖐"
    property string _value:   "-- °C"
    property string _tooltip: "Weather loading..."

    // ── Fetch via weather.sh every Config.weatherInterval seconds ──
    Process {
        id: weatherProc
        command: [Config.barDir + "/weather.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    root._icon    = d.icon    || "󰖐"
                    root._value   = d.value   || d.text || "-- °C"
                    root._tooltip = d.tooltip || ""
                } catch(e) { root._value = "-- °C" }
            }
        }
    }
    Timer {
        interval: Config.weatherInterval * 1000
        running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!weatherProc.running) weatherProc.running = true
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Config.iconTextGap

        Text {
            text: root._icon
            color: Config.glyphColor
            font.family: Config.fontFamily
            font.pixelSize: Config.infoGlyphSize
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: root._value
            color: Config.textColor
            font.family: Config.labelFont
            font.pixelSize: Config.infoFontSize
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    Process { id: weatherWidgetProc; command: [Config.candyDir + "/GJS/toggle-weather-widget.sh"]; running: false }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(ev) {
            if (ev.button !== Qt.RightButton && !weatherWidgetProc.running)
                weatherWidgetProc.running = true
        }
        onWheel: function(ev) {
            if (ev.angleDelta.y > 0) toggleCProc.running = true
            else toggleFProc.running = true
            Qt.callLater(function() { if (!weatherProc.running) weatherProc.running = true })
        }
    }

    Process { id: toggleCProc; command: [Config.barDir + "/toggle-weather-format.sh", "-c"]; running: false }
    Process { id: toggleFProc; command: [Config.barDir + "/toggle-weather-format.sh", "-f"]; running: false }
}
