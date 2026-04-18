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
//
//  Disks   : Shows /, /home, /boot* from internal devices (deduped by device
//            to collapse btrfs subvolumes). Also shows all mounts under
//            /media, /run/media, /mnt (external/removable), deduped by device.
//            Skips tmpfs, devtmpfs, squashfs, overlay, efivarfs.
//
//  Fixes vs prior version
//    • GPUBUSY separator changed → § so GPU names with colons parse correctly
//    • iGPU now always shown (alongside dGPU, not hidden by it)
//    • awk quoting fixed → UPTIME/LOAD lines now emit correctly
//    • Thermal ZONE separator uses | to avoid colon collisions in zone types
//    • df uses -b (bytes) + awk post-processing to avoid case ambiguity in K/k
//    • Battery: _hasBat initialised from BAT: lines every poll cycle, not just
//      once at startup — works even when batDetectProc races
//    • External drives deduplicated by device (handles btrfs subvolumes)
//    • All internal mount dedup also by device, not just by mount path
// ─────────────────────────────────────────────────────────────────────────────

PanelWindow {
    id: smWin

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap:    Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot: Config.outerMarginBottom + Config.barHeight + 6
    readonly property real _panelMargin: Config.outerMarginSide * 2

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

    Connections {
        target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                SystemMonitorPopupState.close()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onClicked: SystemMonitorPopupState.close() }

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
    property var    _disks:     []
    property real   _rxRate:    0
    property real   _txRate:    0
    property var    _prevNet:   null
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
    function _fmtDisk(bytes) {
        const b = parseInt(bytes) || 0
        if (b >= 1099511627776) return (b / 1099511627776).toFixed(1) + " TB"
        if (b >= 1073741824)    return (b / 1073741824).toFixed(1) + " GB"
        if (b >= 1048576)       return (b / 1048576).toFixed(0) + " MB"
        if (b >= 1024)          return (b / 1024).toFixed(0) + " KB"
        return b + " B"
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
            " pci=$(cat /sys/class/drm/$card/device/address 2>/dev/null);" +
            " pname=$(cat /sys/class/drm/$card/device/product_name 2>/dev/null);" +
            " [ -z \"$pname\" ] && pname=$(lspci -D -s \"$pci\" 2>/dev/null | sed 's/.*: //');" +
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
            " is_igpu=0;" +
            " (echo \"$drv\" | grep -qE '^(i915|xe)$' && echo \"$pci\" | grep -q ':00:02.0') && is_igpu=1;" +
            " echo \"$pname\" | grep -qiE 'Radeon Graphics|RENOIR|CEZANNE|REMBRANDT|RAPHAEL|PHOENIX|BARCELO|MENDOCINO|HAWK.?POINT|STRIX.?POINT|780M|760M|740M|VEGA' && is_igpu=1;" +
            // Emit with § separator: drv§pname§busy§is_igpu§gtemp
            " printf 'GPUBUSY:%s§%s§%s§%s§%s\\n' \"$drv\" \"$pname\" \"$busy\" \"$is_igpu\" \"$gtemp\";" +
            " done;" +
            // ── Disks (bytes for unambiguous parsing) ──
            // Use -b for byte counts, post-processed via awk to emit clean DISK lines
            "df -b --output=source,target,pcent,used,size" +
            " -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null" +
            " | tail -n +2" +
            " | awk '{gsub(/%/,\"\",$3); printf \"DISK:%s|%s|%s|%s|%s\\n\",$1,$2,$3,$4,$5}';" +
            // ── Battery ──
            "for b in /sys/class/power_supply/BAT* /sys/class/power_supply/bat*; do" +
            " [ -d \"$b\" ] || continue;" +
            " cap=$(cat \"$b/capacity\" 2>/dev/null);" +
            " sta=$(cat \"$b/status\" 2>/dev/null);" +
            " [ -n \"$cap\" ] && printf 'BAT:%s:%s\\n' \"$cap\" \"$sta\" && break;" +
            " done;" +
            // ── Network ──
            "awk 'NR>2{gsub(\":\",\" \",$1);if($1!=\"lo\"){rx+=$2;tx+=$10}}END{printf \"NET:%d:%d\\n\",rx,tx}' /proc/net/dev;" +
            // ── Uptime / Load (use printf to avoid awk quoting issues) ──
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
            smWin._parse(sysProc._buf.slice())
            sysProc._buf = []
        }
    }

    function _parse(lines) {
        let mi = {}
        let tempBest = 0, tempOk = false
        let gpus  = []
        let disks = []
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
                const name    = rawName
                    .replace(/Advanced Micro Devices[^,]*/i, "")
                    .replace(/AMD\s*/i, "")
                    .replace(/ATI(\s+Technologies\s+Inc\.?)?\s*/i, "")
                    .replace(/Intel(\s+Corporation)?\s*/i, "")
                    .replace(/\[|\]/g, "").trim().slice(0, 14) || drv.slice(0, 14) || "GPU"
                gpus.push({ name, pct, temp, type: drv, isIgpu })
                continue
            }

            // ── Disks (format: DISK:source|mount|pct|used_bytes|size_bytes) ──
            if (l.startsWith("DISK:")) {
                const inner = l.slice(5)
                const p     = inner.split("|")
                if (p.length < 5) continue
                disks.push({
                    device: p[0],
                    mount:  p[1],
                    pct:    parseInt(p[2]) || 0,
                    used:   _fmtDisk(parseInt(p[3])),
                    size:   _fmtDisk(parseInt(p[4]))
                })
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

            // ── Network ──
            if (l.startsWith("NET:")) {
                const p = l.split(":")
                const rx = parseInt(p[1]) || 0, tx = parseInt(p[2]) || 0
                const now = Date.now() / 1000
                if (_prevNet) {
                    const dt = Math.max(0.1, now - _prevNet.ts)
                    _rxRate = Math.max(0, (rx - _prevNet.rx) / dt)
                    _txRate = Math.max(0, (tx - _prevNet.tx) / dt)
                }
                _prevNet = { rx, tx, ts: now }
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

        // ── Disk filter ────────────────────────────────────────────────────
        // Internal: show /, /home, /boot* — deduplicated by device so btrfs
        // subvolumes sharing a device only appear once (canonical mount wins).
        const internalWanted = ["/", "/home", "/boot", "/boot/efi", "/boot/esp"]
        // External prefixes — anything mounted here is shown (removable/USB/etc)
        const extPfx = ["/media/", "/run/media/", "/mnt/"]
        const isExt  = m => extPfx.some(p => m.startsWith(p))

        // Build canonical-mount preference: '/' > '/home' > '/boot' > longer paths
        const mountPriority = m => {
            const idx = internalWanted.indexOf(m)
            return idx >= 0 ? idx : internalWanted.length
        }

        // Dedup internal by device — keep lowest-priority (most canonical) mount
        const internalByDev = {}
        for (const d of disks) {
            if (!internalWanted.includes(d.mount)) continue
            const existing = internalByDev[d.device]
            if (!existing || mountPriority(d.mount) < mountPriority(existing.mount))
                internalByDev[d.device] = d
        }
        // Sort by wanted order
        const internalResult = Object.values(internalByDev)
        internalResult.sort((a, b) => mountPriority(a.mount) - mountPriority(b.mount))

        // Dedup external by device — first seen wins
        const seenExtDev = {}
        const externalResult = []
        for (const d of disks) {
            if (!isExt(d.mount)) continue
            if (!seenExtDev[d.device]) {
                seenExtDev[d.device] = true
                externalResult.push(d)
            }
        }

        _disks = internalResult.concat(externalResult)

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
        running: true
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
                const onS = Theme.cOnSurf
                ctx.lineWidth = lw; ctx.lineCap = "round"
                ctx.beginPath(); ctx.arc(cx, cy, r, S, E)
                ctx.strokeStyle = Qt.rgba(onS.r, onS.g, onS.b, 0.12).toString()
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
            text: ag.sub; color: Theme.cOnSurfVar
            font.pixelSize: 9; font.family: Config.labelFont
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight; width: parent.width
        }
        Text {
            anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
            text: ag.label; color: Theme.cOnSurfVar
            font.pixelSize: 11; font.family: Config.labelFont
            horizontalAlignment: Text.AlignHCenter
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: smPanel
        // 5 × 88 + 4 × 8 + 2 × 16 = 504 px
        anchors { right: parent.right; rightMargin: smWin._panelMargin
                  top: parent.top; bottom: parent.bottom }
        width: 504

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

            // Header
            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "󰻠  System Monitor"; color: Theme.cOnSurf
                    font.pixelSize: 14; font.weight: Font.Medium; font.family: Config.fontFamily
                }
                Item { Layout.fillWidth: true }
                Rectangle {
                    width: 26; height: 26; radius: 99; color: "transparent"
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: SystemMonitorPopupState.close()
                        Text {
                            anchors.centerIn: parent; text: "󰅙"
                            color: parent.containsMouse ? Theme.cOnSurf : Theme.cOnSurfVar
                            font.pixelSize: 15; font.family: Config.fontFamily
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28) }

            // Gauge grid — Flow wraps at 5 per row (504 px panel, 88 px gauges, 8 px gaps)
            Flow {
                Layout.fillWidth: true; spacing: 8

                ArcGauge {
                    value:    smWin._cpu;  glyph: "󰻠"; label: "CPU"
                    valStr:   Math.round(smWin._cpu * 100) + "%"
                    arcColor: Theme.cPrimary
                }
                ArcGauge {
                    value:    smWin._ram;  glyph: "󰍛"; label: "RAM"
                    valStr:   Math.round(smWin._ram * 100) + "%"
                    sub:      smWin._fmtBytes(smWin._ramUsed)
                    arcColor: Theme.cSecondary
                }
                ArcGauge {
                    value:    smWin._tempOk ? Math.min(smWin._temp / 100, 1) : 0
                    glyph:    "󰔏"; label: "Temp"
                    valStr:   smWin._tempOk ? Math.round(smWin._temp) + "°" : "N/A"
                    arcColor: smWin._tempOk && smWin._temp > 80 ? Qt.rgba(1.0, 0.4, 0.2, 1) : Theme.cPrimaryFixedDim
                }
                ArcGauge {
                    visible:  smWin._swapOk
                    value:    smWin._swap; glyph: "󰾴"; label: "Swap"
                    valStr:   Math.round(smWin._swap * 100) + "%"
                    sub:      smWin._swapOk ? smWin._fmtBytes(smWin._swapUsed) : ""
                    arcColor: Theme.cSecondaryContainer
                }

                // GPUs — all detected GPUs shown (iGPU and dGPU both visible)
                Repeater {
                    model: smWin._gpus
                    delegate: ArcGauge {
                        required property var modelData
                        value:    modelData.pct / 100
                        glyph:    modelData.isIgpu ? "󰟽" : "󰢮"
                        label:    (modelData.isIgpu ? "iGPU" : "dGPU") + (smWin._gpus.length > 1 ? "" : "")
                        valStr:   modelData.pct + "%"
                        sub:      (modelData.temp > 0 ? modelData.temp + "°  " : "") + modelData.name.slice(0, 8)
                        arcColor: modelData.isIgpu ? Theme.cTertiaryContainer : Theme.cTertiary
                    }
                }

                // Battery — laptops only; hidden on desktops
                ArcGauge {
                    visible:  smWin._hasBat
                    value:    smWin._batPct / 100
                    glyph:    smWin._batPct > 80 ? "󰁹" : smWin._batPct > 60 ? "󰂀"
                              : smWin._batPct > 40 ? "󰁾" : smWin._batPct > 20 ? "󰁼" : "󰁺"
                    label:    smWin._batStatus === "Full"      ? "Battery ✓"
                              : smWin._batStatus === "Charging" ? "Battery ⚡" : "Battery"
                    valStr:   smWin._batPct + "%"
                    sub:      smWin._batStatus
                    arcColor: smWin._batPct <= 20 ? Qt.rgba(1.0, 0.3, 0.3, 1)
                              : smWin._batStatus === "Charging" ? Qt.rgba(0.3, 0.9, 0.5, 1)
                              : Theme.cPrimary
                }

                // Disks — internal (/,/home,/boot*) + external (/media,/run/media,/mnt)
                // Btrfs subvolumes are deduplicated by block device at parse time.
                Repeater {
                    model: smWin._disks
                    delegate: ArcGauge {
                        required property var modelData
                        value:    modelData.pct / 100
                        glyph:    "󰋊"
                        label:    modelData.mount === "/"         ? "root"
                                  : modelData.mount === "/home"     ? "home"
                                  : modelData.mount === "/boot"     ? "boot"
                                  : modelData.mount === "/boot/efi" ? "efi"
                                  : modelData.mount === "/boot/esp" ? "esp"
                                  : modelData.mount.split("/").pop() || modelData.mount
                        valStr:   modelData.pct + "%"
                        sub:      modelData.used + "/" + modelData.size
                        arcColor: modelData.pct >= 90 ? Qt.rgba(1.0, 0.3, 0.3, 1)
                                  : modelData.pct >= 75 ? Qt.rgba(1.0, 0.7, 0.2, 1)
                                  : Theme.cSecondary
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28) }

            // Footer — network rates, uptime, load average
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                Column {
                    spacing: 4
                    Row { spacing: 6
                        Text { text: "󰁅"; color: Theme.cPrimary; font.pixelSize: 12; font.family: Config.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: smWin._fmtRate(smWin._rxRate); color: Theme.cOnSurf; font.pixelSize: 11; font.family: Config.labelFont }
                    }
                    Row { spacing: 6
                        Text { text: "󰁝"; color: Theme.cPrimary; font.pixelSize: 12; font.family: Config.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: smWin._fmtRate(smWin._txRate); color: Theme.cOnSurf; font.pixelSize: 11; font.family: Config.labelFont }
                    }
                }
                Item { Layout.fillWidth: true }
                Column {
                    spacing: 4
                    Row { spacing: 6; anchors.right: parent.right
                        Text { text: "󰅐"; color: Theme.cPrimary; font.pixelSize: 12; font.family: Config.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Up: " + smWin._uptime; color: Theme.cOnSurf; font.pixelSize: 11; font.family: Config.labelFont }
                    }
                    Row { spacing: 6; anchors.right: parent.right
                        Text { text: "󰒋"; color: Theme.cPrimary; font.pixelSize: 12; font.family: Config.fontFamily; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: "Load: " + smWin._load; color: Theme.cOnSurf; font.pixelSize: 11; font.family: Config.labelFont }
                    }
                }
            }

            Item { height: 0 }
        }
    }
}
