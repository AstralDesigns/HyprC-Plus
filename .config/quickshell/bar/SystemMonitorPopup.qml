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
    // Set true after the first successful _parse(); gates the popup enter-animation
    // so dials never appear empty. Resets when popup/widget both go inactive.
    property bool   _hasData:   false

    on_ActiveChanged: {
        // Fresh activation (neither widget nor popup was already running) — reset
        // so the popup waits for the first data batch before animating in.
        if (_active && !SystemMonitorPopupState.widgetVisible) _hasData = false
    }

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
    // Clamp a device name to `n` chars, appending an ellipsis when truncated
    // so shortened GPU/NPU names read clearly instead of cutting off mid-word.
    function _trunc(s, n) {
        if (!s) return ""
        return s.length > n ? s.slice(0, n) + "\u2026" : s
    }
    // Short vendor label for a GPU dial's arc-gap text (preferred over the raw
    // driver name). Derived from the driver/type field so it stays stable even
    // when the lspci product name is empty.
    function _vendor(g) {
        const t = (g && g.type ? g.type : "").toLowerCase()
        if (t === "nvidia" || t === "nouveau") return "NVIDIA"
        if (t === "amdgpu" || t === "radeon")  return "AMD"
        if (t === "i915"   || t === "xe")       return "Intel"
        if (t === "vc4"    || t === "v3d")      return "Broadcom"
        if (t === "panfury" || t === "lima")    return "Arm"
        // Unknown driver: fall back to a truncated product name, else the driver.
        return g && g.name ? _trunc(g.name, 8) : _trunc(t, 8)
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
        // Order the accelerator dials so any iGPU precedes the dGPU(s); the NPU
        // dial(s) are inserted ahead of all GPUs in GaugesCard._dials.
        gpus.sort((a, b) => (b.isIgpu ? 1 : 0) - (a.isIgpu ? 1 : 0))
        _gpus = gpus
        // Mark data as ready — unlocks the popup enter-animation
        _hasData = true
    }

    Timer {
        interval: 2000; repeat: true; triggeredOnStart: true
        running: scope._active
        onTriggered: if (!sysProc.running) sysProc.running = true
    }

    // ── Unified dial list ───────────────────────────────────────────────────
    // Single source of truth shared by the popup GaugesCard and the widget's
    // per-dial cards. Order: NPU first, then iGPU before dGPU(s); battery last.
    readonly property var _dials: {
        let list = []
        // 1. CPU
        list.push({
            value: scope._cpu,
            glyph: "󰻠",
            label: "CPU",
            valStr: Math.round(scope._cpu * 100) + "%",
            sub: "",
            arcColor: Theme.cWc5
        })
        // 2. RAM
        list.push({
            value: scope._ram,
            glyph: "󰍛",
            label: "RAM",
            valStr: Math.round(scope._ram * 100) + "%",
            sub: scope._fmtBytes(scope._ramUsed),
            arcColor: Theme.cWc5
        })
        // 3. Temp
        list.push({
            value: scope._tempOk ? Math.min(scope._temp / 100, 1) : 0,
            glyph: "󰔏",
            label: "Temp",
            valStr: scope._tempOk ? Math.round(scope._temp) + "°" : "N/A",
            sub: "",
            arcColor: scope._tempOk && scope._temp > 80 ? Qt.rgba(1.0, 0.4, 0.2, 1) : Theme.cWc4
        })
        // 4. Swap (if swapOk)
        if (scope._swapOk) {
            list.push({
                value: scope._swap,
                glyph: "\u{F04E1}",   // md-swap_horizontal
                label: "Swap",
                valStr: Math.round(scope._swap * 100) + "%",
                sub: scope._fmtBytes(scope._swapUsed),
                arcColor: Theme.cWc4
            })
        }
        // 5. NPU (from SystemMonitorPopupState.npus)
        for (let i = 0; i < SystemMonitorPopupState.npus.length; i++) {
            const npu = SystemMonitorPopupState.npus[i]
            list.push({
                value: (npu.pct || 0) / 100,
                glyph: "󰧑",
                label: "NPU" + (npu.name ? " " + scope._trunc(npu.name, 8) : ""),
                valStr: (npu.pct || 0) + "%",
                sub: "",
                arcColor: Theme.cWc1
            })
        }
        // 6. GPUs — all detected GPUs shown (iGPU precedes dGPU via _parse sort)
        for (let i = 0; i < scope._gpus.length; i++) {
            const gpu = scope._gpus[i]
            list.push({
                value: (gpu.pct || 0) / 100,
                glyph: gpu.isIgpu ? "󱤓" : "󰢮",
                gapText: scope._vendor(gpu),
                label: (gpu.isIgpu ? "iGPU" : "dGPU") + (gpu.name ? " " + scope._trunc(gpu.name, 8) : ""),
                valStr: (gpu.pct || 0) + "%",
                sub: gpu.temp > 0 ? gpu.temp + "°" : "",
                arcColor: Theme.cWc3
            })
        }
        // 7. Battery — laptops only; hidden on desktops
        if (scope._hasBat) {
            const bPct = scope._batPct
            const bSta = scope._batStatus
            list.push({
                value: bPct / 100,
                // The arc already encodes charge level, so the gap glyph only
                // signals power state: bolt when plugged/charging, plain battery
                // when discharging, alert battery when very low (<=20%).
                glyph: bSta !== "Discharging" ? "\u{F140C}"
                           : bPct <= 20 ? "\u{F12A1}" : "\u{F0EC3}",
                label: "Battery",
                valStr: bPct + "%",
                arcColor: bPct <= 20 ? Qt.rgba(1.0, 0.3, 0.3, 1) : bSta === "Charging" ? Qt.rgba(0.3, 0.9, 0.5, 1) : Theme.cWc6
            })
        }
        return list
    }

    // ── Arc gauge (popup) — value+sub inside the ring, icon in the bottom gap ─
    // The 270° ring leaves an open gap at the bottom centre; the metric's colored
    // glyph now sits in that gap instead of a separate title row (the "CPU"/"RAM"
    // … labels are gone). GPU dials put a short vendor name (Intel/AMD/NVIDIA) in
    // the gap via `gapText` instead of the glyph. The ring interior carries the
    // primary value large with an optional small secondary line beneath it.
    component ArcGauge: Item {
        id: ag
        property real   value:    0
        property string glyph:    ""
        property string gapText:  ""     // when non-empty, replaces the gap glyph
        property string valStr:   "--"
        property string sub:      ""
        property bool   subGlyph: false  // sub is a Nerd-Font icon (battery charge) → bigger + icon font
        property color  arcColor: Theme.cPrimary

        implicitWidth:  88
        implicitHeight: 84

        Behavior on value { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

        Canvas {
            id: arcC
            anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
            width: 82; height: 82

            property real   _v:  ag.value
            property color  _ac: ag.arcColor
            property string _vt: ag.valStr
            property string _sb: ag.sub
            property bool   _sg: ag.subGlyph

            on_VChanged:  requestPaint()
            on_AcChanged: requestPaint()
            on_VtChanged: requestPaint()
            on_SbChanged: requestPaint()
            on_SgChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const cx = width/2, cy = height/2, r = 33, lw = 6
                const S = 0.75*Math.PI, E = 2.25*Math.PI
                const onS = Theme.cOnSecondary
                ctx.lineWidth = lw; ctx.lineCap = "round"
                ctx.beginPath(); ctx.arc(cx, cy, r, S, E)
                ctx.strokeStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.35).toString()
                ctx.stroke()
                if (_v > 0.005) {
                    ctx.beginPath(); ctx.arc(cx, cy, r, S, S + _v*(E-S))
                    ctx.strokeStyle = _ac.toString(); ctx.stroke()
                }
                // Data centered in the ring, nudged up to leave the bottom gap
                // clear for the icon/vendor text. Sub line is 2px smaller than
                // before to keep the ring interior tidy.
                ctx.textAlign = "center"
                ctx.fillStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.94).toString()
                if (_sb) {
                    ctx.font = "bold 15px '" + Config.labelFont + "'"
                    ctx.textBaseline = "bottom"
                    ctx.fillText(_vt, cx, cy - 2)
                    if (_sg) {
                        // Battery charge/discharge glyph: drawn with the icon
                        // font. Shifted ~1px left to cancel the glyph's extra
                        // left side-bearing (advance-width centering sits right).
                        ctx.font = "12px '" + Config.fontFamily + "'"
                        ctx.textBaseline = "top"
                        ctx.fillText(_sb, cx - 1, cy + 1)
                    } else {
                        ctx.font = "10px '" + Config.labelFont + "'"
                        ctx.textBaseline = "top"
                        ctx.fillText(_sb, cx, cy)
                    }
                } else {
                    ctx.font = "bold 15px '" + Config.labelFont + "'"
                    ctx.textBaseline = "middle"
                    ctx.fillText(_vt, cx, cy - 5)
                }
            }
        }

        // Bottom-gap content: the metric glyph (most dials) or a short vendor
        // name (GPU dials). Positioned in the open 90° gap at the ring's base.
        Text {
            visible: ag.gapText === "" && ag.glyph !== ""
            text: ag.glyph; color: Theme.cOnSecondary
            font.pixelSize: 15; font.family: Config.fontFamily
            anchors.horizontalCenter: arcC.horizontalCenter
            anchors.bottom: arcC.bottom; anchors.bottomMargin: 8
        }
        Text {
            visible: ag.gapText !== ""
            text: ag.gapText; color: Theme.cOnSecondary
            font.pixelSize: 9; font.family: Config.labelFont
            anchors.horizontalCenter: arcC.horizontalCenter
            anchors.bottom: arcC.bottom; anchors.bottomMargin: 8
        }
    }



    // ── Compact gauge (widget) — value+sub inside the ring, glyph in the gap ──
    // Minimal grid cell mirroring the popup layout but smaller: the ring carries
    // the value (large) with an optional sub line beneath it, and the metric's
    // glyph sits in the open bottom gap. No labels, and (unlike the popup GPUs)
    // the widget always shows the glyph rather than a vendor name.
    component CompactGauge: Item {
        id: cg
        property real   value:    0
        property string glyph:    ""
        property string gapText:  ""     // widget ignores this — always shows the glyph
        property string valStr:   "--"
        property string sub:      ""
        property bool   subGlyph: false  // sub is a Nerd-Font icon (battery charge) → bigger + icon font
        property color  arcColor: Theme.cPrimary
        property int    ringSize: 68

        implicitWidth:  88
        implicitHeight: ringSize + 6

        Behavior on value { NumberAnimation { duration: 800; easing.type: Easing.OutCubic } }

        // Small arc ring: value (+ optional sub) centered inside.
        Canvas {
            id: cgRing
            anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
            width: cg.ringSize; height: cg.ringSize

            property real   _v: cg.value
            property color  _ac: cg.arcColor
            property string _vt: cg.valStr
            property string _sb: cg.sub
            property bool   _sg: cg.subGlyph
            on_VChanged:  requestPaint()
            on_AcChanged: requestPaint()
            on_VtChanged: requestPaint()
            on_SbChanged: requestPaint()
            on_SgChanged: requestPaint()
            Component.onCompleted: requestPaint()

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const cx = width/2, cy = height/2, lw = 5, r = cx - lw
                const S = 0.75*Math.PI, E = 2.25*Math.PI
                const onS = Theme.cOnSecondary
                ctx.lineWidth = lw; ctx.lineCap = "round"
                ctx.beginPath(); ctx.arc(cx, cy, r, S, E)
                ctx.strokeStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.35).toString()
                ctx.stroke()
                if (_v > 0.005) {
                    ctx.beginPath(); ctx.arc(cx, cy, r, S, S + _v*(E-S))
                    ctx.strokeStyle = _ac.toString(); ctx.stroke()
                }
                // Value + optional sub inside the ring, nudged up for the gap glyph.
                ctx.fillStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.92).toString()
                ctx.textAlign = "center"
                const vpx = Math.round(width*0.24)
                if (_sb) {
                    ctx.font = "bold " + vpx + "px '" + Config.labelFont + "'"
                    ctx.textBaseline = "bottom"
                    ctx.fillText(_vt, cx, cy)
                    if (_sg) {
                        // Battery charge/discharge glyph: icon font, shifted ~1px
                        // left to cancel the glyph's extra left side-bearing.
                        ctx.font = Math.round(width*0.19) + "px '" + Config.fontFamily + "'"
                        ctx.textBaseline = "top"
                        ctx.fillText(_sb, cx - 1, cy + 1)
                    } else {
                        ctx.font = Math.round(width*0.15) + "px '" + Config.labelFont + "'"
                        ctx.textBaseline = "top"
                        ctx.fillText(_sb, cx, cy + 1)
                    }
                } else {
                    ctx.font = "bold " + vpx + "px '" + Config.labelFont + "'"
                    ctx.textBaseline = "middle"
                    ctx.fillText(_vt, cx, cy - 3)
                }
            }
        }

        // Metric glyph in the ring's bottom gap (no label / vendor text).
        Text {
            visible: cg.glyph !== ""
            text: cg.glyph; color: Theme.cOnSecondary
            font.pixelSize: 13; font.family: Config.fontFamily
            anchors.horizontalCenter: cgRing.horizontalCenter
            anchors.bottom: cgRing.bottom; anchors.bottomMargin: 5
        }
    }



    // ── Widget per-dial mini card ──────────────────────────────────────────
    // Each dial gets its own bordered tile so the widget reads as a cluster of
    // small cards instead of one slab. All tiles live inside the single
    // PinnedWidgetWindow body, so one drag anywhere still moves the whole grid.
    component WidgetDialCard: Rectangle {
        id: wdc
        required property var root
        required property var dial
        implicitWidth: 100
        implicitHeight: 82
        radius: 16
        color: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g,
                       Theme.cSurfaceTint.b, 0.65)
        border.width: 1
        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)

        CompactGauge {
            anchors.centerIn: parent
            value:    wdc.dial ? wdc.dial.value : 0
            glyph:    wdc.dial ? wdc.dial.glyph : ""
            gapText:  (wdc.dial && wdc.dial.gapText) ? wdc.dial.gapText : ""
            subGlyph: (wdc.dial && wdc.dial.subGlyph) === true
            valStr:   wdc.dial ? wdc.dial.valStr : "--"
            sub:      wdc.dial ? wdc.dial.sub : ""
            arcColor: wdc.dial ? wdc.dial.arcColor : Theme.cPrimary
        }
    }

    // ── Widget Load / Uptime footer card (separate from the dials) ─────────
    component WidgetFooterCard: Rectangle {
        id: wfc
        required property var root
        implicitHeight: 30
        radius: 16
        color: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g,
                       Theme.cSurfaceTint.b, 0.65)
        border.width: 1
        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)

        RowLayout {
            anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
            spacing: 5
            Text {
                text: "󰒋"; color: Theme.cOnSecondary
                font.pixelSize: 11; font.family: Config.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "Load: " + wfc.root._load; color: Theme.cOnPrimary
                font.pixelSize: 10; font.family: Config.labelFont
                anchors.verticalCenter: parent.verticalCenter
            }
            Item { Layout.fillWidth: true; Layout.preferredWidth: 1 }
            Text {
                text: "󰅐"; color: Theme.cOnSecondary
                font.pixelSize: 11; font.family: Config.fontFamily
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: "Up: " + wfc.root._uptime; color: Theme.cOnPrimary
                font.pixelSize: 10; font.family: Config.labelFont
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    // ── Dials Card (used in popup panel and widget) ───────────────────────
    component GaugesCard: Rectangle {
        id: cardRoot
        required property var root
        property bool compact: false

        radius: 16
        color: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g,
                       Theme.cSurfaceTint.b, 0.65)
        border.width: 1
        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)

        // Unified dial list lives on `scope._dials` so the popup and the
        // widget's per-dial cards read from a single source.
        readonly property var _dials: cardRoot.root._dials

        readonly property int _pairCount: Math.floor(_dials.length / 2)
        readonly property bool _hasOddRemainder: _dials.length % 2 === 1
        readonly property int _rowCount: Math.ceil(_dials.length / 2)

        implicitWidth: 88 * 2 + 12 + 24
        // Row stack + spacing + 24px internal padding (12 top + 12 bottom) + 28px footer
        implicitHeight: compact
            ? (_rowCount * 66 + Math.max(0, _rowCount - 1) * 10 + 24 + 28)
            : (_rowCount * 84 + Math.max(0, _rowCount - 1) * 10 + 24 + 28)

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
            spacing: compact ? 6 : 10

            // 2-column paired rows (popup only)
            Repeater {
                model: cardRoot.compact ? 0 : cardRoot._pairCount
                delegate: RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    required property int index

                    ArcGauge {
                        readonly property var d: cardRoot._dials[index * 2]
                        value:    d ? d.value : 0
                        glyph:    d ? d.glyph : ""
                        gapText:  (d && d.gapText) ? d.gapText : ""
                        subGlyph: (d && d.subGlyph) === true
                        valStr:   d ? d.valStr : "--"
                        sub:      d ? d.sub : ""
                        arcColor: d ? d.arcColor : Theme.cPrimary
                    }

                    ArcGauge {
                        readonly property var d: cardRoot._dials[index * 2 + 1]
                        value:    d ? d.value : 0
                        glyph:    d ? d.glyph : ""
                        gapText:  (d && d.gapText) ? d.gapText : ""
                        subGlyph: (d && d.subGlyph) === true
                        valStr:   d ? d.valStr : "--"
                        sub:      d ? d.sub : ""
                        arcColor: d ? d.arcColor : Theme.cPrimary
                    }
                }
            }

            // Odd remainder: single dial at the bottom, centered (popup only)
            Item {
                visible: cardRoot._hasOddRemainder && !cardRoot.compact
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 88
                implicitHeight: 84

                ArcGauge {
                    anchors.centerIn: parent
                    readonly property var d: cardRoot._hasOddRemainder ? cardRoot._dials[cardRoot._dials.length - 1] : null
                    value:    d ? d.value : 0
                    glyph:    d ? d.glyph : ""
                    gapText:  (d && d.gapText) ? d.gapText : ""
                    subGlyph: (d && d.subGlyph) === true
                    valStr:   d ? d.valStr : "--"
                    sub:      d ? d.sub : ""
                    arcColor: d ? d.arcColor : Theme.cPrimary
                }
            }

            // Compact 2-column paired rows (widget only) — same pairing as popup
            Repeater {
                model: cardRoot.compact ? cardRoot._pairCount : 0
                delegate: RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 12

                    required property int index

                    CompactGauge {
                        readonly property var d: cardRoot._dials[index * 2]
                        value:    d ? d.value : 0
                        glyph:    d ? d.glyph : ""
                        gapText:  (d && d.gapText) ? d.gapText : ""
                        subGlyph: (d && d.subGlyph) === true
                        valStr:   d ? d.valStr : "--"
                        sub:      d ? d.sub : ""
                        arcColor: d ? d.arcColor : Theme.cPrimary
                    }

                    CompactGauge {
                        readonly property var d: cardRoot._dials[index * 2 + 1]
                        value:    d ? d.value : 0
                        glyph:    d ? d.glyph : ""
                        gapText:  (d && d.gapText) ? d.gapText : ""
                        subGlyph: (d && d.subGlyph) === true
                        valStr:   d ? d.valStr : "--"
                        sub:      d ? d.sub : ""
                        arcColor: d ? d.arcColor : Theme.cPrimary
                    }
                }
            }

            // Compact odd remainder: single cell centered at the bottom (widget only)
            Item {
                visible: cardRoot.compact && cardRoot._hasOddRemainder
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 88
                implicitHeight: 66

                CompactGauge {
                    anchors.centerIn: parent
                    readonly property var d: cardRoot._hasOddRemainder ? cardRoot._dials[cardRoot._dials.length - 1] : null
                    value:    d ? d.value : 0
                    glyph:    d ? d.glyph : ""
                    gapText:  (d && d.gapText) ? d.gapText : ""
                    subGlyph: (d && d.subGlyph) === true
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

        // Gate on _hasData: popup stays invisible until the first poll completes,
        // preventing empty-dial flash on first open.
        scale: popupMode ? (SystemMonitorPopupState.visible && smPanel.root._hasData ? 1.0 : 0.92) : 1.0
        opacity: popupMode ? (SystemMonitorPopupState.visible && smPanel.root._hasData ? 1.0 : 0.0) : 1.0
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

        // StartMenu-style backdrop: full width, single bar-edge anchor, tall
        // enough to reach the far screen edge so the z:-1 backdrop catches a
        // click anywhere. Single vertical anchor avoids full-height stretch on
        // bar-position toggle.
        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
        margins {
            top:    _barAtBottom ? 0 : _barGap
            bottom: _barAtBottom ? _barGapBot : 0
        }

        implicitHeight: (screen ? screen.height : 1080)
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
            }
            y: smPopup._barAtBottom ? (parent.height - height) : 0
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

        // Split-card widget: a 2-column grid of per-dial tiles plus a separate
        // full-width Load/Uptime tile. No unifying slab — each tile draws its
        // own border. The whole cluster sits in one PinnedWidgetWindow body, so
        // a single drag anywhere moves everything together.
        Item {
            id: widgetBody
            width: widgetCol.implicitWidth
            height: widgetCol.implicitHeight

            ColumnLayout {
                id: widgetCol
                anchors.left: parent.left
                anchors.top: parent.top
                spacing: 8

                GridLayout {
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8

                    Repeater {
                        // Stable int model — delegates persist across the 2s poll
                        // instead of being recreated each cycle (which re-ran the
                        // 0→value enter animation and made the tiles "pulse").
                        model: scope._dials.length
                        delegate: WidgetDialCard {
                            required property int index
                            root: scope
                            dial: scope._dials[index]
                            // Lone tile on an odd final row spans both columns and
                            // centers, mirroring the popup's odd-remainder handling.
                            readonly property bool _lastOdd: scope._dials.length % 2 === 1
                                                             && index === scope._dials.length - 1
                            Layout.columnSpan: _lastOdd ? 2 : 1
                            Layout.alignment: _lastOdd ? Qt.AlignHCenter : Qt.AlignLeft
                        }
                    }
                }

                WidgetFooterCard {
                    root: scope
                    Layout.fillWidth: true
                }
            }
        }
    }
}
