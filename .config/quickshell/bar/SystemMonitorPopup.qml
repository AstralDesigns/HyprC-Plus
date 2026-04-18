pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────────
//  SystemMonitorPopup — Quickshell native system monitor
//
//  Fix: removed the `visible: SystemMonitorPopupState.visible` binding from
//  PanelWindow. The Loader in shell.qml already gates creation/destruction via
//  `active: SystemMonitorPopupState.visible`. Having both causes a layershell
//  surface race where the wlr_layer_surface is committed before Quickshell
//  finishes anchoring it, resulting in a silent no-show.
//
//  Auto-append logic matches GJS system-monitor.js:
//    • CPU / RAM / Temp / Swap  — always shown (Swap hidden if no swap)
//    • GPU gauges               — dynamically added/removed as count changes
//    • Battery                  — only appended on laptops (BAT* detected)
//    • Disk gauges              — dynamically added/removed as df output changes
//    • Footer: ↓↑ net rates, uptime, load average
// ─────────────────────────────────────────────────────────────────────────────

PanelWindow {
    id: smWin

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap:    Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot: Config.outerMarginBottom + Config.barHeight + 6
    readonly property real _panelMargin: Config.outerMarginSide * 2

    // Full-width anchor (left+right) so the layershell surface spans the screen.
    // Panel Rectangle is right-aligned inside — matches StartMenuPopup pattern.
    // right-only anchor produces a zero-width surface that never renders.
    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }

    implicitHeight: smCol.implicitHeight + 32

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell:sysmon-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"

    // ── Dismiss on focus change ───────────────────────────────────────────
    Connections {
        target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                SystemMonitorPopupState.close()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onClicked: SystemMonitorPopupState.close() }

    // ── Data state ────────────────────────────────────────────────────────
    property real   _cpu:       0
    property real   _ram:       0
    property real   _ramUsed:   0
    property real   _ramTotal:  0
    property real   _temp:      0
    property bool   _tempOk:    false
    property real   _swap:      0
    property real   _swapUsed:  0
    property real   _swapTotal: 0
    property bool   _swapOk:    false

    // GPU: list of { name, pct } objects — length drives auto-append
    property var    _gpus:      []

    // Battery: auto-detected once at startup, matches GJS behaviour
    property bool   _hasBat:    false
    property real   _batPct:    0
    property string _batStatus: ""

    // Disk: list of { mount, pct, used, size } — length drives auto-append
    property var    _disks:     []

    property real   _rxRate:    0
    property real   _txRate:    0
    property var    _prevNet:   null

    property string _uptime:    "--"
    property string _load:      "--"
    property var    _prevCpu:   null

    // ── One-shot battery detection (like GJS getBatteryInfo probe) ────────
    Process {
        id: batDetectProc
        command: ["bash", "-c", "ls /sys/class/power_supply/BAT* 2>/dev/null | wc -l"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { smWin._hasBat = parseInt(l.trim()) > 0 }
        }
        Component.onCompleted: running = true
    }

    // ── Helpers ───────────────────────────────────────────────────────────
    function _fmtBytes(b) {
        if (b <= 0) return "0 B"
        const k = 1024, s = ["B","KB","MB","GB","TB"]
        const i = Math.min(Math.floor(Math.log(b) / Math.log(k)), 4)
        return parseFloat((b / Math.pow(k, i)).toFixed(1)) + " " + s[i]
    }
    function _fmtRate(bps) {
        if (bps < 1024)    return Math.round(bps) + " B/s"
        if (bps < 1048576) return (bps / 1024).toFixed(1) + " KB/s"
        return (bps / 1048576).toFixed(1) + " MB/s"
    }
    function _fmtUptime(sec) {
        const d = Math.floor(sec / 86400)
        const h = Math.floor((sec % 86400) / 3600)
        const m = Math.floor((sec % 3600) / 60)
        return d > 0 ? d+"d "+h+"h "+m+"m" : h > 0 ? h+"h "+m+"m" : m+"m"
    }
    function _fmtDisk(kb) {
        if (kb >= 1073741824) return (kb / 1073741824).toFixed(1) + " TB"
        if (kb >= 1048576)    return (kb / 1048576).toFixed(1) + " GB"
        if (kb >= 1024)       return (kb / 1024).toFixed(0) + " MB"
        return kb + " KB"
    }

    // ── Single-shot poller ────────────────────────────────────────────────
    Process {
        id: sysProc
        property var _buf: []

        command: ["bash", "-c",
            // CPU
            "head -1 /proc/stat;" +
            // Memory
            "grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo;" +
            // Thermal zones (all, let parser pick best)
            "for z in /sys/class/thermal/thermal_zone*/;" +
            "do t=$(cat \"$z/temp\" 2>/dev/null); y=$(cat \"$z/type\" 2>/dev/null);" +
            "[ -n \"$t\" ] && echo \"ZONE:$y:$t\"; done;" +
            // NVIDIA GPU (utilization + name)
            "command -v nvidia-smi >/dev/null 2>&1 && " +
            "nvidia-smi --query-gpu=utilization.gpu,name --format=csv,noheader,nounits 2>/dev/null" +
            " | while IFS=, read pct name; do echo \"NVIDIA:${pct// /}:${name# }\"; done;" +
            // AMD/Intel GPU busy percent (one per drm card)
            "for f in /sys/class/drm/card*/device/gpu_busy_percent;" +
            "do [ -f \"$f\" ] || continue;" +
            "card=$(echo \"$f\" | grep -oP 'card\\d+');" +
            "driver=$(readlink -f /sys/class/drm/$card/device/driver 2>/dev/null | grep -oP '[^/]+$');" +
            "[ \"$driver\" = \"amdgpu\" ] || [ \"$driver\" = \"i915\" ] || [ \"$driver\" = \"xe\" ] || continue;" +
            "pname=$(cat /sys/class/drm/$card/device/product_name 2>/dev/null);" +
            "[ -z \"$pname\" ] && pname=$(lspci -d ::0300 -mm 2>/dev/null | grep -i \"$driver\" | head -1 | awk -F'\"' '{print $4}' | sed 's/.*\[//;s/\].*//');" +
            "[ -z \"$pname\" ] && pname=$driver;" +
            "echo \"GPUBUSY:$driver:$pname:$(cat $f 2>/dev/null)\"; done;" +
            // Disk usage — deduplicated by mountpoint, matching GJS df flags
            "df -BK --output=target,pcent,used,size -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null | tail -n +2;" +
            // Battery
            "for b in /sys/class/power_supply/BAT*;" +
            "do [ -d \"$b\" ] && echo \"BAT:$(cat $b/capacity 2>/dev/null):$(cat $b/status 2>/dev/null)\"; break; done;" +
            // Network
            "awk 'NR>2{gsub(\":\",\" \",$1);if($1!=\"lo\"){rx+=$2;tx+=$10}}END{print \"NET:\"rx\":\"tx}' /proc/net/dev;" +
            // Uptime + load
            "awk '{print \"UPTIME:\"$1}' /proc/uptime;" +
            "awk '{print \"LOAD:\"$1}' /proc/loadavg"]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { if (l.trim() !== "") sysProc._buf.push(l.trim()) }
        }
        onRunningChanged: if (running) _buf = []
        onExited: function() {
            smWin._parse(sysProc._buf.slice())
            sysProc._buf = []
        }
    }

    function _parse(lines) {
        let mi = {}
        let tempBest = 0, tempOk = false
        let gpus = []          // [{ name, pct }]  — rebuilt each poll
        let nvidiaNames = {}   // pct-index → name (for multi-GPU)
        let netRx = 0, netTx = 0
        let disks = []         // [{ mount, pct, used, size }]

        for (const l of lines) {
            // ── CPU ──────────────────────────────────────────────────────
            if (l.startsWith("cpu ")) {
                const p = l.split(/\s+/)
                const idle  = parseInt(p[4]) + parseInt(p[5])
                let total = 0
                for (let i = 1; i <= 8 && i < p.length; i++) total += parseInt(p[i]) || 0
                if (_prevCpu) {
                    const dt = total - _prevCpu.total
                    const di = idle  - _prevCpu.idle
                    if (dt > 0) _cpu = (dt - di) / dt
                }
                _prevCpu = { total, idle }
                continue
            }
            // ── /proc/meminfo ────────────────────────────────────────────
            const mm = l.match(/^(\w+):\s*(\d+)\s*kB/)
            if (mm) { mi[mm[1]] = parseInt(mm[2]) * 1024; continue }

            // ── Thermal zones ────────────────────────────────────────────
            if (l.startsWith("ZONE:")) {
                const zp = l.split(":")
                if (zp.length >= 3) {
                    const v  = parseInt(zp[2]) / 1000
                    const ty = zp[1].toLowerCase()
                    if (v > 0 && v < 150) {
                        // Prefer x86_pkg / pkg / cpu / core zones (matches GJS)
                        const preferred = ty.includes("x86") || ty.includes("pkg") ||
                                          ty.includes("cpu") || ty.includes("core")
                        if (!tempOk || preferred) { tempBest = v; tempOk = true }
                    }
                }
                continue
            }
            // ── NVIDIA GPU ───────────────────────────────────────────────
            if (l.startsWith("NVIDIA:")) {
                const rest = l.slice(7)
                const ci   = rest.indexOf(":")
                const pct  = parseInt(rest.slice(0, ci)) || 0
                const name = rest.slice(ci + 1).trim()
                              .replace(/NVIDIA\s*GeForce\s*/i, "")
                              .replace(/\s+\(.*\)$/, "")
                              .slice(0, 10)
                gpus.push({ name: name || "NVIDIA", pct: Math.max(0, pct), type: "nvidia" })
                continue
            }
            // ── AMD/Intel GPU busy percent ───────────────────────────────
            if (l.startsWith("GPUBUSY:")) {
                const p      = l.split(":")
                const driver = p[1] || ""
                const rawName = p[2] || driver
                const pct    = parseInt(p[3]) || 0
                // Clean up name: strip vendor prefix, brackets, truncate
                const name = rawName.replace(/AMD\s*/i,"").replace(/Intel\s*/i,"").replace(/\[|\]/g,"").trim().slice(0,10) || driver.slice(0,10) || "GPU"
                // Collect all; after loop, filter to prefer amdgpu over iGPU
                if (!gpus.find(g => g.type === "nvidia"))
                    gpus.push({ name, pct, type: driver })
                continue
            }
            // ── Battery ──────────────────────────────────────────────────
            if (l.startsWith("BAT:")) {
                const p = l.split(":")
                _hasBat    = true
                _batPct    = parseInt(p[1]) || 0
                _batStatus = p[2] || ""
                continue
            }
            // ── Network ──────────────────────────────────────────────────
            if (l.startsWith("NET:")) {
                const p  = l.split(":")
                const rx = parseInt(p[1]) || 0
                const tx = parseInt(p[2]) || 0
                const now = Date.now() / 1000
                if (_prevNet) {
                    const dt = Math.max(0.1, now - _prevNet.ts)
                    _rxRate = Math.max(0, (rx - _prevNet.rx) / dt)
                    _txRate = Math.max(0, (tx - _prevNet.tx) / dt)
                }
                _prevNet = { rx, tx, ts: now }
                continue
            }
            // ── df lines: /mount  12%  1234M  9876M ─────────────────────
            const dfm = l.match(/^(\S+)\s+(\d+)%\s+(\d+)K\s+(\d+)K/)
            if (dfm) {
                const usedKB = parseInt(dfm[3]), sizeKB = parseInt(dfm[4])
                disks.push({ mount: dfm[1], pct: parseInt(dfm[2]),
                             used: _fmtDisk(usedKB), size: _fmtDisk(sizeKB) })
                continue
            }
            // ── uptime / loadavg (tagged) ─────────────────────────────
            if (l.startsWith("UPTIME:")) { _uptime = _fmtUptime(parseFloat(l.slice(7))); continue }
            if (l.startsWith("LOAD:"))   { _load = parseFloat(l.slice(5)).toFixed(2); continue }
        }

        // ── Commit memory ─────────────────────────────────────────────────
        if (mi.MemTotal) {
            _ramTotal = mi.MemTotal
            _ramUsed  = mi.MemTotal - (mi.MemAvailable || 0)
            _ram      = _ramTotal > 0 ? _ramUsed / _ramTotal : 0
        }
        _swapTotal = mi.SwapTotal || 0
        _swapUsed  = _swapTotal - (mi.SwapFree || 0)
        _swap      = _swapTotal > 0 ? _swapUsed / _swapTotal : 0
        _swapOk    = _swapTotal > 0

        _temp  = tempBest
        _tempOk = tempOk

        // ── Deduplicate disks (GJS deduplicateDisks logic) ────────────────
        // Prefer root mountpoint; among non-root prefer shortest path
        const byDevice = {}
        for (const d of disks) {
            // Use mount as key (df already dedupes by block device on most systems)
            // Additional pass: collapse bind-mounts sharing same used/size
            const key = d.used + ":" + d.size
            if (!byDevice[key]) {
                byDevice[key] = d
            } else {
                const ex = byDevice[key]
                if (d.mount === "/") byDevice[key] = d
                else if (ex.mount !== "/" && d.mount.length < ex.mount.length)
                    byDevice[key] = d
            }
        }
        _disks = Object.values(byDevice)

        // Filter GPUs: if amdgpu present, drop i915/xe (iGPU on hybrid systems)
        const hasAmd = gpus.some(g => g.type === "amdgpu")
        _gpus = hasAmd ? gpus.filter(g => g.type !== "i915" && g.type !== "xe") : gpus

    }

    // ── Polling timer (matches GJS 2-second interval) ─────────────────────
    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: true   // always running while Loader has us active
        onTriggered: if (!sysProc.running) sysProc.running = true
    }

    // ── Arc gauge component ───────────────────────────────────────────────
    component ArcGauge: Item {
        id: ag
        property real   value:    0
        property string glyph:    ""
        property string label:    ""
        property string valStr:   "--"
        property string sub:      ""
        property color  arcColor: Theme.cPrimary

        implicitWidth:  76
        implicitHeight: 96

        Behavior on value { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

        Canvas {
            id: arcC
            anchors.top: parent.top
            anchors.horizontalCenter: parent.horizontalCenter
            width: 68; height: 68

            property real   _v:  ag.value
            property color  _ac: ag.arcColor
            property string _gl: ag.glyph
            property string _vt: ag.valStr

            on_VChanged:  requestPaint()
            on_AcChanged: requestPaint()
            on_GlChanged: requestPaint()
            on_VtChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const cx = width/2, cy = height/2, r = 27, lw = 5
                const S = 0.75 * Math.PI, E = 2.25 * Math.PI
                const onS = Theme.cOnSurf
                ctx.lineWidth = lw; ctx.lineCap = "round"
                // Track
                ctx.beginPath(); ctx.arc(cx, cy, r, S, E)
                ctx.strokeStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.12).toString()
                ctx.stroke()
                // Fill
                if (_v > 0.005) {
                    ctx.beginPath(); ctx.arc(cx, cy, r, S, S + _v * (E - S))
                    ctx.strokeStyle = _ac.toString(); ctx.stroke()
                }
                // Glyph (center, slightly above midpoint)
                ctx.fillStyle = Qt.rgba(_ac.r, _ac.g, _ac.b, 0.90).toString()
                ctx.font = "14px 'Symbols Nerd Font Mono'"
                ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
                ctx.fillText(_gl, cx, cy + 2)
                // Value text (below glyph)
                ctx.fillStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.88).toString()
                ctx.font = "bold 8px monospace"
                ctx.textBaseline = "top"
                ctx.fillText(_vt, cx, cy + 5)
            }
        }

        // Sub-label (e.g. used RAM, disk used/total, battery status)
        Text {
            anchors.top: arcC.bottom; anchors.topMargin: 1
            anchors.horizontalCenter: parent.horizontalCenter
            text: ag.sub; color: Theme.cOnSurfVar
            font.pixelSize: 8; font.family: Config.labelFont
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight; width: parent.width
        }
        // Bottom label (CPU / RAM / Temp / GPU name / mount point…)
        Text {
            anchors.bottom: parent.bottom
            anchors.horizontalCenter: parent.horizontalCenter
            text: ag.label; color: Theme.cOnSurfVar
            font.pixelSize: 9; font.family: Config.labelFont
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: smPanel
        anchors { right: parent.right; rightMargin: smWin._panelMargin; top: parent.top; bottom: parent.bottom }
        width: 280

        radius: Config.barMode === "island" ? Config.islandRadius : Config.barRadius
        color:  Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.42)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.40)

        scale: SystemMonitorPopupState.visible ? 1.0 : 0.92
        transformOrigin: smWin._barAtBottom ? Item.BottomRight : Item.TopRight
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: smCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            spacing: 10

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "󰻠  System Monitor"; color: Theme.cOnSurf
                    font.pixelSize: 13; font.weight: Font.Medium; font.family: Config.fontFamily
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 24; height: 24; radius: 99; color: "transparent"
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: SystemMonitorPopupState.close()
                        Text {
                            anchors.centerIn: parent; text: "󰅙"
                            color: parent.containsMouse ? Theme.cOnSurf : Theme.cOnSurfVar
                            font.pixelSize: 14; font.family: Config.fontFamily
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
            }

            // ── Gauge grid (auto-append like GJS) ─────────────────────────
            // Fixed gauges: CPU, RAM, Temp, Swap (Swap hidden when no swap)
            // Then: GPU gauges (Repeater, count-driven)
            // Then: Battery (only on laptops — _hasBat gate)
            // Then: Disk gauges (Repeater, count-driven)
            Flow {
                Layout.fillWidth: true; spacing: 6

                // CPU — always shown
                ArcGauge {
                    value:    smWin._cpu
                    glyph:    "󰻠"; label: "CPU"
                    valStr:   Math.round(smWin._cpu * 100) + "%"
                    arcColor: Theme.cPrimary
                }
                // RAM — always shown
                ArcGauge {
                    value:    smWin._ram
                    glyph:    "󰍛"; label: "RAM"
                    valStr:   Math.round(smWin._ram * 100) + "%"
                    sub:      smWin._fmtBytes(smWin._ramUsed)
                    arcColor: Theme.cSecondary
                }
                // Temp — always shown, N/A when unavailable
                ArcGauge {
                    value:    smWin._tempOk ? Math.min(smWin._temp / 100, 1) : 0
                    glyph:    "󰔏"; label: "Temp"
                    valStr:   smWin._tempOk ? Math.round(smWin._temp) + "°" : "N/A"
                    arcColor: smWin._tempOk && smWin._temp > 80
                        ? Qt.rgba(1.0, 0.4, 0.2, 1) : Theme.cPrimaryFixedDim
                }
                // Swap — hidden when no swap partition (matches GJS 'none')
                ArcGauge {
                    visible:  smWin._swapOk
                    value:    smWin._swap
                    glyph:    "󰾴"; label: "Swap"
                    valStr:   Math.round(smWin._swap * 100) + "%"
                    sub:      smWin._swapOk ? smWin._fmtBytes(smWin._swapUsed) : ""
                    arcColor: Theme.cSecondaryContainer
                }

                // GPU gauges — auto-appended, one per detected GPU (NVIDIA + AMD/Intel)
                // Matches GJS: gpuGs rebuilt when gpus.length changes
                Repeater {
                    model: smWin._gpus
                    delegate: ArcGauge {
                        required property var modelData
                        required property int index
                        value:    modelData.pct / 100
                        glyph:    "󰢮"
                        label:    modelData.name.length > 8
                                  ? modelData.name.slice(0, 8)
                                  : (modelData.name || "GPU")
                        valStr:   modelData.pct + "%"
                        arcColor: Theme.cTertiary
                    }
                }

                // Battery — auto-appended only on laptops (matches GJS batG probe)
                ArcGauge {
                    visible:  smWin._hasBat
                    value:    smWin._batPct / 100
                    glyph:    smWin._batPct > 80 ? "󰁹"
                              : smWin._batPct > 60 ? "󰂀"
                              : smWin._batPct > 40 ? "󰁾"
                              : smWin._batPct > 20 ? "󰁼" : "󰁺"
                    label:    smWin._batStatus === "Full"    ? "Battery ✓"
                              : smWin._batStatus === "Charging" ? "Battery"
                              : "Battery"
                    valStr:   smWin._batPct + "%"
                    sub:      smWin._batStatus
                    arcColor: smWin._batPct <= 20
                              ? Qt.rgba(1.0, 0.3, 0.3, 1)
                              : smWin._batStatus === "Charging"
                                ? Qt.rgba(0.3, 0.9, 0.5, 1)
                                : Theme.cPrimary
                }

                // Disk gauges — auto-appended, deduplicated (matches GJS deduplicateDisks)
                Repeater {
                    model: smWin._disks
                    delegate: ArcGauge {
                        required property var modelData
                        value:    modelData.pct / 100
                        glyph:    "󰋊"
                        label:    modelData.mount === "/"
                                  ? "Root"
                                  : modelData.mount.split("/").pop() || modelData.mount
                        valStr:   modelData.pct + "%"
                        sub:      modelData.used + "/" + modelData.size
                        arcColor: modelData.pct >= 90 ? Qt.rgba(1.0, 0.3, 0.3, 1)
                                  : modelData.pct >= 75 ? Qt.rgba(1.0, 0.7, 0.2, 1)
                                  : Theme.cSecondary
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
            }

            // ── Footer: network rates + uptime/load ───────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 0

                // Left: ↓ rx / ↑ tx
                Column {
                    spacing: 3
                    Row {
                        spacing: 5
                        Text {
                            text: "󰁅"; color: Theme.cPrimary
                            font.pixelSize: 11; font.family: Config.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: smWin._fmtRate(smWin._rxRate)
                            color: Theme.cOnSurf
                            font.pixelSize: 10; font.family: Config.labelFont
                        }
                    }
                    Row {
                        spacing: 5
                        Text {
                            text: "󰁝"; color: Theme.cPrimary
                            font.pixelSize: 11; font.family: Config.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: smWin._fmtRate(smWin._txRate)
                            color: Theme.cOnSurf
                            font.pixelSize: 10; font.family: Config.labelFont
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Right: uptime / load average
                Column {
                    spacing: 3
                    Row {
                        spacing: 5; anchors.right: parent.right
                        Text {
                            text: "󰅐"; color: Theme.cPrimary
                            font.pixelSize: 11; font.family: Config.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Up: " + smWin._uptime
                            color: Theme.cOnSurf
                            font.pixelSize: 10; font.family: Config.labelFont
                        }
                    }
                    Row {
                        spacing: 5; anchors.right: parent.right
                        Text {
                            text: "󰒋"; color: Theme.cPrimary
                            font.pixelSize: 11; font.family: Config.fontFamily
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Load: " + smWin._load
                            color: Theme.cOnSurf
                            font.pixelSize: 10; font.family: Config.labelFont
                        }
                    }
                }
            }

            Item { height: 0 }
        }
    }
}
