pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

QtObject {
    id: root
    property bool visible: false
    property bool widgetVisible: false
    property int widgetX: Quickshell.screens[0] ? Math.round((Quickshell.screens[0].width - 244) / 2) : 674
    property int widgetY: Quickshell.screens[0] ? (Quickshell.screens[0].height - 380) / 2 : 350

    function toggle() { root.visible = !root.visible }
    function open()   { root.visible = true  }
    function close()  { root.visible = false }

    function toggleWidget() { root.widgetVisible = !root.widgetVisible }
    function closeWidget()  { root.widgetVisible = false }

    // ── NPU Listing Support ───────────────────────────────────────────────
    property var npus: []
    readonly property bool hasNpu: npus.length > 0

    readonly property var _npuScanProc: Process {
        id: npuScanProc
        property var _buf: []
        command: ["bash", "-c",
            "for dev in /sys/class/accel/accel*; do " +
            "  [ -d \"$dev\" ] || continue; " +
            "  pci=$(cat \"$dev/device/address\" 2>/dev/null); " +
            "  name=\"\"; " +
            "  [ -n \"$pci\" ] && name=$(lspci -D -s \"$pci\" 2>/dev/null | sed 's/.*: //'); " +
            "  [ -z \"$name\" ] && name=$(cat \"$dev/device/product_name\" 2>/dev/null); " +
            "  drv=$(readlink -f \"$dev/device/driver\" 2>/dev/null | grep -oE '[^/]+$'); " +
            "  [ -z \"$name\" ] && name=${drv:-NPU}; " +
            "  busy=$(cat \"$dev/device/busy_percent\" \"$dev/device/npu_busy_percent\" 2>/dev/null | head -1); " +
            "  [ -z \"$busy\" ] && busy=0; " +
            "  printf 'NPU:%s§%s§%s\\n' \"$drv\" \"$name\" \"$busy\"; " +
            "done; " +
            "lspci -D -d ::1200 2>/dev/null | while read -r line; do " +
            "  pci=$(echo \"$line\" | awk '{print $1}'); " +
            "  pname=$(echo \"$line\" | sed 's/.*: //'); " +
            "  printf 'PCI_NPU:%s§%s§0\\n' \"$pci\" \"$pname\"; " +
            "done; " +
            "lspci -D 2>/dev/null | grep -iE 'VPU|NPU|AI Boost|Neural' | while read -r line; do " +
            "  pci=$(echo \"$line\" | awk '{print $1}'); " +
            "  pname=$(echo \"$line\" | sed 's/.*: //'); " +
            "  printf 'PCI_NPU:%s§%s§0\\n' \"$pci\" \"$pname\"; " +
            "done;"
        ]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { if (l.trim() !== "") npuScanProc._buf.push(l.trim()) }
        }
        onRunningChanged: if (running) _buf = []
        onExited: {
            let found = []
            let seen = {}
            for (const l of npuScanProc._buf) {
                if (l.startsWith("NPU:")) {
                    const parts = l.slice(4).split("§")
                    const drv  = parts[0] || "NPU"
                    const name = parts[1] || drv
                    const pct  = parseInt(parts[2]) || 0
                    if (!seen[name]) {
                        seen[name] = true
                        found.push({ name: name.trim().slice(0, 14), driver: drv, pct: Math.max(0, Math.min(100, pct)) })
                    }
                } else if (l.startsWith("PCI_NPU:")) {
                    const parts = l.slice(8).split("§")
                    const pci  = parts[0]
                    const name = parts[1] || "NPU"
                    if (!seen[name] && !seen[pci]) {
                        seen[name] = true
                        seen[pci] = true
                        found.push({ name: name.replace(/Intel\s+Corporation\s*/i, "").replace(/Advanced Micro Devices[^,]*,?\s*/i, "").trim().slice(0, 14), driver: "pci", pct: 0 })
                    }
                }
            }
            root.npus = found
            npuScanProc._buf = []
        }
    }

    readonly property var _pollTimer: Timer {
        interval: 3000
        repeat: true
        running: root.visible || root.widgetVisible
        triggeredOnStart: true
        onTriggered: if (!npuScanProc.running) npuScanProc.running = true
    }
}
