pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Left-click bar module → top-layer popup. Right-click → bottom-layer draggable widget.
Item {
    id: scope

    readonly property bool _active: ClockPopupState.visible || ClockPopupState.widgetVisible

    property var _now: new Date()
    property string _secStr: Qt.formatDateTime(_now, "ss")
    property string _dateStr: Qt.formatDateTime(_now, "dddd, MMMM d")
    property bool _colonVisible: _now.getMilliseconds() < 500

    property string _greeting: {
        const h = _now.getHours()
        if (h >= 5 && h < 12) return "Good Morning!"
        if (h >= 12 && h < 17) return "Good Afternoon!"
        if (h >= 17 && h < 22) return "Good Evening!"
        return "Good Night!"
    }

    // 1 Hz tick — enough for digital + analog; avoids 20 FPS canvas repaints.
    Timer {
        interval: 1000
        running: scope._active
        repeat: true
        onTriggered: {
            scope._now = new Date()
            scope._colonVisible = !scope._colonVisible
        }
    }

    component ClockPanel: Rectangle {
        required property var root
        implicitWidth: 380
        implicitHeight: 150
        radius: 20
        clip: true
        color: Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 35
            radius: 35
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 20

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                Text {
                    text: root._greeting
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 1.00)
                    font.family: Config.labelFont
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                Row {
                    spacing: 2
                    Text {
                        text: Qt.formatDateTime(root._now, "HH")
                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 1.00)
                        font.family: "C059"
                        font.italic: true
                        font.weight: Font.Bold
                        font.pixelSize: 38
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: ":"
                        color: Theme.cWc3
                        font.family: "C059"
                        font.italic: true
                        font.weight: Font.Bold
                        font.pixelSize: 38
                        opacity: root._colonVisible ? 1.0 : 0.2
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: Qt.formatDateTime(root._now, "mm")
                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 1.00)
                        font.family: "C059"
                        font.italic: true
                        font.weight: Font.Bold
                        font.pixelSize: 38
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 8; height: 1 }
                    Rectangle {
                        width: 32
                        height: 22
                        radius: 6
                        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
                        border.width: 1
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.40)
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            anchors.centerIn: parent
                            text: root._secStr
                            color: Theme.cWc6
                            font.family: Config.labelFont
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }
                }

                Text {
                    text: root._dateStr
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 1.00)
                    font.family: Config.labelFont
                    font.pixelSize: 12
                }
            }

            Item {
                width: 110
                height: 110
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 99
                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                                               Theme.cInversePrimary.b, 0.45)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.45)
                }

                Canvas {
                    anchors.fill: parent
                    antialiasing: true
                    property var time: root._now
                    onTimeChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)
                        const cx = width / 2
                        const cy = height / 2
                        const r = width / 2 - 4
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = Qt.rgba(Theme.cWc3.r, Theme.cWc3.g, Theme.cWc3.b, 0.80).toString()
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                        ctx.stroke()
                        ctx.fillStyle = Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.80).toString()
                        for (let i = 0; i < 12; i++) {
                            const angle = (i * 30) * Math.PI / 180
                            const mx = cx + (r - 6) * Math.sin(angle)
                            const my = cy - (r - 6) * Math.cos(angle)
                            ctx.beginPath()
                            const mRadius = (i % 3 === 0) ? 2.5 : 1.2
                            ctx.arc(mx, my, mRadius, 0, 2 * Math.PI)
                            ctx.fill()
                        }
                        const ms = time.getMilliseconds()
                        const sec = time.getSeconds() + ms / 1000.0
                        const min = time.getMinutes() + sec / 60.0
                        const hr = (time.getHours() % 12) + min / 60.0
                        const secAngle = (sec * 6) * Math.PI / 180
                        const minAngle = (min * 6) * Math.PI / 180
                        const hrAngle = (hr * 30) * Math.PI / 180
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.rotate(hrAngle)
                        ctx.lineWidth = 4.0
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.cWc6.toString()
                        ctx.beginPath()
                        ctx.moveTo(0, 8)
                        ctx.lineTo(0, -(r - 18))
                        ctx.stroke()
                        ctx.restore()
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.rotate(minAngle)
                        ctx.lineWidth = 2.5
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.cWc5.toString()
                        ctx.beginPath()
                        ctx.moveTo(0, 10)
                        ctx.lineTo(0, -(r - 10))
                        ctx.stroke()
                        ctx.restore()
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.rotate(secAngle)
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Qt.rgba(Theme.cWc3.r, Theme.cWc3.g, Theme.cWc3.b, 0.00).toString()
                        ctx.beginPath()
                        ctx.moveTo(0, 12)
                        ctx.lineTo(0, -(r - 6))
                        ctx.stroke()
                        ctx.fillStyle = Theme.cWc3.toString()
                        ctx.beginPath()
                        ctx.arc(0, -(r - 16), 3, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.restore()
                        ctx.fillStyle = Theme.cWc9.toString()
                        ctx.beginPath()
                        ctx.arc(cx, cy, 4, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.fillStyle = Theme.cWc6.toString()
                        ctx.beginPath()
                        ctx.arc(cx, cy, 1.5, 0, 2 * Math.PI)
                        ctx.fill()
                    }
                }
            }
        }
    }

    component ClockWidgetPanel: Rectangle {
        id: cwp
        required property var root
        implicitWidth: 156
        implicitHeight: 156
        radius: 99
        color: Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                              Config.barBorderColor.b, Config.barBorderAlpha)

        // Inner analogue clock background card
        Rectangle {
            anchors.centerIn: parent
            width: 110
            height: 110
            radius: 55
            color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                           Theme.cInversePrimary.b, 0.45)
            border.width: 1
            border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.45)
        }

        Canvas {
            anchors.fill: parent
            antialiasing: true
            property var time: cwp.root._now
            onTimeChanged: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.reset()
                ctx.clearRect(0, 0, width, height)
                const cx = width / 2
                const cy = height / 2
                const r = 51

                // Inner clock dial outline
                ctx.lineWidth = 1.5
                ctx.strokeStyle = Qt.rgba(Theme.cWc3.r, Theme.cWc3.g, Theme.cWc3.b, 0.80).toString()
                ctx.beginPath()
                ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                ctx.stroke()

                // Hour markers (12 dots)
                ctx.fillStyle = Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.80).toString()
                for (let i = 0; i < 12; i++) {
                    const angle = (i * 30) * Math.PI / 180
                    const mx = cx + (r - 6) * Math.sin(angle)
                    const my = cy - (r - 6) * Math.cos(angle)
                    ctx.beginPath()
                    const mRadius = (i % 3 === 0) ? 2.5 : 1.2
                    ctx.arc(mx, my, mRadius, 0, 2 * Math.PI)
                    ctx.fill()
                }

                // Time angles (without second hand)
                const ms = time.getMilliseconds()
                const sec = time.getSeconds() + ms / 1000.0
                const min = time.getMinutes() + sec / 60.0
                const hr = (time.getHours() % 12) + min / 60.0
                const minAngle = (min * 6) * Math.PI / 180
                const hrAngle = (hr * 30) * Math.PI / 180

                // Hour hand
                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate(hrAngle)
                ctx.lineWidth = 4.0
                ctx.lineCap = "round"
                ctx.strokeStyle = Theme.cWc6.toString()
                ctx.beginPath()
                ctx.moveTo(0, 8)
                ctx.lineTo(0, -(r - 18))
                ctx.stroke()
                ctx.restore()

                // Minute hand
                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate(minAngle)
                ctx.lineWidth = 2.5
                ctx.lineCap = "round"
                ctx.strokeStyle = Theme.cWc5.toString()
                ctx.beginPath()
                ctx.moveTo(0, 10)
                ctx.lineTo(0, -(r - 10))
                ctx.stroke()
                ctx.restore()

                // Circulating inner seconds dot
                const secAngle = (sec * 6) * Math.PI / 180
                ctx.save()
                ctx.translate(cx, cy)
                ctx.rotate(secAngle)
                ctx.fillStyle = Theme.cWc3.toString()
                ctx.beginPath()
                ctx.arc(0, -(r - 16), 3, 0, 2 * Math.PI)
                ctx.fill()
                ctx.restore()

                // Center pivot cap
                ctx.fillStyle = Theme.cWc9.toString()
                ctx.beginPath()
                ctx.arc(cx, cy, 4, 0, 2 * Math.PI)
                ctx.fill()
                ctx.fillStyle = Theme.cWc6.toString()
                ctx.beginPath()
                ctx.arc(cx, cy, 1.5, 0, 2 * Math.PI)
                ctx.fill()

                // Padded region: pointing Hour and Minute text
                const hrText = Qt.formatDateTime(time, "hh")
                const minText = Qt.formatDateTime(time, "mm")

                let diff = Math.abs(hrAngle - minAngle) % (2 * Math.PI)
                if (diff > Math.PI) diff = 2 * Math.PI - diff
                const rHr = (diff < 0.28) ? 62 : 66
                const rMin = (diff < 0.28) ? 70 : 66

                const hrX = cx + rHr * Math.sin(hrAngle)
                const hrY = cy - rHr * Math.cos(hrAngle)
                const minX = cx + rMin * Math.sin(minAngle)
                const minY = cy - rMin * Math.cos(minAngle)

                ctx.font = "bold 11px monospace"
                ctx.textAlign = "center"
                ctx.textBaseline = "middle"

                // Hour text where hour hand points
                ctx.fillStyle = Theme.cWc6.toString()
                ctx.fillText(hrText, hrX, hrY)

                // Minute text where minute hand points
                ctx.fillStyle = Theme.cWc5.toString()
                ctx.fillText(minText, minX, minY)
            }
        }
    }

    PanelWindow {
        id: clkPopup
        readonly property bool _barAtBottom: Config.barPosition === "bottom"
        readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop - 8) : Config.outerMarginTop + 4) + Config.barHeight
        readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom - 8) : Config.outerMarginBottom + 4) + Config.barHeight

        // ── Deferred-destroy animation pattern ──────────────────────────────
        // Surface stays alive during exit animation so the panel can animate
        // out; only destroyed (visible=false) after the Timer fires.
        property bool _stateVisible: ClockPopupState.visible
        Timer { id: _clkExitDelay; interval: 220; repeat: false }
        visible: _stateVisible || _clkExitDelay.running
        on_StateVisibleChanged: { if (!_stateVisible) _clkExitDelay.restart() }

        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
        margins {
            top: _barAtBottom ? 0 : _barGap
            bottom: _barAtBottom ? _barGapBot : 0
        }

        implicitWidth: clkPanel.implicitWidth + 8
        implicitHeight: clkPanel.implicitHeight + 8
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:clock-popup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        Connections {
            target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
            ignoreUnknownSignals: true
            function onAddressChanged() {
                if (HyprlandFocusedClient.address !== "")
                    ClockPopupState.close()
            }
        }

        MouseArea { anchors.fill: parent; z: -1; onClicked: ClockPopupState.close() }

        ClockPanel {
            id: clkPanel
            root: scope
            anchors.horizontalCenter: parent.horizontalCenter
            // Animate in/out with opacity + scale
            opacity: clkPopup._stateVisible ? 1.0 : 0.0
            scale:   clkPopup._stateVisible ? 1.0 : 0.92
            transformOrigin: clkPopup._barAtBottom ? Item.Bottom : Item.Top
            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        }
    }

    PinnedWidgetWindow {
        id: clockWidget
        active: ClockPopupState.widgetVisible
        widgetNamespace: "quickshell:clock-widget"
        onActiveChanged: {
            if (active) {
                clockWidget.posX = ClockPopupState.widgetX
                clockWidget.posY = ClockPopupState.widgetY
            }
        }
        onPositionCommitted: function(x, y) {
            ClockPopupState.widgetX = Math.round(x)
            ClockPopupState.widgetY = Math.round(y)
        }

        ClockWidgetPanel { root: scope }
    }
}
