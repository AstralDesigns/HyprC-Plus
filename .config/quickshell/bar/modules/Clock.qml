import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// Time-only module — sits left of the ControlCenter button in center island.
// DateDisplay sits on the right.
// Left-click  → toggle ClockPopup (world clock)
// (right-click is handled by the MouseArea acceptedButtons)
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: timeText.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    property string _time: Qt.formatDateTime(new Date(), "HH:mm")

    // ── Sunrise / sunset (astronomical, no API) ───────────────────────────
    readonly property real _lat: 0.0
    readonly property real _lon: 0.0

    function _sunTimes() {
        const now       = new Date()
        const D2R       = Math.PI / 180
        const tzOff     = -now.getTimezoneOffset() / 60
        const dayOfYear = Math.floor(
            (now - new Date(now.getFullYear(), 0, 0)) / 86400000)

        const lngHour = _lon / 15

        function _calc(isRise) {
            const t   = dayOfYear + ((isRise ? 6 : 18) - lngHour) / 24
            const M   = (0.9856 * t - 3.289)
            let   L   = M + 1.916 * Math.sin(M * D2R) + 0.020 * Math.sin(2 * M * D2R) + 282.634
            L = ((L % 360) + 360) % 360
            let   RA  = Math.atan(0.91764 * Math.tan(L * D2R)) / D2R
            RA = ((RA % 360) + 360) % 360
            RA = (RA + (Math.floor(L / 90) * 90 - Math.floor(RA / 90) * 90)) / 15
            const sinDec = 0.39782 * Math.sin(L * D2R)
            const cosDec = Math.cos(Math.asin(sinDec))
            const cosH   = (-0.01454 - sinDec * Math.sin(_lat * D2R))
                         / (cosDec  * Math.cos(_lat * D2R))
            if (cosH < -1) return isRise ? 0  : 24
            if (cosH >  1) return isRise ? 12 : 12
            const H      = isRise
                ? (360 - Math.acos(cosH) / D2R) / 15
                : (      Math.acos(cosH) / D2R) / 15
            const localT = H + RA - (0.06571 * t) - 6.622 + tzOff - lngHour
            return ((localT % 24) + 24) % 24
        }

        return { rise: _calc(true), set: _calc(false) }
    }

    // ── Hour-based clock icon ─────────────────────────────────────────────
    function _clockIcon() {
        const h12     = new Date().getHours() % 12 || 12
        const filled  = ["󱑋","󱑌","󱑍","󱑎","󱑏","󱑐","󱑑","󱑒","󱑓","󱑔","󱑕","󱑖"]
        const outline = ["󱑋","󱑌","󱑍","󱑎","󱑏","󱑐","󱑑","󱑒","󱑓","󱑔","󱑕","󱑖"]
        const sun     = _sunTimes()
        const nowH    = new Date().getHours() + new Date().getMinutes() / 60
        const isDay   = nowH >= sun.rise && nowH < sun.set
        return isDay ? filled[h12 - 1] : outline[h12 - 1]
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

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(ev) {
            if (ev.button === Qt.RightButton)
                ClockPopupState.toggleWidget()
            else
                ClockPopupState.toggle()
        }
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
        id: minuteTick; interval: 1000; running: false; repeat: true
        onTriggered: {
            root._time = Qt.formatDateTime(new Date(), "HH:mm")
            root._icon = root._clockIcon()
        }
    }
}
