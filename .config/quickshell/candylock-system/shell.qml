// ~/.config/quickshell/candylock-system/shell.qml
// Candylock system-monitor overlay — left-side panel
// Start alongside candylock; add to Hyprland: layerrule = blur, namespace:quickshell:candylock-system
// IPC close: qs ipc -c candylock-system call candylockSystem close

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // ── Matugen colors ─────────────────────────────────────────────────────
    property string _m3primary:              "#f7c382"
    property string _m3onSecondary:          "#100a00"
    property string _m3surfaceContainerHigh: "#1b1611"
    property string _m3onSurface:            "#f1e1d2"
    property string _m3onSurfaceVariant:     "#d1bca6"
    property string _m3outlineVariant:       "#5f5242"

    readonly property color cPrimary:   Qt.color(_m3primary)
    readonly property color cOnSurf:    Qt.color(_m3onSurface)
    readonly property color cOnSurfVar: Qt.color(_m3onSurfaceVariant)
    readonly property color cOutVar:    Qt.color(_m3outlineVariant)
    readonly property color cPanelBg:   Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.4)

    function parseColors(text) {
        const re = /property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while ((m = re.exec(text)) !== null) {
            switch (m[1]) {
                case "m3primary":             root._m3primary = m[2];              break
                case "m3onSecondary":         root._m3onSecondary = m[2];          break
                case "m3surfaceContainerHigh":root._m3surfaceContainerHigh = m[2]; break
                case "m3onSurface":           root._m3onSurface = m[2];            break
                case "m3onSurfaceVariant":    root._m3onSurfaceVariant = m[2];     break
                case "m3outlineVariant":      root._m3outlineVariant = m[2];       break
            }
        }
    }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) +
              "/quickshell/wallpaper/MatugenColors.qml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseColors(text())
    }

    // ── IPC: close when unlock succeeds ────────────────────────────────────
    IpcHandler {
        target: "candylockSystem"
        function close(): void { Qt.quit() }
    }

    // ── System monitor data ─────────────────────────────────────────────────
    property real cpuUsage:  0
    property real memUsage:  0
    property real tempC:     0
    property bool tempOk:    false
    property real swapUsage: 0
    property string uptimeStr: ""

    property var _prevCpu: null

    Process {
        id: sysProc; property var _buf: []
        command: ["bash", "-c",
            "head -1 /proc/stat; echo '---'; " +
            "grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo; echo '---'; " +
            "for z in /sys/class/thermal/thermal_zone*/; do " +
            "  t=$(cat \"$z/temp\" 2>/dev/null); y=$(cat \"$z/type\" 2>/dev/null); echo \"$y:$t\"; " +
            "done 2>/dev/null; echo '---'; " +
            "awk '{h=int($1/3600);m=int(($1%3600)/60);printf \"%dh %02dm\",h,m}' /proc/uptime; " +
            "echo -n ' · '; awk '{printf \"%.2f\",$1}' /proc/loadavg"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { sysProc._buf.push(l.trim()) }
        }
        onRunningChanged: if (running) _buf = []
        onExited: function() {
            const lines = _buf.slice(); _buf = []
            const cpuLine = lines[0] || ""
            const cm = cpuLine.match(/cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/)
            if (cm) {
                const u=+cm[1],n=+cm[2],s=+cm[3],i=+cm[4]
                const cur={total:u+n+s+i, idle:i}
                if (root._prevCpu) {
                    const dt=cur.total-root._prevCpu.total, di=cur.idle-root._prevCpu.idle
                    if (dt>0) root.cpuUsage=(dt-di)/dt
                }
                root._prevCpu=cur
            }
            let mi={}
            for (const l of lines) {
                const mm=l.match(/^(\w+):\s*(\d+)\s*kB/)
                if (mm) mi[mm[1]]=parseInt(mm[2])*1024
            }
            if (mi.MemTotal && mi.MemAvailable)
                root.memUsage=(mi.MemTotal-mi.MemAvailable)/mi.MemTotal
            if (mi.SwapTotal>0)
                root.swapUsage=(mi.SwapTotal-mi.SwapFree)/mi.SwapTotal
            for (const l of lines) {
                const tm=l.match(/^([^:]+):(\d+)$/)
                if (!tm) continue
                const type=tm[1].toLowerCase(), val=parseInt(tm[2])/1000
                if (val>0 && val<150 && (type.includes('cpu')||type.includes('core')||type.includes('x86'))) {
                    root.tempC=val; root.tempOk=true; break
                }
            }
            // Last non-empty line after last '---' is uptime
            for (let i=lines.length-1;i>=0;i--) {
                if (lines[i] && lines[i]!=='---') { root.uptimeStr=lines[i]; break }
            }
        }
    }

    Timer { interval: 2500; repeat: true; running: true
        onTriggered: if (!sysProc.running) sysProc.running = true
        Component.onCompleted: sysProc.running = true }

    // ── Panel window ────────────────────────────────────────────────────────
    PanelWindow {
        anchors { left: true; top: true; bottom: true }
        WlrLayershell.namespace: "quickshell:candylock-system"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        width: 220
        color: "transparent"

        Rectangle {
            anchors { fill: parent; margins: 16 }
            radius: 22
            color: root.cPanelBg
            border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.30)
            border.width: 1

            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 10

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "System"; color: root.cPrimary
                    font.pixelSize: 13; font.weight: Font.Medium; opacity: 0.85
                }

                // 2×2 gauge grid
                Grid {
                    Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                    columns: 2; spacing: 8
                    horizontalItemAlignment: Grid.AlignHCenter

                    Repeater {
                        model: [
                            { glyph: "󰻠", label: "CPU",  val: root.cpuUsage,
                              text: Math.round(root.cpuUsage*100)+"%" },
                            { glyph: "󰍛", label: "RAM",  val: root.memUsage,
                              text: Math.round(root.memUsage*100)+"%" },
                            { glyph: "󰔏", label: "Temp", val: root.tempOk ? Math.min(root.tempC/100,1) : 0,
                              text: root.tempOk ? Math.round(root.tempC)+"°" : "N/A" },
                            { glyph: "󰾴", label: "Swap", val: root.swapUsage,
                              text: Math.round(root.swapUsage*100)+"%" },
                        ]

                        delegate: Item {
                            required property var modelData
                            width: 80; height: 88

                            Canvas {
                                id: gaugeCanvas
                                anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                                width: 80; height: 80
                                property color pri:    root.cPrimary
                                property color onSurf: root.cOnSurf
                                property real  val:    modelData.val
                                property string glyph: modelData.glyph
                                property string vText: modelData.text

                                onPriChanged:    requestPaint()
                                onOnSurfChanged: requestPaint()
                                onValChanged:    requestPaint()

                                onPaint: {
                                    const ctx=getContext("2d")
                                    ctx.clearRect(0,0,width,height)
                                    const cx=width/2, cy=height/2, r=30, lw=5
                                    const s=0.75*Math.PI, e=2.25*Math.PI
                                    ctx.lineWidth=lw; ctx.lineCap="round"
                                    ctx.beginPath(); ctx.arc(cx,cy,r,s,e)
                                    ctx.strokeStyle="rgba(255,255,255,0.09)"; ctx.stroke()
                                    if (val>0.005) {
                                        ctx.beginPath(); ctx.arc(cx,cy,r,s,s+val*(e-s))
                                        ctx.strokeStyle=pri.toString(); ctx.stroke()
                                    }
                                    ctx.fillStyle=Qt.rgba(pri.r,pri.g,pri.b,0.75).toString()
                                    ctx.font="15px 'Symbols Nerd Font Mono'"
                                    ctx.textAlign="center"; ctx.textBaseline="alphabetic"
                                    ctx.fillText(glyph, cx, cy-3)
                                    ctx.fillStyle=onSurf.toString()
                                    ctx.font="bold 10px monospace"; ctx.textBaseline="top"
                                    ctx.fillText(vText, cx, cy+4)
                                }
                            }

                            Text {
                                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                                text: modelData.label; color: root.cOnSurfVar; font.pixelSize: 10
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.25)
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.uptimeStr || "--"
                    color: root.cOnSurfVar; font.pixelSize: 11
                    horizontalAlignment: Text.AlignHCenter
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
