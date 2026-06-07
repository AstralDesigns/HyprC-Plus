pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ═══════════════════════════════════════════════════════════════════════════
//  ClockPopup.qml — advanced clock dashboard, hyprcandy quickshell edition
//
//  Left-click on the Clock bar module → toggle this popup.
//  Displays a dashboard with a ticking greeting, digital clock, seconds capsule,
//  and a beautiful high-frequency sweeping analog clock. Dismisses on focus.
// ═══════════════════════════════════════════════════════════════════════════
PanelWindow {
    id: clkWin

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap:    Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot: Config.outerMarginBottom + Config.barHeight + 6
    readonly property real _panelMargin: Config.outerMarginSide * 2

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }

    implicitWidth:  clkPanel.implicitWidth  + 8
    implicitHeight: clkPanel.implicitHeight + 8

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell:clock-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    visible: ClockPopupState.visible

    // ── Dismiss on focus change ───────────────────────────────────────────
    Connections {
        target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                ClockPopupState.close()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onClicked: ClockPopupState.close() }

    // ── Time & Greeting Logic ─────────────────────────────────────────────
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

    // High frequency timer for smooth sweep and accurate digital update
    Timer {
        id: smoothTimer
        interval: 50
        running: clkWin.visible
        repeat: true
        onTriggered: {
            clkWin._now = new Date()
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: clkPanel
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth:  380
        implicitHeight: 150

        radius: 20
        clip: true
        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.40)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.40)

        // Glass sheen — transparent base; clip:true on parent clips to rounded corners
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

        RowLayout {
            id: clkLayout
            anchors.fill: parent
            anchors.margins: 18
            spacing: 20

            // Left Side: Digital display & info
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 6

                // Greeting text
                Text {
                    text: clkWin._greeting
                    color: Theme.cPrimary
                    font.family: Config.labelFont
                    font.pixelSize: 13
                    font.weight: Font.Medium
                }

                // Digital Time Row
                Row {
                    spacing: 2

                    Text {
                        text: Qt.formatDateTime(clkWin._now, "HH")
                        color: Theme.cOnSurf
                        font.family: "C059"
                        font.italic: true
                        font.weight: Font.Bold
                        font.pixelSize: 38
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: ":"
                        color: Theme.cPrimary
                        font.family: "C059"
                        font.italic: true
                        font.weight: Font.Bold
                        font.pixelSize: 38
                        opacity: clkWin._colonVisible ? 1.0 : 0.2
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on opacity { NumberAnimation { duration: 150 } }
                    }
                    Text {
                        text: Qt.formatDateTime(clkWin._now, "mm")
                        color: Theme.cOnSurf
                        font.family: "C059"
                        font.italic: true
                        font.weight: Font.Bold
                        font.pixelSize: 38
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: 8; height: 1 } // spacer
                    // Seconds capsule
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
                            text: clkWin._secStr
                            color: Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.0)
                            font.family: Config.labelFont
                            font.pixelSize: 11
                            font.weight: Font.Bold
                        }
                    }
                }

                // Localized date
                Text {
                    text: clkWin._dateStr
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 1.0)
                    font.family: Config.labelFont
                    font.pixelSize: 12
                }
            }

            // Right Side: Sweeping Analog Clock
            Item {
                width: 110; height: 110
                Layout.alignment: Qt.AlignVCenter

                Rectangle {
                    anchors.fill: parent
                    radius: 999
                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
                }

                Canvas {
                    id: analogCanvas
                    anchors.fill: parent
                    antialiasing: true

                    // Trigger repaint whenever time changes
                    property var time: clkWin._now
                    onTimeChanged: requestPaint()

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.clearRect(0, 0, width, height)

                        const cx = width / 2
                        const cy = height / 2
                        const r = width / 2 - 4

                        // 1. Draw outer circle
                        ctx.lineWidth = 1.5
                        ctx.strokeStyle = Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 0.35).toString()
                        ctx.beginPath()
                        ctx.arc(cx, cy, r, 0, 2 * Math.PI)
                        ctx.stroke()

                        // 2. Draw dial markings (12 dots)
                        ctx.fillStyle = Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.40).toString()
                        for (let i = 0; i < 12; i++) {
                            const angle = (i * 30) * Math.PI / 180
                            const mx = cx + (r - 6) * Math.sin(angle)
                            const my = cy - (r - 6) * Math.cos(angle)
                            ctx.beginPath()
                            // Make 12, 3, 6, 9 markers slightly larger
                            const mRadius = (i % 3 === 0) ? 2.5 : 1.2
                            ctx.arc(mx, my, mRadius, 0, 2 * Math.PI)
                            ctx.fill()
                        }

                        // Compute smooth hand angles
                        const ms = time.getMilliseconds()
                        const sec = time.getSeconds() + ms / 1000.0
                        const min = time.getMinutes() + sec / 60.0
                        const hr = (time.getHours() % 12) + min / 60.0

                        const secAngle = (sec * 6) * Math.PI / 180
                        const minAngle = (min * 6) * Math.PI / 180
                        const hrAngle = (hr * 30) * Math.PI / 180

                        // 3. Draw Hour Hand
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.rotate(hrAngle)
                        ctx.lineWidth = 4.0
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.cPrimary.toString()
                        ctx.beginPath()
                        ctx.moveTo(0, 8)
                        ctx.lineTo(0, -(r - 18))
                        ctx.stroke()
                        ctx.restore()

                        // 4. Draw Minute Hand
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.rotate(minAngle)
                        ctx.lineWidth = 2.5
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.cOnSurf.toString()
                        ctx.beginPath()
                        ctx.moveTo(0, 10)
                        ctx.lineTo(0, -(r - 10))
                        ctx.stroke()
                        ctx.restore()

                        // 5. Draw Second Hand (Smooth Sweeping)
                        ctx.save()
                        ctx.translate(cx, cy)
                        ctx.rotate(secAngle)
                        ctx.lineWidth = 0.0
                        ctx.lineCap = "round"
                        ctx.strokeStyle = Theme.cPrimaryFixedDim.toString()
                        ctx.beginPath()
                        ctx.moveTo(0, 12)
                        ctx.lineTo(0, -(r - 6))
                        ctx.stroke()

                        // Target circle on second hand
                        ctx.fillStyle = Theme.cPrimaryFixedDim.toString()
                        ctx.beginPath()
                        ctx.arc(0, -(r - 16), 3, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.restore()

                        // 6. Center Pin (Axle)
                        ctx.fillStyle = Theme.cPrimary.toString()
                        ctx.beginPath()
                        ctx.arc(cx, cy, 4, 0, 2 * Math.PI)
                        ctx.fill()

                        ctx.fillStyle = Theme.cOnSurf.toString()
                        ctx.beginPath()
                        ctx.arc(cx, cy, 1.5, 0, 2 * Math.PI)
                        ctx.fill()
                    }
                }
            }
        }
    }
}
