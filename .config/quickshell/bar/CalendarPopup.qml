pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  CalendarPopup.qml — hyprcandy quickshell edition
//
//  Launched by left-click on the DateDisplay bar module.
//  Right-click on DateDisplay launches gnome-calendar (see DateDisplay.qml).
//
//  Styling: transparent glass, matugen M3 color palette — matches CC/Weather
//  popup style exactly (cOnSecondary bg @ 0.42, cOutVar border @ 0.40).
//
//  Features:
//    • Full calendar grid with day-of-week headers
//    • Today highlighted with primary accent pill
//    • Current month/year header with prev/next navigation
//    • Scroll wheel on the calendar to navigate months
//    • Week numbers shown in left gutter
//    • Dismiss on focus change (same as weather popup)
//    • Click month/year label to jump back to today's month
//    • Year quick-jump: scroll wheel on the year label skips ±1 year
//    • Upcoming days footer showing the next 3 days
// ═══════════════════════════════════════════════════════════════════════════
PanelWindow {
    id: calWin

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap:    Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot: Config.outerMarginBottom + Config.barHeight + 6

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }

    implicitWidth:  320
    implicitHeight: calPanel.implicitHeight + 4

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell:calendar-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    visible: CalendarPopupState.visible

    // ── Dismiss on focus change ───────────────────────────────────────────
    // BUG FIX: guard target with typeof check (same pattern as
    // ControlCenterPopup / NotificationsPopup / SystemMonitorPopup)
    // so we don't get "HyprlandFocusedClient is not defined" on compositors
    // where the Hyprland IPC singleton isn't available yet.
    Connections {
        target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                CalendarPopupState.close()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onClicked: CalendarPopupState.close() }

    // ── Calendar logic ────────────────────────────────────────────────────
    property int _viewYear:  new Date().getFullYear()
    property int _viewMonth: new Date().getMonth()   // 0-based

    readonly property int _todayYear:  new Date().getFullYear()
    readonly property int _todayMonth: new Date().getMonth()
    readonly property int _todayDay:   new Date().getDate()

    // Day-of-week of the 1st of _viewMonth (Mon=0 … Sun=6)
    function _firstWeekday(y, m) {
        const d = new Date(y, m, 1).getDay()
        return (d + 6) % 7
    }

    function _daysInMonth(y, m) {
        return new Date(y, m + 1, 0).getDate()
    }

    // ISO week number
    function _isoWeek(y, m, d) {
        const date = new Date(y, m, d)
        const jan4  = new Date(date.getFullYear(), 0, 4)
        const startOfWeek1 = new Date(jan4)
        startOfWeek1.setDate(jan4.getDate() - ((jan4.getDay() + 6) % 7))
        const diff = date - startOfWeek1
        return Math.floor(diff / (7 * 86400000)) + 1
    }

    // Navigate
    function _prevMonth() {
        if (_viewMonth === 0) { _viewMonth = 11; _viewYear-- }
        else _viewMonth--
    }
    function _nextMonth() {
        if (_viewMonth === 11) { _viewMonth = 0; _viewYear++ }
        else _viewMonth++
    }
    function _prevYear() { _viewYear-- }
    function _nextYear() { _viewYear++ }
    function _goToday() {
        _viewYear  = _todayYear
        _viewMonth = _todayMonth
    }

    // Whether the currently viewed month is today's month
    readonly property bool _isCurrentMonth:
        _viewYear === _todayYear && _viewMonth === _todayMonth

    // Cell array — reactive to _viewMonth / _viewYear changes
    readonly property var _cells: {
        const offset = _firstWeekday(_viewYear, _viewMonth)
        const days   = _daysInMonth(_viewYear, _viewMonth)
        const cells  = []
        for (let i = 0; i < offset; i++) cells.push(0)
        for (let d = 1; d <= days; d++) cells.push(d)
        while (cells.length % 7 !== 0) cells.push(0)
        return cells
    }

    readonly property var _monthNames: [
        "January","February","March","April","May","June",
        "July","August","September","October","November","December"
    ]
    readonly property var _monthNamesShort: [
        "Jan","Feb","Mar","Apr","May","Jun",
        "Jul","Aug","Sep","Oct","Nov","Dec"
    ]
    readonly property var _dayLabels: ["Mo","Tu","We","Th","Fr","Sa","Su"]

    // ── Upcoming days (next 3 days relative to today, for the footer) ─────
    readonly property var _upcomingDays: {
        const days = []
        const dayNames = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
        for (let i = 1; i <= 3; i++) {
            const d = new Date(_todayYear, _todayMonth, _todayDay + i)
            days.push({
                label: dayNames[d.getDay()],
                day:   d.getDate(),
                month: _monthNamesShort[d.getMonth()]
            })
        }
        return days
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: calPanel
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth:  320
        implicitHeight: mainCol.implicitHeight + 24

        radius: 20
        clip: true
        color: Qt.rgba(Theme.cOnPrimaryFixedVariant.r, Theme.cOnPrimaryFixedVariant.g, Theme.cOnPrimaryFixedVariant.b, 0.3)
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

        // Subtle inner glass sheen — transparent base so only gradient alpha shows;
        // clip:true on parent keeps everything inside the rounded corners
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 35
            radius: 35
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.06) }
                GradientStop { position: 1.0; color: Qt.rgba(1,1,1,0.00) }
            }
        }

        // ── Scroll wheel anywhere on the panel = navigate months ─────────
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: (event) => {
                if (event.angleDelta.y > 0) calWin._prevMonth()
                else calWin._nextMonth()
            }
        }

        ColumnLayout {
            id: mainCol
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                topMargin: 12; leftMargin: 14; rightMargin: 14
            }
            spacing: 0

            // ── Month / year header ───────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 10

                // Prev button — nf-md-chevron_left_circle
                Text {
                    text: "󰅁"
                    font.family: Config.fontFamily
                    font.pixelSize: 16
                    color: prevHov.containsMouse
                        ? Theme.cPrimary
                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea {
                        id: prevHov; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: calWin._prevMonth()
                    }
                }

                // Month + year label
                // Click  → jump to today's month
                // Scroll → jump ±1 year
                Item {
                    Layout.fillWidth: true
                    height: monthYearText.implicitHeight

                    Text {
                        id: monthYearText
                        anchors.centerIn: parent
                        text: calWin._monthNames[calWin._viewMonth] + "  " + calWin._viewYear
                        // Accent colour when already on today's month
                        color: calWin._isCurrentMonth ? Theme.cPrimary : Theme.cOnSurf
                        font.family: Config.labelFont
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        hoverEnabled: true
                        onClicked: calWin._goToday()
                    }

                    // Scroll on header label = jump ±1 year
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            if (event.angleDelta.y > 0) calWin._prevYear()
                            else calWin._nextYear()
                        }
                    }
                }

                // Next button — nf-md-chevron_right_circle
                Text {
                    text: "󰅂"
                    font.family: Config.fontFamily
                    font.pixelSize: 16
                    color: nextHov.containsMouse
                        ? Theme.cPrimary
                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea {
                        id: nextHov; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: calWin._nextMonth()
                    }
                }
            }

            // ── Day-of-week headers ───────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                implicitHeight: headersRow.implicitHeight + 12
                radius: 20
                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
                border.width: 1
                border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.22)

                Row {
                    id: headersRow
                    anchors.centerIn: parent
                    width: 290
                    height: 20

                    // Week-number gutter label
                    Item { width: 26; height: 20
                        Text { anchors.centerIn: parent; text: "Wk"
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.50)
                            font.family: Config.labelFont; font.pixelSize: 9 }
                    }
                    Repeater {
                        model: calWin._dayLabels
                        delegate: Item {
                            // BUG FIX: with pragma ComponentBehavior: Bound,
                            // `index` is not implicitly in scope — it must be
                            // declared as a required property to be accessible.
                            required property string modelData
                            required property int    index
                            width: (320 - 28 - 28) / 7
                            height: 20
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: (index === 5 || index === 6)
                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimaryContainer.g, Theme.cPrimaryContainer.b, 0.70)
                                    : Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.70)
                                font.family: Config.labelFont
                                font.pixelSize: 10
                                font.weight: Font.Medium
                            }
                        }
                    }
                }
            }

            // ── Calendar grid ─────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 10
                implicitHeight: gridCol.implicitHeight + 16
                radius: 20
                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
                border.width: 1
                border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.22)

                Column {
                    id: gridCol
                    anchors.centerIn: parent
                    width: 290
                    spacing: 2

                    Repeater {
                        model: calWin._cells.length / 7
                        delegate: Row {
                            required property int index
                            property int _row: index
                            width: parent.width
                            spacing: 0

                            // Week-number gutter
                            Item {
                                width: 26; height: 30
                                Text {
                                    anchors.centerIn: parent
                                    property int _fd: {
                                        for (let i = 0; i < 7; i++) {
                                            const c = calWin._cells[_row * 7 + i]
                                            if (c > 0) return c
                                        }
                                        return 1
                                    }
                                    text: calWin._isoWeek(calWin._viewYear, calWin._viewMonth, _fd)
                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.40)
                                    font.family: Config.labelFont; font.pixelSize: 9
                                }
                            }

                            // 7 day cells
                            Repeater {
                                model: 7
                                delegate: Item {
                                    required property int index
                                    property int _col:  index
                                    property int _day:  calWin._cells[_row * 7 + _col]
                                    property bool _isToday: _day > 0
                                        && calWin._viewYear  === calWin._todayYear
                                        && calWin._viewMonth === calWin._todayMonth
                                        && _day === calWin._todayDay
                                    property bool _isWeekend: _col >= 5

                                    width: (320 - 28 - 28) / 7; height: 30

                                    // Hover highlight (non-today cells only)
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 26; height: 26; radius: 99
                                        visible: !_isToday && _day > 0 && dayHover.containsMouse
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                    }

                                    // Today pill
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 26; height: 26; radius: 99
                                        visible: _isToday
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: _day > 0 ? _day : ""
                                        color: _isToday
                                            ? Theme.cPrimary
                                            : _isWeekend
                                                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimaryContainer.g, Theme.cPrimaryContainer.b, 1.00)
                                                : Theme.cOnSurf
                                        font.family: Config.labelFont
                                        font.pixelSize: 12
                                        font.weight: _isToday ? Font.Bold : Font.Normal
                                    }

                                    MouseArea {
                                        id: dayHover
                                        anchors.fill: parent
                                        hoverEnabled: _day > 0
                                        cursorShape: _day > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Footer: today string ──────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1; Layout.bottomMargin: 8
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.22)
            }

            Text {
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDateTime(new Date(), "dddd, d MMMM yyyy")
                color: Config.ccGlyphColor
                font.family: Config.labelFont
                font.pixelSize: 11
            }

            // ── Upcoming 3 days strip ─────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 1; Layout.bottomMargin: 6
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.16)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 2
                spacing: 4

                Repeater {
                    model: calWin._upcomingDays
                    delegate: Rectangle {
                        required property var modelData
                        Layout.fillWidth: true
                        height: upcomingCol.implicitHeight + 10
                        radius: 6
                        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
                        border.width: 1
                        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.18)

                        ColumnLayout {
                            id: upcomingCol
                            anchors.centerIn: parent
                            spacing: 1

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.label
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 1.0)
                                font.family: Config.labelFont
                                font.pixelSize: 9
                                font.weight: Font.Medium
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.day
                                color: Theme.cOnSurf
                                font.family: Config.labelFont
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.month
                                color: Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.55)
                                font.family: Config.labelFont
                                font.pixelSize: 9
                            }
                        }
                    }
                }
            }
        }
    }
}
