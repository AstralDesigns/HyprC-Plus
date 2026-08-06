import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ─────────────────────────────────────────────────────────────────────────────
//  Weather bar module
//
//  Display is bound directly to WeatherPopupState properties so the bar and
//  popup always show the same data. The poll timer here is the primary driver
//  of WeatherPopupState.refresh() — the singleton's own background timer is
//  a safety net only.
// ─────────────────────────────────────────────────────────────────────────────
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  row.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    // ── Drive the shared fetch pipeline on the bar's configured interval ──
    Timer {
        interval: Config.weatherInterval * 1000
        running: Config.showWeather; repeat: true; triggeredOnStart: true
        onTriggered: WeatherPopupState.refresh()
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Config.iconTextGap

        Text {
            text: WeatherPopupState.icon
            color: Qt.rgba(Theme.cInversePrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 1.00)
            font.family: Config.fontFamily
            font.pixelSize: Config.infoGlyphSize + 2
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            // Show temp from the shared state; fall back to placeholder while
            // the very first fetch is in flight (temp starts as "--")
            text: WeatherPopupState.temp === "--" ? "-- °C" : WeatherPopupState.temp
            color: Config.textColor
            font.family: Config.labelFont
            font.pixelSize: Config.infoFontSize
            font.weight: Config.fontWeight
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(ev) {
            if (ev.button === Qt.RightButton)
                WeatherPopupState.toggleWidget()
            else
                WeatherPopupState.toggle()
        }
        onWheel: function(ev) {
            // Route through toggleUnit() so the conversion is instant from
            // _lastRaw — same path as the popup's °C/°F button.
            // Scroll up = °C, scroll down = °F; only toggle if not already
            // in the requested unit so double-scrolling doesn't flip back.
            if (ev.angleDelta.y > 0) {
                if (!WeatherPopupState._metric) WeatherPopupState.toggleUnit()
            } else {
                if (WeatherPopupState._metric)  WeatherPopupState.toggleUnit()
            }
        }
    }
}
