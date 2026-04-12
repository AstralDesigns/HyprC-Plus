import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: row.implicitWidth + Config.btnPadLeft + Config.btnPadRight
    implicitHeight: Config.moduleHeight

    // Detected once at startup: true = laptop (has battery), false = desktop PC.
    property bool _hasBattery: false

    Process {
        id: batDetectProc
        command: ["bash", "-c",
            "ls /sys/class/power_supply/BAT* 2>/dev/null | wc -l"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { root._hasBattery = parseInt(l.trim()) > 0 }
        }
        Component.onCompleted: running = true
    }

    property int  _capacity:  100
    property bool _charging:  false
    property string _state:   "Full"

    readonly property string _icon: {
        if (_charging) return ""
        const icons = ["", "", "󰪞", "󰪟", "󰪠", "󰪡", "󰪢", "󰪣", "󰪤", "󰪥"]
        return icons[Math.min(Math.floor(_capacity / 10), 9)]
    }
    readonly property color _iconColor: {
        if (_charging)        return Config.batteryChargingColor
        if (_capacity <= 10)  return Config.batteryLowColor
        if (_capacity <= 20)  return Qt.rgba(Config.batteryLowColor.r, Config.batteryLowColor.g,
                                             Config.batteryLowColor.b, 0.8)
        return Config.batteryIconColor
    }
    readonly property color _textColor: {
        if (_capacity <= 10)  return Config.batteryLowColor
        if (_capacity <= 20)  return Qt.rgba(Config.batteryLowColor.r, Config.batteryLowColor.g,
                                             Config.batteryLowColor.b, 0.8)
        return Config.batteryTextColor
    }

    Process {
        id: batProc
        command: ["bash", "-c",
            "CAP=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); " +
            "STA=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); " +
            "echo \"${CAP:-100} ${STA:-Full}\""]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const p = l.trim().split(" ")
                if (p.length >= 1) root._capacity = parseInt(p[0]) || 100
                if (p.length >= 2) {
                    root._state    = p[1]
                    root._charging = p[1] === "Charging" || p[1] === "Full"
                }
            }
        }
    }
    Timer {
        interval: 30000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!batProc.running) batProc.running = true
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Config.iconTextGap

        // ── Radial arc indicator ──────────────────────────────────────────────────
        //  PC (no battery): always-full radial + bolt glyph, no percentage.
        //  Laptop: normal dynamic battery arc + percentage.
        Item {
            visible: Config.batteryRadialVisible
            width:  Config.batteryRadialSize
            height: Config.batteryRadialSize
            anchors.verticalCenter: parent.verticalCenter

            // Track arc (background)
            Canvas {
                id: radialTrack
                anchors.fill: parent
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx = width/2, cy = height/2
                    const r  = Math.min(cx, cy) - Config.batteryRadialWidth/2
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, -Math.PI/2, Math.PI * 1.5)
                    ctx.strokeStyle = Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
                    ctx.lineWidth   = Config.batteryRadialWidth
                    ctx.stroke()
                }
            }

            // Fill arc (capacity)
            Canvas {
                id: radialFill
                anchors.fill: parent
                property color arcColor: root._iconColor
                onArcColorChanged: requestPaint()

                Connections {
                    target: root
                    function on_CapacityChanged()  { radialFill.requestPaint() }
                    function on_HasBatteryChanged() { radialFill.requestPaint() }
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const cx   = width/2, cy = height/2
                    const r    = Math.min(cx, cy) - Config.batteryRadialWidth/2
                    // PC (no battery): always full; laptop: real capacity
                    const cap  = root._hasBattery ? root._capacity : 100
                    const pct  = Math.max(0, Math.min(100, cap)) / 100
                    const end  = -Math.PI/2 + pct * Math.PI * 2
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, -Math.PI/2, end)
                    ctx.strokeStyle = radialFill.arcColor
                    ctx.lineWidth   = Config.batteryRadialWidth
                    ctx.lineCap     = "round"
                    ctx.stroke()
                }
            }

            // ── Lightning bolt overlay ─────────────────────────────
            // PC: always shown (always plugged in); Laptop: only when charging.
            Text {
                visible: root._hasBattery ? root._charging : true
                anchors.centerIn: parent
                text: "󱐋"
                color: Config.batteryChargingColor
                font.family: Config.fontFamily
                font.pixelSize: Math.max(6, Math.round(Config.batteryRadialSize * 0.55))
                Behavior on visible { }
            }
        }

        // Numeric percentage — hidden on PC (always 100% / plugged in)
        Text {
            visible: root._hasBattery
            text: root._capacity + "%"
            color: root._textColor
            font.family: Config.labelFont
            font.pixelSize: Config.infoFontSize
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    Process { id: sysMonProc;  command: [Config.candyDir + "/GJS/toggle-system-monitor.sh"]; running: false }
    Process { id: sysAppProc;  command: ["gnome-system-monitor"]; running: false }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(ev) {
            if (ev.button === Qt.RightButton) { if (!sysAppProc.running)  sysAppProc.running  = true }
            else                              { if (!sysMonProc.running) sysMonProc.running = true }
        }
    }
}
