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
//  Layout  : 5 gauges per row  (88 × 5 + 8 × 4 gaps + 16 × 2 margins = 504 px)
//
//  GPU     : Discovered by iterating card*/device/driver symlinks.
//            NVIDIA via nvidia-smi. AMD/Intel via sysfs.
//            iGPU shown always (alongside dGPU). dGPU always shown.
//            Heuristics: Intel 00:02.0 → iGPU; AMD APU codenames → iGPU.
//            GPUBUSY lines use a dedicated separator (§) to avoid colon
//            collisions in GPU names from lspci.
// ─────────────────────────────────────────────────────────────────────────────

// Left-click → top-layer popup. Right-click → bottom-layer draggable widget.
Item {
    id: scope

    readonly property bool _active: SystemMonitorPopupState.visible || SystemMonitorPopupState.widgetVisible

    // ── Data ──────────────────────────────────────────────────────────────
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
    property var    _gpus:      []
    property bool   _hasBat:    false
    property real   _batPct:    0
    property string _batStatus: ""
    property string _uptime:    "--"
    property string _load:      "--"
    property var    _prevCpu:   null

    // ── Helpers ───────────────────────────────────────────────────────────
    function _fmtBytes(b) {
        if (b <= 0) return "0 B"
        const k = 1024, s = ["B","KB","MB","GB","TB"]
        const i = Math.min(Math.floor(Math.log(b) / Math.log(k)), 4)
        return parseFloat((b / Math.pow(k, i)).toFixed(1)) + " " + s[i]
    }
    function _fmtUptime(sec) {
        const d = Math.floor(sec / 86400)
        const h = Math.floor((sec % 86400) / 3600)
        const m = Math.floor((sec % 3600) / 60)
        return d > 0 ? d+"d "+h+"h "+m+"m" : h > 0 ? h+"h "+m+"m" : m+"m"
    }

    // ── Poller ────────────────────────────────────────────────────────────
    // Notes on separator choice:
    //   ZONE lines use | between type and value — zone type strings never
    //   contain | but may contain spaces/colons (e.g. "acpi_tz0").
    //   GPUBUSY lines use § (U+00A7) as field separator — GPU names from
    //   lspci often contain colons, so : cannot be used safely here.
    //   BAT/NET/UPTIME/LOAD use : with fields that never contain colons.
    Process {
        id: sysProc
        property var _buf: []

        command: ["bash", "-c",
            // ── CPU ──
            "head -1 /proc/stat;" +
            // ── Memory ──
            "grep -E '^(MemTotal|MemAvailable|SwapTotal|SwapFree):' /proc/meminfo;" +
            // ── Thermal zones (separator | avoids colon issues in zone names) ──
            "for z in /sys/class/thermal/thermal_zone*/; do" +
            " t=$(cat \"${z}temp\" 2>/dev/null);" +
            " y=$(cat \"${z}type\" 2>/dev/null);" +
            " [ -n \"$t\" ] && printf 'ZONE:%s|%s\\n' \"$y\" \"$t\";" +
            " done;" +
            // ── NVIDIA ──
            "command -v nvidia-smi >/dev/null 2>&1 &&" +
            " nvidia-smi --query-gpu=utilization.gpu,name,temperature.gpu --format=csv,noheader,nounits 2>/dev/null" +
            " | while IFS=, read pct name temp; do printf 'NVIDIA:%s:%s:%s\\n' \"${pct// /}\" \"${name# }\" \"${temp// /}\"; done;" +
            // ── AMD / Intel: driver-symlink discovery ──
            // Separator § (never appears in lspci GPU names or driver names)
            "for dp in /sys/class/drm/card*/device/driver; do" +
            " [ -L \"$dp\" ] || continue;" +
            " card=$(echo \"$dp\" | grep -oE 'card[0-9]+');" +
            " drv=$(readlink -f \"$dp\" 2>/dev/null | grep -oE '[^/]+$');" +
            " echo \"$drv\" | grep -qE '^(amdgpu|radeon|i915|xe)$' || continue;" +
            // Always read address from the dedicated file (gives full DBSF like 0000:00:02.0)
            " pci=$(cat /sys/class/drm/$card/device/address 2>/dev/null);" +
            " pname=$(cat /sys/class/drm/$card/device/product_name 2>/dev/null);" +
            // Use card's own PCI address for lspci lookup — never fall back to head -1
            // which would give the wrong GPU's name to every card.
            " if [ -z \"$pname\" ] && [ -n \"$pci\" ]; then pname=$(lspci -D -s \"$pci\" 2>/dev/null | sed 's/.*: //'); fi;" +
            " [ -z \"$pname\" ] && pname=$drv;" +
            " busy=$(cat /sys/class/drm/$card/device/gpu_busy_percent 2>/dev/null);" +
            " if [ -z \"$busy\" ]; then" +
            "   vt=$(cat /sys/class/drm/$card/device/mem_info_vram_total 2>/dev/null);" +
            "   vu=$(cat /sys/class/drm/$card/device/mem_info_vram_used 2>/dev/null);" +
            "   [ -n \"$vt\" ] && [ \"$vt\" -gt 0 ] 2>/dev/null && busy=$(( vu * 100 / vt ));" +
            " fi;" +
            " [ -z \"$busy\" ] && busy=0;" +
            // Temperature: search hwmon entries under this card's device
            " gtemp=0;" +
            " for hw in /sys/class/drm/$card/device/hwmon/hwmon*/temp1_input; do" +
            "   [ -f \"$hw\" ] || continue;" +
            "   raw=$(cat \"$hw\" 2>/dev/null);" +
            "   [ -n \"$raw\" ] && gtemp=$raw && break;" +
            " done;" +
            // iGPU heuristics
            // Intel: i915/xe driver is always iGPU (Arc dGPUs use i915 too but
            // report a PCI function of 00:02.0 only for integrated; Arc cards land
            // on different bus addresses — detect Arc explicitly as dGPU).
            " is_igpu=0;" +
            " if echo \"$drv\" | grep -qE '^(i915|xe)$'; then" +
            "   is_igpu=1;" +
            "   echo \"$pname\" | grep -qiE '\\bArc\\b|\\bAlchemist\\b|\\bBattlemage\\b' && is_igpu=0;" +
            " fi;" +
            // AMD: APU codenames and integrated Radeon branding → iGPU
            " echo \"$pname\" | grep -qiE 'Radeon Graphics|RENOIR|CEZANNE|REMBRANDT|RAPHAEL|PHOENIX|BARCELO|MENDOCINO|HAWK.?POINT|STRIX.?POINT|780M|760M|740M|VEGA|Radeon RX Vega [0-9]' && is_igpu=1;" +
            // Emit with § separator: drv§pname§busy§is_igpu§gtemp
            " printf 'GPUBUSY:%s§%s§%s§%s§%s\\n' \"$drv\" \"$pname\" \"$busy\" \"$is_igpu\" \"$gtemp\";" +
            " done;" +
            // ── Battery ──
            "for b in /sys/class/power_supply/BAT* /sys/class/power_supply/bat*; do" +
            " [ -d \"$b\" ] || continue;" +
            " cap=$(cat \"$b/capacity\" 2>/dev/null);" +
            " sta=$(cat \"$b/status\" 2>/dev/null);" +
            " [ -n \"$cap\" ] && printf 'BAT:%s:%s\\n' \"$cap\" \"$sta\" && break;" +
            " done;" +
            // ── Uptime / Load ──
            "read ut _ < /proc/uptime && printf 'UPTIME:%s\\n' \"$ut\";" +
            "read la _ < /proc/loadavg && printf 'LOAD:%s\\n' \"$la\""
        ]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { if (l.trim() !== "") sysProc._buf.push(l.trim()) }
        }
        onRunningChanged: if (running) _buf = []
        onExited: function() {
            scope._parse(sysProc._buf.slice())
            sysProc._buf = []
        }
    }

    function _parse(lines) {
        let mi = {}
        let tempBest = 0, tempOk = false
        let gpus  = []
        let foundBat = false

        for (const l of lines) {
            // ── CPU ──
            if (l.startsWith("cpu ")) {
                const p = l.split(/\s+/)
                const idle = parseInt(p[4]) + parseInt(p[5])
                let total = 0
                for (let i = 1; i <= 8 && i < p.length; i++) total += parseInt(p[i]) || 0
                if (_prevCpu) {
                    const dt = total - _prevCpu.total, di = idle - _prevCpu.idle
                    if (dt > 0) _cpu = (dt - di) / dt
                }
                _prevCpu = { total, idle }
                continue
            }

            // ── Memory (/proc/meminfo lines: "Key: NNN kB") ──
            const mm = l.match(/^(\w+):\s*(\d+)\s*kB/)
            if (mm) { mi[mm[1]] = parseInt(mm[2]) * 1024; continue }

            // ── Thermal zones (format: ZONE:type|millidegrees) ──
            if (l.startsWith("ZONE:")) {
                const bar = l.indexOf("|")
                if (bar < 0) continue
                const ty = l.slice(5, bar).toLowerCase()
                const v  = parseInt(l.slice(bar + 1)) / 1000
                if (v > 0 && v < 150) {
                    const pref = ty.includes("x86") || ty.includes("pkg") ||
                                 ty.includes("cpu") || ty.includes("core")
                    if (!tempOk || pref) { tempBest = v; tempOk = true }
                }
                continue
            }

            // ── NVIDIA (format: NVIDIA:pct:name:temp) ──
            if (l.startsWith("NVIDIA:")) {
                const rest = l.slice(7)
                const parts = rest.split(":")
                const pct  = parseInt(parts[0]) || 0
                // name may contain colons — rejoin everything between index 1 and last
                const temp = parseInt(parts[parts.length - 1]) || 0
                const name = parts.slice(1, parts.length - 1).join(":")
                              .replace(/NVIDIA\s*GeForce\s*/i, "").replace(/\s+\(.*\)$/, "").trim().slice(0, 14)
                gpus.push({ name: name || "NVIDIA", pct: Math.max(0, pct), temp, type: "nvidia", isIgpu: false })
                continue
            }

            // ── AMD/Intel (format: GPUBUSY:drv§pname§busy§is_igpu§gtemp) ──
            if (l.startsWith("GPUBUSY:")) {
                const inner = l.slice(8)  // strip "GPUBUSY:"
                const p     = inner.split("§")
                if (p.length < 5) continue
                const drv     = p[0] || ""
                const rawName = p[1] || drv
                const pct     = parseInt(p[2]) || 0
                const isIgpu  = p[3] === "1"
                const temp    = Math.round(parseInt(p[4]) / 1000) || 0
                // Clean verbose vendor prefixes from lspci names.
                // IMPORTANT: apply cleaning only to rawName; the fallback drv
                // (e.g. 'amdgpu') must NOT be cleaned — regexes like /\bAMD/i
                // would match 'amd' inside 'amdgpu' and corrupt it to 'gpu'.
                const cleanedName = rawName
                    .replace(/Advanced Micro Devices[^,]*,?\s*/i, "")
                    .replace(/\bAMD\s+/i, "")           // 'AMD Radeon' → 'Radeon'; won't match 'amdgpu'
                    .replace(/ATI(\s+Technologies\s+Inc\.?)?\s*/i, "")
                    .replace(/Intel\s+Corporation\s*/i, "")
                    .replace(/\bIntel\s+/i, "")          // requires trailing space — won't match mid-word
                    .replace(/\[([^\]]+)\]/g, "$1")
                    .replace(/\s+/g, " ").trim()
                const name = (cleanedName.slice(0, 14) || drv.slice(0, 14) || "GPU")
                gpus.push({ name, pct, temp, type: drv, isIgpu })
                continue
            }

            // ── Battery ──
            if (l.startsWith("BAT:")) {
                const p = l.split(":")
                foundBat = true
                _hasBat  = true
                _batPct  = parseInt(p[1]) || 0
                _batStatus = p[2] || ""
                continue
            }

            if (l.startsWith("UPTIME:")) { _uptime = _fmtUptime(parseFloat(l.slice(7))); continue }
            if (l.startsWith("LOAD:"))   { _load   = parseFloat(l.slice(5)).toFixed(2);  continue }
        }

        // No BAT line this cycle → no battery present
        if (!foundBat) _hasBat = false

        // ── Memory ──
        if (mi.MemTotal) {
            _ramTotal = mi.MemTotal
            _ramUsed  = mi.MemTotal - (mi.MemAvailable || 0)
            _ram      = _ramTotal > 0 ? _ramUsed / _ramTotal : 0
        }
        _swapTotal = mi.SwapTotal || 0
        _swapUsed  = _swapTotal - (mi.SwapFree || 0)
        _swap      = _swapTotal > 0 ? _swapUsed / _swapTotal : 0
        _swapOk    = _swapTotal > 0
        _temp = tempBest; _tempOk = tempOk

        // ── GPU filter: show ALL GPUs (both iGPU and dGPU) ───────────────
        // iGPU is only hidden when a dGPU is present AND user is on a system
        // where the iGPU is truly just an internal display engine with no
        // independent workload (NVIDIA Optimus pattern). For AMD/Intel combos,
        // show both so the user can see integrated workload separately.
        // Policy: always show dGPUs; show iGPUs always too (both are useful).
        _gpus = gpus
    }

    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: scope._active
        onTriggered: if (!sysProc.running) sysProc.running = true
    }

    // ── Arc gauge ─────────────────────────────────────────────────────────
    component ArcGauge: Item {
        id: ag
        property real   value:    0
        property string glyph:    ""
        property string label:    ""
        property string valStr:   "--"
        property string sub:      ""
        property color  arcColor: Theme.cPrimary

        implicitWidth:  88
        implicitHeight: 112

        Behavior on value { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

        Canvas {
            id: arcC
            anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
            width: 78; height: 78

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
                const cx = width/2, cy = height/2, r = 31, lw = 6
                const S = 0.75*Math.PI, E = 2.25*Math.PI
                const onS = Theme.cOnSecondary
                ctx.lineWidth = lw; ctx.lineCap = "round"
                ctx.beginPath(); ctx.arc(cx, cy, r, S, E)
                ctx.strokeStyle = Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.35).toString()
                ctx.stroke()
                if (_v > 0.005) {
                    ctx.beginPath(); ctx.arc(cx, cy, r, S, S + _v*(E-S))
                    ctx.strokeStyle = _ac.toString(); ctx.stroke()
                }
                ctx.fillStyle = Qt.rgba(_ac.r, _ac.g, _ac.b, 0.90).toString()
                ctx.font = "16px 'Symbols Nerd Font Mono'"
                ctx.textAlign = "center"; ctx.textBaseline = "alphabetic"
                ctx.fillText(_gl, cx, cy + 2)
                ctx.fillStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.88).toString()
                ctx.font = "bold 9px monospace"
                ctx.textBaseline = "top"
                ctx.fillText(_vt, cx, cy + 6)
            }
        }

        Text {
            anchors.top: arcC.bottom; anchors.topMargin: 2
            anchors.horizontalCenter: parent.horizontalCenter
            text: ag.sub; color: Theme.cOnSecondary
            font.pixelSize: 11; font.family: Config.labelFont
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight; width: parent.width
        }
        Text {
            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
            text: ag.label; color: Theme.cOnSecondary
            font.pixelSize: 12; font.family: Config.labelFont
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── Dials Card (used in popup panel and widget) ───────────────────────
    component GaugesCard: Rectangle {
        id: cardRoot
        required property var root

        radius: 16
        color: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g,
                       Theme.cSurfaceTint.b, 0.65)
        border.width: 1
        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)

        // Unified list of all active dials
        readonly property var _dials: {
            let list = []
            // 1. CPU
            list.push({
                value: cardRoot.root._cpu,
                glyph: "󰻠",
                label: "CPU",
                valStr: Math.round(cardRoot.root._cpu * 100) + "%",
                sub: "",
                arcColor: Theme.cWc5
            })
            // 2. RAM
            list.push({
                value: cardRoot.root._ram,
                glyph: "󰍛",
                label: "RAM",
                valStr: Math.round(cardRoot.root._ram * 100) + "%",
                sub: cardRoot.root._fmtBytes(cardRoot.root._ramUsed),
                arcColor: Theme.cWc5
            })
            // 3. Temp
            list.push({
                value: cardRoot.root._tempOk ? Math.min(cardRoot.root._temp / 100, 1) : 0,
                glyph: "󰔏",
                label: "Temp",
                valStr: cardRoot.root._tempOk ? Math.round(cardRoot.root._temp) + "°" : "N/A",
                sub: "",
                arcColor: cardRoot.root._tempOk && cardRoot.root._temp > 80 ? Qt.rgba(1.0, 0.4, 0.2, 1) : Theme.cWc4
            })
            // 4. Swap (if swapOk)
            if (cardRoot.root._swapOk) {
                list.push({
                    value: cardRoot.root._swap,
                    glyph: "󰾴",
                    label: "Swap",
                    valStr: Math.round(cardRoot.root._swap * 100) + "%",
                    sub: cardRoot.root._fmtBytes(cardRoot.root._swapUsed),
                    arcColor: Theme.cWc4
                })
            }
            // 5. NPU (from SystemMonitorPopupState.npus)
            for (let i = 0; i < SystemMonitorPopupState.npus.length; i++) {
                const npu = SystemMonitorPopupState.npus[i]
                list.push({
                    value: (npu.pct || 0) / 100,
                    glyph: "󰧑",
                    label: "NPU",
                    valStr: (npu.pct || 0) + "%",
                    sub: (npu.name || "NPU").slice(0, 8),
                    arcColor: Theme.cWc1
                })
            }
            // 6. GPUs — all detected GPUs shown (iGPU and dGPU both visible)
            for (let i = 0; i < cardRoot.root._gpus.length; i++) {
                const gpu = cardRoot.root._gpus[i]
                list.push({
                    value: (gpu.pct || 0) / 100,
                    glyph: gpu.isIgpu ? "󱤓" : "󰢮",
                    label: gpu.isIgpu ? "iGPU" : "dGPU",
                    valStr: (gpu.pct || 0) + "%",
                    sub: (gpu.temp > 0 ? gpu.temp + "°  " : "") + (gpu.name || "GPU").slice(0, 8),
                    arcColor: Theme.cWc3
                })
            }
            // 7. Battery — laptops only; hidden on desktops
            if (cardRoot.root._hasBat) {
                const bPct = cardRoot.root._batPct
                const bSta = cardRoot.root._batStatus
                list.push({
                    value: bPct / 100,
                    glyph: bPct > 80 ? "󰁹" : bPct > 60 ? "󰂀" : bPct > 40 ? "󰁾" : bPct > 20 ? "󰁼" : "󰁺",
                    label: bSta === "Full" ? "Battery " : bSta === "Charging" ? "Battery 󱐋" : "Battery",
                    valStr: bPct + "%",
                    sub: bSta,
                    arcColor: bPct <= 20 ? Qt.rgba(1.0, 0.3, 0.3, 1) : bSta === "Charging" ? Qt.rgba(0.3, 0.9, 0.5, 1) : Theme.cWc6
                })
            }
            return list
        }

        readonly property int _pairCount: Math.floor(_dials.length / 2)
        readonly property bool _hasOddRemainder: _dials.length % 2 === 1
        readonly property int _rowCount: Math.ceil(_dials.length / 2)

        implicitWidth: 88 * 2 + 12 + 24
        implicitHeight: _rowCount * 112 + Math.max(0, _rowCount - 1) * 10 + 24 + 28

        ColumnLayout {
            id: dialsCol
            anchors {
                top: parent.top
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                topMargin: 12
                bottomMargin: 12
            }
            width: 88 * 2 + 12
            spacing: 10

            // 2-column paired rows
            Repeater {
                model: cardRoot._pairCount
                delegate: RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    required property int index

                    ArcGauge {
                        readonly property var d: cardRoot._dials[index * 2]
                        value:    d ? d.value : 0
                        glyph:    d ? d.glyph : ""
                        label:    d ? d.label : ""
                        valStr:   d ? d.valStr : "--"
                        sub:      d ? d.sub : ""
                        arcColor: d ? d.arcColor : Theme.cPrimary
                    }

                    ArcGauge {
                        readonly property var d: cardRoot._dials[index * 2 + 1]
                        value:    d ? d.value : 0
                        glyph:    d ? d.glyph : ""
                        label:    d ? d.label : ""
                        valStr:   d ? d.valStr : "--"
                        sub:      d ? d.sub : ""
                        arcColor: d ? d.arcColor : Theme.cPrimary
                    }
                }
            }

            // Odd remainder: single dial at the bottom, centered
            Item {
                visible: cardRoot._hasOddRemainder
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 88
                implicitHeight: 112

                ArcGauge {
                    anchors.centerIn: parent
                    readonly property var d: cardRoot._hasOddRemainder ? cardRoot._dials[cardRoot._dials.length - 1] : null
                    value:    d ? d.value : 0
                    glyph:    d ? d.glyph : ""
                    label:    d ? d.label : ""
                    valStr:   d ? d.valStr : "--"
                    sub:      d ? d.sub : ""
                    arcColor: d ? d.arcColor : Theme.cPrimary
                }
            }

            // Bottom of inner card: Load (left-aligned) and Uptime (right-aligned)
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                Layout.topMargin: 4

                Row {
                    Layout.alignment: Qt.AlignLeft
                    spacing: 5
                    Text {
                        text: "󰒋"
                        color: Theme.cOnSecondary
                        font.pixelSize: 11
                        font.family: Config.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Load: " + cardRoot.root._load
                        color: Theme.cOnPrimary
                        font.pixelSize: 10
                        font.family: Config.labelFont
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Item { Layout.fillWidth: true }

                Row {
                    Layout.alignment: Qt.AlignRight
                    spacing: 5
                    Text {
                        text: "󰅐"
                        color: Theme.cOnSecondary
                        font.pixelSize: 11
                        font.family: Config.fontFamily
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "Up: " + cardRoot.root._uptime
                        color: Theme.cOnPrimary
                        font.pixelSize: 10
                        font.family: Config.labelFont
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    component SysMonPanel: Rectangle {
        id: smPanel
        required property var root
        property bool showClose: true
        property bool popupMode: false

        width: gaugesCard.implicitWidth + 24
        implicitHeight: gaugesCard.implicitHeight + 24

        topLeftRadius: 20
        topRightRadius: 20
        bottomLeftRadius: 20
        bottomRightRadius: 20
        color: Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

        scale: popupMode && SystemMonitorPopupState.visible ? 1.0 : (popupMode ? 0.92 : 1.0)
        opacity: popupMode ? (SystemMonitorPopupState.visible ? 1.0 : 0.0) : 1.0
        transformOrigin: popupMode && Config.barPosition === "bottom" ? Item.BottomRight : Item.TopRight
        Behavior on scale   { enabled: popupMode; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on opacity { enabled: popupMode; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        GaugesCard {
            id: gaugesCard
            root: smPanel.root
            anchors.centerIn: parent
        }

        MouseArea {
            anchors.fill: parent
            enabled: popupMode
            cursorShape: Qt.PointingHandCursor
            onClicked: SystemMonitorPopupState.close()
        }
    }

    PanelWindow {
        id: smPopup
        readonly property bool _barAtBottom: Config.barPosition === "bottom"
        readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop) : Config.outerMarginTop) + Config.barHeight + 4
        readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom) : Config.outerMarginBottom) + Config.barHeight + 4
        readonly property real _panelMargin: Config.barMode === "shell" ? Config.popupSideMargin : Config.popupSideMargin * 2

        // ── Deferred-destroy animation pattern ──────────────────────────────
        property bool _stateVisible: SystemMonitorPopupState.visible
        Timer { id: _smExitDelay; interval: 220; repeat: false }
        visible: _stateVisible || _smExitDelay.running
        on_StateVisibleChanged: { if (!_stateVisible) _smExitDelay.restart() }

        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
        margins {
            top: _barAtBottom ? 0 : _barGap
            bottom: _barAtBottom ? _barGapBot : 0
        }

        implicitHeight: smPanelPopup.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:sysmon-popup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"

        Connections {
            target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
            ignoreUnknownSignals: true
            function onAddressChanged() {
                if (HyprlandFocusedClient.address !== "")
                    SystemMonitorPopupState.close()
            }
        }

        MouseArea { anchors.fill: parent; z: -1; onClicked: SystemMonitorPopupState.close() }

        SysMonPanel {
            id: smPanelPopup
            root: scope
            showClose: true
            popupMode: true
            anchors {
                right: parent.right
                rightMargin: smPopup._panelMargin
                top: parent.top
                bottom: parent.bottom
            }
        }
    }

    PinnedWidgetWindow {
        id: sysmonWidget
        active: SystemMonitorPopupState.widgetVisible
        widgetNamespace: "quickshell:sysmon-widget"
        onActiveChanged: {
            if (active) {
                sysmonWidget.posX = SystemMonitorPopupState.widgetX
                sysmonWidget.posY = SystemMonitorPopupState.widgetY
            }
        }
        onPositionCommitted: function(x, y) {
            SystemMonitorPopupState.widgetX = Math.round(x)
            SystemMonitorPopupState.widgetY = Math.round(y)
        }

        Rectangle {
            implicitWidth: widgetDials.implicitWidth + 20
            implicitHeight: widgetDials.implicitHeight + 20
            radius: 24
            color: Theme.blurBackground
            border.width: Config.barBorderWidth
            border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                                  Config.barBorderColor.b, Config.barBorderAlpha)

            GaugesCard {
                id: widgetDials
                root: scope
                anchors.centerIn: parent
            }
        }
    }
}
