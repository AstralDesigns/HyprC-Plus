pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ═══════════════════════════════════════════════════════════════════════════
//  CalendarPopup.qml — hyprcandy quickshell edition
//
//  Opened by left-click on the DateDisplay bar module.
//  Clicking a day extends the panel downward with that day's holiday / events
//  and the add-edit form. Data, holidays and reminders live in EventsState.
//
//  Styling: transparent glass, matugen M3 palette (matches the other popups).
// ═══════════════════════════════════════════════════════════════════════════
PanelWindow {
    id: calWin

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop - 8) : Config.outerMarginTop + 4) + Config.barHeight
    readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom - 8) : Config.outerMarginBottom + 4) + Config.barHeight

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }

    implicitWidth:  320
    // Fixed surface height: the layer window must NOT resize per-frame (that is
    // what made the expand/collapse glitch). calPanel animates inside this.
    implicitHeight: 640

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell"
    WlrLayershell.keyboardFocus: calWin._formOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    color: "transparent"

    // ── Deferred-destroy animation pattern ──────────────────────────────
    property bool _stateVisible: CalendarPopupState.visible
    Timer { id: _calExitDelay; interval: 220; repeat: false }
    visible: _stateVisible || _calExitDelay.running
    on_StateVisibleChanged: { if (!_stateVisible) _calExitDelay.restart() }

    // ── Dismiss on focus change ───────────────────────────────────────────
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

    property string _selected: ""   // YYYY-MM-DD of the expanded day ("" = none)

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function keyOf(y, m, d) { return y + "-" + pad(m + 1) + "-" + pad(d) }

    function _firstWeekday(y, m) {
        const d = new Date(y, m, 1).getDay()
        return (d + 6) % 7
    }
    function _daysInMonth(y, m) { return new Date(y, m + 1, 0).getDate() }
    function _isoWeek(y, m, d) {
        const date = new Date(y, m, d)
        const jan4 = new Date(date.getFullYear(), 0, 4)
        const startOfWeek1 = new Date(jan4)
        startOfWeek1.setDate(jan4.getDate() - ((jan4.getDay() + 6) % 7))
        return Math.floor((date - startOfWeek1) / (7 * 86400000)) + 1
    }

    function _prevMonth() { if (_viewMonth === 0) { _viewMonth = 11; _viewYear-- } else _viewMonth--; EventsState.ensureYear(_viewYear) }
    function _nextMonth() { if (_viewMonth === 11) { _viewMonth = 0; _viewYear++ } else _viewMonth++; EventsState.ensureYear(_viewYear) }
    function _prevYear() { _viewYear--; EventsState.ensureYear(_viewYear) }
    function _nextYear() { _viewYear++; EventsState.ensureYear(_viewYear) }
    function _goToday() {
        _viewYear = _todayYear; _viewMonth = _todayMonth
        _selected = keyOf(_todayYear, _todayMonth, _todayDay)
        EventsState.ensureYear(_viewYear)
    }

    readonly property bool _isCurrentMonth: _viewYear === _todayYear && _viewMonth === _todayMonth

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
        "July","August","September","October","November","December"]
    readonly property var _monthNamesShort: [
        "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
    readonly property var _dayLabels: ["Mo","Tu","We","Th","Fr","Sa","Su"]

    function _eventsCount(key) { return EventsState.eventsOn(key).length }
    function _holName(key) { return EventsState.holidays[key] || "" }

    // ── Event form state ──────────────────────────────────────────────────
    property bool _formOpen: false
    property real _fId: -1        // real: event ids are Date.now()-based (>2^31)
    property int _fReminder: -1
    property string _fRecurrence: "none"

    readonly property var _remOpts: [
        { label: "None", v: -1 }, { label: "At time", v: 0 }, { label: "5m", v: 5 },
        { label: "10m", v: 10 }, { label: "15m", v: 15 }, { label: "30m", v: 30 }, { label: "60m", v: 60 }]
    readonly property var _recOpts: [
        { label: "None", v: "none" }, { label: "Daily", v: "daily" }, { label: "Weekly", v: "weekly" },
        { label: "Monthly", v: "monthly" }, { label: "Yearly", v: "yearly" }]

    function openNew() {
        _fId = -1; _fReminder = -1; _fRecurrence = "none"; _formOpen = true
        titleField.text = ""; dateField.text = _selected; timeField.text = "09:00"; notesField.text = ""
        Qt.callLater(function() { titleField.requestFocus() })
    }
    function openEdit(it) {
        _fId = it.id; _fReminder = (it.reminderMin === undefined ? -1 : it.reminderMin)
        _fRecurrence = it.recurrence || "none"; _formOpen = true
        titleField.text = it.title || ""; dateField.text = it.date
        timeField.text = it.time || "09:00"; notesField.text = it.notes || ""
        Qt.callLater(function() { titleField.requestFocus() })
    }
    function saveForm() {
        const title = titleField.text.trim()
        const date  = dateField.text.trim()
        if (title === "" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return
        const obj = { title: title, date: date, time: timeField.text.trim(),
                      reminderMin: _fReminder, recurrence: _fRecurrence, notes: notesField.text.trim() }
        if (_fId < 0) EventsState.addEvent(obj)
        else EventsState.updateEvent(_fId, obj)
        _selected = date
        _formOpen = false
    }
    function deleteForm() {
        if (_fId >= 0) EventsState.removeEvent(_fId)
        _formOpen = false
    }
    function _remLabel(v) { return v < 0 ? "No reminder" : (v === 0 ? "At time" : v + "m before") }
    function _cap(s) { return s.charAt(0).toUpperCase() + s.slice(1) }

    readonly property var _dayItems: {
        const evs = EventsState.events
        const hol = EventsState.holidays
        const s = _selected
        const out = []
        if (s && hol[s]) out.push({ kind: "holiday", name: hol[s] })
        if (s) for (const e of EventsState.eventsOn(s))
            out.push({ kind: "event", id: e.id, title: e.title, date: e.date, time: e.time,
                       reminderMin: e.reminderMin, recurrence: e.recurrence, notes: e.notes })
        return out
    }

    Component.onCompleted: {
        EventsState.init()
        EventsState.ensureYear(_viewYear)
    }

    // ── Reusable chip ─────────────────────────────────────────────────────
    component Chip: Rectangle {
        id: chip
        required property string label
        required property bool active
        signal chosen()
        implicitWidth: chipText.implicitWidth + 16
        implicitHeight: 24
        radius: 12
        color: active ? Theme.cPrimary
                      : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.12)
        Behavior on color { ColorAnimation { duration: 90 } }
        Text {
            id: chipText
            anchors.centerIn: parent
            text: chip.label
            color: active ? Theme.cOnPrimary : Theme.cOnSurf
            font.family: Config.labelFont; font.pixelSize: 11
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.chosen() }
    }

    // ── Small labelled text field ─────────────────────────────────────────
    component Field: Rectangle {
        id: fld
        property alias text: ti.text
        property alias placeholder: ph.text
        signal edited()
        function requestFocus() { ti.forceActiveFocus() }
        implicitHeight: 28
        radius: 8
        color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.35)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.5)
        Text {
            id: ph
            visible: ti.text === ""
            anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
            color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.4)
            font.family: Config.labelFont; font.pixelSize: 12
        }
        TextInput {
            id: ti
            anchors { fill: parent; leftMargin: 8; rightMargin: 8 }
            verticalAlignment: TextInput.AlignVCenter
            color: Theme.cOnSurf
            selectionColor: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
            font.family: Config.labelFont; font.pixelSize: 12
            clip: true
            onAccepted: fld.edited()
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: calPanel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: !calWin._barAtBottom ? parent.top : undefined
        anchors.bottom: calWin._barAtBottom ? parent.bottom : undefined
        anchors.topMargin: 2
        anchors.bottomMargin: 2

        implicitWidth:  320
        height: mainCol.implicitHeight + 24
        Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }

        radius: 20
        clip: true
        color: Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

        opacity: calWin._stateVisible ? 1.0 : 0.0
        scale:   calWin._stateVisible ? 1.0 : 0.92
        transformOrigin: calWin._barAtBottom ? Item.Bottom : Item.Top
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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

                Text {
                    text: "󰅁"
                    font.family: Config.fontFamily
                    font.pixelSize: 16
                    color: prevHov.containsMouse
                        ? Theme.cOnSurf
                        : Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.55)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    MouseArea {
                        id: prevHov; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: calWin._prevMonth()
                    }
                }

                Item {
                    Layout.fillWidth: true
                    height: monthYearText.implicitHeight
                    Text {
                        id: monthYearText
                        anchors.centerIn: parent
                        text: calWin._monthNames[calWin._viewMonth] + "  " + calWin._viewYear
                        color: calWin._isCurrentMonth ? Theme.cOnSurf : Theme.cPrimary
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
                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            if (event.angleDelta.y > 0) calWin._prevYear()
                            else calWin._nextYear()
                        }
                    }
                }

                Text {
                    text: "󰅂"
                    font.family: Config.fontFamily
                    font.pixelSize: 16
                    color: nextHov.containsMouse
                        ? Theme.cOnSurf
                        : Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.55)
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
                color: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, 0.65)
                border.width: 1
                border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)

                Row {
                    id: headersRow
                    anchors.centerIn: parent
                    width: 290
                    height: 20
                    Item { width: 26; height: 20
                        Text { anchors.centerIn: parent; text: "Wk"
                            color: Theme.cInversePrimary
                            font.family: Config.labelFont; font.pixelSize: 9 }
                    }
                    Repeater {
                        model: calWin._dayLabels
                        delegate: Item {
                            required property string modelData
                            required property int    index
                            width: (320 - 28 - 28) / 7
                            height: 20
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                color: (index === 5 || index === 6) ? Theme.cInversePrimary : Theme.cOnSecondary
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
                Layout.bottomMargin: 4
                implicitHeight: gridCol.implicitHeight + 16
                radius: 12
                color: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, 0.65)
                border.width: 1
                border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)

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

                            Item {
                                width: 26; height: 34
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
                                    color: Theme.cInversePrimary
                                    font.family: Config.labelFont; font.pixelSize: 9
                                }
                            }

                            Repeater {
                                model: 7
                                delegate: Item {
                                    required property int index
                                    property int _col:  index
                                    property int _day:  calWin._cells[_row * 7 + _col]
                                    property string _key: _day > 0
                                        ? calWin.keyOf(calWin._viewYear, calWin._viewMonth, _day) : ""
                                    property bool _isToday: _day > 0
                                        && calWin._viewYear === calWin._todayYear
                                        && calWin._viewMonth === calWin._todayMonth
                                        && _day === calWin._todayDay
                                    property bool _isWeekend: _col >= 5
                                    property bool _isSel: _key !== "" && _key === calWin._selected
                                    property bool _hasEvent: _day > 0 && calWin._eventsCount(_key) > 0
                                    property bool _isHoliday: _day > 0 && calWin._holName(_key) !== ""

                                    width: (320 - 28 - 28) / 7; height: 34

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 28; height: 28; radius: 99
                                        visible: _isSel
                                        color: "transparent"
                                        border.width: 1; border.color: Theme.cPrimary
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 26; height: 26; radius: 99
                                        visible: !_isToday && _day > 0 && dayHover.containsMouse && !_isSel
                                        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                                    }
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 26; height: 26; radius: 99
                                        visible: _isToday
                                        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.45)
                                        border.width: 1
                                        border.color: _isSel ? "transparent"
                                            : Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.55)
                                    }

                                    Text {
                                        id: dayNum
                                        anchors.centerIn: parent
                                        text: _day > 0 ? _day : ""
                                        color: _isToday ? Theme.cSurfaceTint
                                             : _isWeekend ? Theme.cInversePrimary : Theme.cOnSecondary
                                        font.family: Config.labelFont
                                        font.pixelSize: 12
                                        font.weight: _isToday ? Font.Bold : Font.Normal
                                    }

                                    Row {
                                        spacing: 3
                                        visible: _isHoliday || _hasEvent
                                        anchors { horizontalCenter: parent.horizontalCenter
                                                  top: dayNum.bottom; topMargin: 2 }
                                        Rectangle { width: 5; height: 5; radius: 3; visible: _isHoliday; color: Theme.cTertiary }
                                        Rectangle { width: 5; height: 5; radius: 3; visible: _hasEvent; color: Theme.cPrimary }
                                    }

                                    MouseArea {
                                        id: dayHover
                                        anchors.fill: parent
                                        hoverEnabled: _day > 0
                                        cursorShape: _day > 0 ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: {
                                            if (_day <= 0) return
                                            calWin._selected = (calWin._selected === _key) ? "" : _key
                                            calWin._formOpen = false
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Events section (extends downward when a day is selected) ──
            // Toggles instantly; calPanel's animated height + clip produce the
            // smooth wipe (same model as the notifications history panel).
            Item {
                id: eventsSection
                Layout.fillWidth: true
                Layout.preferredHeight: eventsInner.implicitHeight
                visible: calWin._selected !== ""

                ColumnLayout {
                    id: eventsInner
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    Layout.bottomMargin: 2
                    implicitHeight: evHead.implicitHeight + 12
                    radius: 10
                    color: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, 0.65)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)

                    RowLayout {
                        id: evHead
                        anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                        spacing: 6
                        Text {
                            Layout.fillWidth: true
                            text: {
                                const p = calWin._selected.split("-").map(Number)
                                if (p.length < 3) return ""
                                return Qt.formatDate(new Date(p[0], p[1] - 1, p[2]), "ddd, d MMM")
                            }
                            color: Theme.cOnSecondary
                            font.family: Config.labelFont; font.pixelSize: 12; font.weight: Font.Medium
                        }
                        Rectangle {
                            visible: !calWin._formOpen
                            implicitWidth: addTxt.implicitWidth + 14; implicitHeight: 22; radius: 11
                            color: Theme.cPrimary
                            Text { id: addTxt; anchors.centerIn: parent; text: "+ Add"
                                color: Theme.cOnPrimary; font.family: Config.labelFont; font.pixelSize: 11 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: calWin.openNew() }
                        }
                    }
                }

                // ── Day list ──
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: !calWin._formOpen
                    spacing: 5

                    Repeater {
                        model: calWin._dayItems
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth: true
                            implicitHeight: itemCol.implicitHeight + 12
                            radius: 9
                            color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.3)
                            border.width: 1
                            border.color: modelData.kind === "holiday"
                                ? Qt.rgba(Theme.cTertiary.r, Theme.cTertiary.g, Theme.cTertiary.b, 0.5)
                                : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)

                            ColumnLayout {
                                id: itemCol
                                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter
                                         leftMargin: 10; rightMargin: 10 }
                                spacing: 2
                                Text {
                                    Layout.fillWidth: true
                                    text: modelData.kind === "holiday" ? modelData.name : (modelData.title || "(untitled)")
                                    elide: Text.ElideRight
                                    color: modelData.kind === "holiday" ? Theme.cTertiary : Theme.cOnSurf
                                    font.family: Config.labelFont; font.pixelSize: 12; font.weight: Font.Medium
                                }
                                Text {
                                    visible: modelData.kind === "event"
                                    text: {
                                        if (modelData.kind !== "event") return ""
                                        const bits = []
                                        if (modelData.time) bits.push(modelData.time)
                                        if (modelData.recurrence && modelData.recurrence !== "none")
                                            bits.push(calWin._cap(modelData.recurrence))
                                        if (modelData.reminderMin >= 0)
                                            bits.push(calWin._remLabel(modelData.reminderMin))
                                        return bits.join("  ·  ")
                                    }
                                    color: Theme.cOnSurfVar
                                    font.family: Config.labelFont; font.pixelSize: 10
                                }
                                Text {
                                    visible: modelData.kind === "event" && (modelData.notes || "") !== ""
                                    text: modelData.notes
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                    color: Theme.cOnSurfVar
                                    font.family: Config.labelFont; font.pixelSize: 10
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: modelData.kind === "event"
                                cursorShape: modelData.kind === "event" ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: calWin.openEdit(modelData)
                            }
                        }
                    }

                    Text {
                        visible: calWin._dayItems.length === 0
                        text: "No events"
                        color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.4)
                        font.family: Config.labelFont; font.pixelSize: 11
                    }
                }

                // ── Add / edit form ──
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: calWin._formOpen
                    spacing: 8

                    Text {
                        text: calWin._fId < 0 ? "New event" : "Edit event"
                        color: Theme.cOnSurf; font.family: Config.labelFont
                        font.pixelSize: 13; font.weight: Font.Medium
                    }

                    Field { id: titleField; Layout.fillWidth: true; placeholder: "Title" }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Field { id: dateField; Layout.fillWidth: true; placeholder: "Date YYYY-MM-DD" }
                        Field { id: timeField; Layout.preferredWidth: 70; placeholder: "HH:MM" }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Text { text: "Reminder"; color: Theme.cOnSurfVar; font.family: Config.labelFont; font.pixelSize: 10 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: calWin._remOpts
                                delegate: Item {
                                    required property var modelData
                                    width: c1.implicitWidth; height: c1.implicitHeight
                                    Chip {
                                        id: c1
                                        label: modelData.label
                                        active: calWin._fReminder === modelData.v
                                        onChosen: calWin._fReminder = modelData.v
                                    }
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 4
                        Text { text: "Repeat"; color: Theme.cOnSurfVar; font.family: Config.labelFont; font.pixelSize: 10 }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 5
                            Repeater {
                                model: calWin._recOpts
                                delegate: Item {
                                    required property var modelData
                                    width: c2.implicitWidth; height: c2.implicitHeight
                                    Chip {
                                        id: c2
                                        label: modelData.label
                                        active: calWin._fRecurrence === modelData.v
                                        onChosen: calWin._fRecurrence = modelData.v
                                    }
                                }
                            }
                        }
                    }

                    Field { id: notesField; Layout.fillWidth: true; placeholder: "Notes" }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            visible: calWin._fId >= 0
                            implicitWidth: delTxt.implicitWidth + 16; implicitHeight: 26; radius: 13
                            color: Qt.rgba(0.85, 0.30, 0.30, 0.85)
                            Text { id: delTxt; anchors.centerIn: parent; text: "Delete"
                                color: Theme.cOnSurf; font.family: Config.labelFont; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: calWin.deleteForm() }
                        }
                        Rectangle {
                            implicitWidth: cancelTxt.implicitWidth + 16; implicitHeight: 26; radius: 13
                            color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.15)
                            Text { id: cancelTxt; anchors.centerIn: parent; text: "Cancel"
                                color: Theme.cOnSurf; font.family: Config.labelFont; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: calWin._formOpen = false }
                        }
                        Rectangle {
                            implicitWidth: saveTxt.implicitWidth + 18; implicitHeight: 26; radius: 13
                            color: Theme.cPrimary
                            Text { id: saveTxt; anchors.centerIn: parent; text: "Save"
                                color: Theme.cOnPrimary; font.family: Config.labelFont; font.pixelSize: 12 }
                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                onClicked: calWin.saveForm() }
                        }
                    }
                }

                // ── Holiday country selector ──
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 2
                    visible: !calWin._formOpen
                    spacing: 6
                    Text {
                        text: "Holidays: " + (EventsState.country || "--")
                        color: Theme.cOnSurfVar
                        font.family: Config.labelFont; font.pixelSize: 10
                    }
                    Item { Layout.fillWidth: true }
                    Chip {
                        label: "Auto"
                        active: EventsState.countryOverride === ""
                        onChosen: EventsState.setCountry("")
                    }
                    Field {
                        id: countryField
                        Layout.preferredWidth: 52
                        placeholder: "CC"
                        onEdited: {
                            const cc = countryField.text.trim().toUpperCase()
                            if (/^[A-Z]{2}$/.test(cc)) { EventsState.setCountry(cc); countryField.text = "" }
                        }
                    }
                }
                }
            }
        }
    }
}
