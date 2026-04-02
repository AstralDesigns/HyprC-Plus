pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // ── Matugen colors ────────────────────────────────────────────────────────
    property string _m3primary:              "#f7c382"
    property string _m3onPrimary:            "#1d1100"
    property string _m3onSecondary:          "#100a00"
    property string _m3background:           "#100a00"
    property string _m3surfaceContainerHigh: "#1b1611"
    property string _m3surfaceContainer:     "#18120e"
    property string _m3onSurface:            "#f1e1d2"
    property string _m3onSurfaceVariant:     "#d1bca6"
    property string _m3outlineVariant:       "#5f5242"
    property string _m3inversePrimary:       "#69361d"
    property string _m3error:               "#ffb4ab"

    readonly property color cPrimary:      Qt.color(_m3primary)
    readonly property color cOnPrim:       Qt.color(_m3onPrimary)
    readonly property color cSurfHi:       Qt.color(_m3surfaceContainerHigh)
    readonly property color cSurfMid:      Qt.color(_m3surfaceContainer)
    readonly property color cOnSurf:       Qt.color(_m3onSurface)
    readonly property color cOnSurfVar:    Qt.color(_m3onSurfaceVariant)
    readonly property color cOutVar:       Qt.color(_m3outlineVariant)
    readonly property color cInvPrimary:   Qt.color(_m3inversePrimary)
    readonly property color cErr:          Qt.color(_m3error)
    // Panel background: onSecondary @ 0.4 alpha (same as wallpaper picker)
    readonly property color cPanelBg: Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g, Qt.color(_m3onSecondary).b, 0.4)

    function parseColors(t) {
        const re=/property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while((m=re.exec(t))!==null) switch(m[1]) {
            case "m3primary":             root._m3primary=m[2]; break
            case "m3onPrimary":           root._m3onPrimary=m[2]; break
            case "m3onSecondary":         root._m3onSecondary=m[2]; break
            case "m3background":          root._m3background=m[2]; break
            case "m3surfaceContainerHigh":root._m3surfaceContainerHigh=m[2]; break
            case "m3surfaceContainer":    root._m3surfaceContainer=m[2]; break
            case "m3onSurface":           root._m3onSurface=m[2]; break
            case "m3onSurfaceVariant":    root._m3onSurfaceVariant=m[2]; break
            case "m3outlineVariant":      root._m3outlineVariant=m[2]; break
            case "m3inversePrimary":      root._m3inversePrimary=m[2]; break
            case "m3error":               root._m3error=m[2]; break
        }
    }
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME")||(Quickshell.env("HOME")+"/.cache"))+"/quickshell/wallpaper/MatugenColors.qml"
        watchChanges:true; onFileChanged:reload(); onLoaded:root.parseColors(text())
    }

    // ── Visibility state + waybar position tracking ────────────────────────────
    property bool menuVisible: false
    property bool waybarAtBottom: false
    property real waybarSideMargin: 12
    property real waybarOuterRadius: 20
    FileView {
        path: Quickshell.env("HOME")+"/.config/hyprcandy/waybar-position.txt"
        watchChanges: true; onFileChanged: reload()
        onLoaded: root.waybarAtBottom = text().trim() === "bottom"
    }
    FileView {
        path: Quickshell.env("HOME")+"/.config/hyprcandy/waybar_side_margin.state"
        watchChanges: true; onFileChanged: reload()
        onLoaded: { const v=parseFloat(text().trim()); if(!isNaN(v)&&v>=0) root.waybarSideMargin=v }
    }
    FileView {
        path: Quickshell.env("HOME")+"/.config/hyprcandy/waybar_outer_radius.state"
        watchChanges: true; onFileChanged: reload()
        onLoaded: { const v=parseFloat(text().trim()); if(!isNaN(v)&&v>=0) root.waybarOuterRadius=v }
    }

    IpcHandler { target: "startmenu"
        function toggle() { root.menuVisible = !root.menuVisible }
        function open()   { root.menuVisible = true }
        function close()  { root.menuVisible = false }
    }

    // Re-sync volume from pactl every time the menu opens so the slider
    // always reflects the current system level regardless of what other
    // volume handlers (waybar, keys, wpctl, etc.) may have changed it.
    Connections {
        target: root
        function onMenuVisibleChanged() {
            if (root.menuVisible && !volReadProc.running)
                volReadProc.running = true
        }
    }

    // ── Brightness ───────────────────────────────────────────────────────────
    // brightnessctl -m → name,subsystem,max,current%,current_raw
    // e.g. intel_backlight,backlight,4882,100%,4882
    // p[3] is "100%" so strip % and divide by 100 for 0..1
    property real backlightValue: 1.0; property real backlightMax: 100
    Process { id: blReadProc
        command:["brightnessctl","-m"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){
            const p=l.split(",")
            if(p.length>=4){
                root.backlightMax=parseFloat(p[2])||100
                root.backlightValue=parseFloat(p[3].replace("%",""))/100
            }
        }}
        Component.onCompleted: running=true
    }
    Process { id: blSetProc; property string _val:""; property string _queued:""
        command:["brightnessctl","s",blSetProc._val]
        onExited: { if(_queued!==""){ _val=_queued; _queued=""; running=true } }
    }
    function setBacklight(v){ const n=String(Math.round(v*root.backlightMax)); if(blSetProc.running){ blSetProc._queued=n } else { blSetProc._val=n; blSetProc.running=true } }

    // ── Volume ────────────────────────────────────────────────────────────────
    property real volumeValue: 0.5; property bool volumeMuted: false
    Process { id: volReadProc; property var _b:[]
        command:["bash","-c","pactl get-sink-volume @DEFAULT_SINK@ && pactl get-sink-mute @DEFAULT_SINK@"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){ const vm=l.match(/(\d+)%/); if(vm) root.volumeValue=parseInt(vm[1])/100; if(l.includes("Mute:")) root.volumeMuted=l.includes("yes") } }
        onRunningChanged: if(running) _b=[]
    }
    Process { id: volSetProc; property string _cmd:""; property string _queued:""
        command:["bash","-c",volSetProc._cmd]
        onExited: { if(_queued!==""){ _cmd=_queued; _queued=""; running=true } else muteRefreshTimer.restart() }
    }
    function setVolume(v){ const c="pactl set-sink-volume @DEFAULT_SINK@ "+Math.round(v*100)+"%"; if(volSetProc.running){ volSetProc._queued=c } else { volSetProc._cmd=c; volSetProc.running=true } }
    function toggleMute(){ const c="pactl set-sink-mute @DEFAULT_SINK@ toggle"; if(volSetProc.running){ volSetProc._queued=c } else { volSetProc._cmd=c; volSetProc.running=true; muteRefreshTimer.restart() } }
    Timer { id:muteRefreshTimer; interval:350; repeat:false; onTriggered: if(!volReadProc.running) volReadProc.running=true }
    Timer { interval:250; running:true; repeat:false; onTriggered: if(!volReadProc.running) volReadProc.running=true }

    // ── Clock tick — re-evaluates the date/time binding every 10s ────────
    property date _now: new Date()
    Timer { interval:10000; repeat:true; running:true; onTriggered: root._now = new Date() }

    // ── Network ────────────────────────────────────────────────────────────────
    property bool networkExpanded: false
    property var networkList: []
    property string networkStatus: ""; property string networkSSID: ""
    property bool netConnecting_: false
    property string netConnectTarget: ""; property bool netPasswordVisible: false

    // Use --escape no so colons in SSIDs don't break parsing; awk splits on first 3 colons only
    Process { id: netStatusProc
        command:["bash","-c","nmcli --escape no -t -f DEVICE,STATE,CONNECTION dev | awk -F: 'NR==1||/wlan|wifi|wlp/{print;exit}'"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){
            const idx1=l.indexOf(":"), idx2=l.indexOf(":",idx1+1)
            if(idx1>0&&idx2>0){
                root.networkStatus=l.substring(idx1+1,idx2)
                root.networkSSID=l.substring(idx2+1)
            }
        }}
        Component.onCompleted: running=true
    }
    Timer { interval:8000; repeat:true; running:true; onTriggered: if(!netStatusProc.running) netStatusProc.running=true }

    property var _netBuf: []
    property var _savedNets: []   // SSIDs with saved NM profiles
    Process { id: netSavedProc
        command: ["bash", "-c", "nmcli --escape no -t -f NAME con show 2>/dev/null"]
        running: true
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            const n = l.trim(); if (n) root._savedNets.push(n)
        }}
        onRunningChanged: if (running) root._savedNets = []
    }
    Process { id: netScanProc
        // --escape no prevents colons in SSIDs from corrupting fields; SSID is last field
        command:["bash","-c","nmcli --escape no -t -f IN-USE,SECURITY,SIGNAL,SSID dev wifi list 2>/dev/null | head -25"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){
            // fields: IN-USE:SECURITY:SIGNAL:SSID  (SSID may contain colons)
            const c1=l.indexOf(":"), c2=l.indexOf(":",c1+1), c3=l.indexOf(":",c2+1)
            if(c3<0) return
            const inuse=l.substring(0,c1)
            const sec=l.substring(c1+1,c2)
            const sig=l.substring(c2+1,c3)
            const ssid=l.substring(c3+1)
            const saved = root._savedNets.indexOf(ssid) >= 0
            if(ssid) root._netBuf.push({active:inuse==="*",secure:sec!=="",signal:parseInt(sig)||0,ssid:ssid,saved:saved})
        }}
        onRunningChanged: if(running) { root._netBuf=[] } else { root.networkList=root._netBuf.slice() }
    }
    Process { id: netConnProc; property string _cmd:""; property string _lastSSID:"";
        command:["bash","-c",netConnProc._cmd]
        onExited: function(code) {
            root.netConnecting_=false
            if (code === 0) { root.netConnectedSSID = netConnProc._lastSSID; netConnFeedbackTimer.restart() }
            if(!netStatusProc.running) netStatusProc.running=true
        }
    }
    Timer { id: netConnFeedbackTimer; interval: 2500; repeat: false
        onTriggered: root.netConnectedSSID = "" }
    function connectNetwork(ssid, password){
        const esc=ssid.replace(/'/g,"'\\''")
        if(password) netConnProc._cmd="nmcli device wifi connect '"+esc+"' password '"+password.replace(/'/g,"'\\''")+"'"
        else netConnProc._cmd="nmcli connection up '"+esc+"' 2>/dev/null || nmcli device wifi connect '"+esc+"'"
        root.netConnecting_=true; root.netConnectTarget=ssid; netConnProc._lastSSID=ssid
        if(!netConnProc.running) netConnProc.running=true
    }

    // ── Bluetooth ─────────────────────────────────────────────────────────────
    // All pairing/connection state is persisted by BlueZ in /var/lib/bluetooth.
    // "Forget" = bluetoothctl remove <MAC>, which is the only way to un-remember.
    property bool   btExpanded:    false
    property bool   btPowered:     false
    property bool   btScanning:    false
    property var    btDevices:     []      // [{mac, name, connected}]
    property string btConnecting:  ""     // MAC currently being connected/disconnected
    property string btExpandedMac: ""     // MAC whose options panel is open
    property var    btActiveProfile: ({}) // mac → active PulseAudio profile string
    property var    btHasAudioCard:  ({}) // mac → bool: device has a bluez PulseAudio card
    property string btConnectedMac: ""   // MAC that just succeeded — shows ✓ briefly
    property string netConnectedSSID: "" // SSID that just succeeded — shows ✓ briefly

    // ── Trust state ───────────────────────────────────────────────────────────
    // Persisted per-MAC in ~/.config/hyprcandy/bt-trust/<MAC>.trust
    // Watches (phone, computer) get auto-trusted on first connect.
    // All other non-audio devices default to untrusted and show a toggle.
    property var btTrusted: ({})   // mac → bool

    property string _btTrustDir: Quickshell.env("HOME") + "/.config/hyprcandy/bt-trust"

    function _btTrustFile(mac) {
        return root._btTrustDir + "/" + mac.replace(/:/g, "_") + ".trust"
    }
    function btIsTrusted(mac) {
        return root.btTrusted[mac] === true
    }
    function btIsAutoTrust(mac) {
        // Audio, watches, phones/tablets, computers/laptops auto-trusted on first connect.
        // Printers get the trust toggle (require explicit user trust).
        // Gamepads, keyboards, mice: no trust concept — not file-capable.
        const dev = root.btDevices.find(function(d) { return d.mac === mac })
        if (!dev) return false
        const ic = (dev.icon || "").toLowerCase()
        return ic === "audio-headset"        || ic === "audio-headset-gateway" ||
               ic === "audio-headphones"     || ic === "audio-card"            ||
               ic.includes("speaker")        ||
               ic === "phone"                || ic === "computer"              ||
               ic.includes("watch")          || ic.includes("wearable")
    }
    function btLoadTrust(mac) {
        // Check trust file
        const f = root._btTrustFile(mac)
        try {
            const [ok, c] = [false, ""] // placeholder — read via Process below
        } catch(e) {}
        return false
    }

    // ── Status poll: power state + paired/connected device list ──────────────
    Process { id: btStatusProc
        property var _buf: []
        command: ["bash", "-c",
            "POWERED=$(bluetoothctl show 2>/dev/null | grep 'Powered:' | awk '{print $2}'); " +
            "DISC=$(bluetoothctl show 2>/dev/null | grep 'Discoverable:' | awk '{print $2}'); " +
            "echo \"POWERED:$POWERED\"; " +
            "echo \"DISCOVERABLE:$DISC\"; " +
            "ALL=$(bluetoothctl devices 2>/dev/null); " +
            "CONN=$(bluetoothctl devices Connected 2>/dev/null); " +
            "echo \"$ALL\" | while read -r line; do " +
            "  mac=$(echo \"$line\" | awk '{print $2}'); " +
            "  [ -z \"$mac\" ] && continue; " +
            "  name=$(echo \"$line\" | cut -d' ' -f3-); " +
            "  [ -z \"$name\" ] && name=$mac; " +
            "  if echo \"$CONN\" | grep -q \"$mac\"; then c=1; else c=0; fi; " +
            "  cls=$(bluetoothctl info \"$mac\" 2>/dev/null | grep 'Class:' | awk '{print $2}'); " +
            "  ico=$(bluetoothctl info \"$mac\" 2>/dev/null | grep 'Icon:' | awk '{print $2}'); " +
            "  echo \"DEV:$mac|$name|$c|$ico\"; " +
            "done"
        ]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (l.startsWith("POWERED:"))
                root.btPowered = l.slice(8).trim() === "yes"
            else if (l.startsWith("DISCOVERABLE:"))
                root.btDiscoverable = l.slice(13).trim() === "yes"
            else if (l.startsWith("DEV:")) {
                const p = l.slice(4).split("|")
                if (p.length >= 3)
                    btStatusProc._buf.push({ mac:p[0], name:p[1]||p[0], connected:p[2]==="1", icon:p[3]||"" })
            }
        }}
        onRunningChanged: if (running) _buf = []
        onExited: {
            root.btDevices = _buf.slice()
            // Load trust state for all devices
            btTrustReadProc._macs = root.btDevices.map(function(d) { return d.mac })
            if (!btTrustReadProc.running) btTrustReadProc.running = true
            // Auto-trust audio + watch/phone/computer devices on first see
            root.btDevices.forEach(function(d) {
                if (root.btIsAutoTrust(d.mac) && root.btTrusted[d.mac] === undefined) {
                    root.btSetTrust(d.mac, true)
                }
            })
            // Auto-reconnect once at startup — fires regardless of menu visibility
            // since btStatusProc.Component.onCompleted starts the first poll.
            if (!btStatusProc._autoReconnectDone && root.btPowered) {
                btStatusProc._autoReconnectDone = true
                const disconnected = root.btDevices.filter(function(x) { return !x.connected })
                if (disconnected.length > 0) {
                    btAutoReconnProc._macs = disconnected.map(function(x) { return x.mac })
                    if (!btAutoReconnProc.running) btAutoReconnProc.running = true
                }
            }
        }
        property bool _autoReconnectDone: false
        Component.onCompleted: running = true
    }
    // Reconnects all previously-paired-but-disconnected devices once at startup.
    // Runs regardless of menu visibility — fires after first btStatusProc poll.
    Process { id: btAutoReconnProc; property var _macs: []
        command: ["bash", "-c",
            "for mac in " + btAutoReconnProc._macs.join(" ") + "; do " +
            "  bluetoothctl connect $mac 2>/dev/null; sleep 1; " +
            "done"]
        onExited: { if (!btStatusProc.running) btStatusProc.running = true }
    }

    // ── Trust management ──────────────────────────────────────────────────────
    // Reads trust files for all known devices once per status poll.
    // Trust state is a simple presence check: file exists = trusted.
    Process { id: btTrustReadProc; property var _macs: []
        command: ["bash", "-c",
            "mkdir -p '" + root._btTrustDir + "'; " +
            "for mac in " + btTrustReadProc._macs.join(" ") + "; do " +
            "  f='" + root._btTrustDir + "/'$(echo $mac | tr ':' '_')'.trust'; " +
            "  [ -f \"$f\" ] && echo \"TRUSTED:$mac\" || echo \"UNTRUSTED:$mac\"; " +
            "done"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (l.startsWith("TRUSTED:")) {
                const mac = l.slice(8).trim()
                const o = Object.assign({}, root.btTrusted); o[mac] = true; root.btTrusted = o
            } else if (l.startsWith("UNTRUSTED:")) {
                const mac = l.slice(10).trim()
                const o = Object.assign({}, root.btTrusted); o[mac] = false; root.btTrusted = o
            }
        }}
    }

    Process { id: btTrustSetProc; property string _cmd: ""
        command: ["bash", "-c", btTrustSetProc._cmd]
        onExited: {
            // Re-read trust state after change
            btTrustReadProc._macs = root.btDevices.map(function(d) { return d.mac })
            if (!btTrustReadProc.running) btTrustReadProc.running = true
        }
    }
    function btSetTrust(mac, trusted) {
        const f = "'" + root._btTrustDir + "/'$(echo " + mac + " | tr ':' '_')'.trust'"
        if (trusted) {
            btTrustSetProc._cmd =
                "mkdir -p '" + root._btTrustDir + "' && touch " + f + " && " +
                "bluetoothctl trust " + mac + " 2>/dev/null"
        } else {
            btTrustSetProc._cmd =
                "rm -f " + f + " && bluetoothctl untrust " + mac + " 2>/dev/null"
        }
        if (!btTrustSetProc.running) btTrustSetProc.running = true
    }
    Timer { interval: 8000; repeat: true; running: true;
        onTriggered: if (!btStatusProc.running) btStatusProc.running = true }

    // ── Power toggle ─────────────────────────────────────────────────────────
    Process { id: btPowerProc; property string _cmd: ""
        command: ["bash", "-c", btPowerProc._cmd]
        onExited: { if (!btStatusProc.running) btStatusProc.running = true }
    }
    function toggleBtPower() {
        btPowerProc._cmd = root.btPowered ? "bluetoothctl power off" : "bluetoothctl power on"
        if (!btPowerProc.running) btPowerProc.running = true
    }
    function toggleBtDiscoverable() {
        btPowerProc._cmd = root.btDiscoverable
            ? "bluetoothctl discoverable off"
            : "bluetoothctl discoverable on && bluetoothctl pairable on"
        if (!btPowerProc.running) btPowerProc.running = true
    }
    function btRepair(mac) {
        // Remove stale pairing data then reconnect — fixes "wrong PIN" after failed pair
        root.btConnecting = mac; btConnProc._lastMac = mac
        btConnProc._cmd = "bluetoothctl remove " + mac + " 2>/dev/null; sleep 0.5; bluetoothctl pair " + mac
        if (!btConnProc.running) btConnProc.running = true
    }

    // ── Discovery scan (20-second timeout, live refresh every 3s while scanning)
    Process { id: btScanProc
        command: ["bash", "-c",
            "bluetoothctl --timeout 20 scan on 2>/dev/null; " +
            "bluetoothctl scan off 2>/dev/null"
        ]
        onExited: {
            root.btScanning = false
            btScanLiveTimer.stop()
            if (!btStatusProc.running) btStatusProc.running = true
        }
    }
    // Fires every 3s during an active scan to pull newly discovered devices into the list
    Timer { id: btScanLiveTimer; interval: 3000; repeat: true
        onTriggered: if (!btStatusProc.running) btStatusProc.running = true }
    function toggleBtScan() {
        if (root.btScanning) {
            root.btScanning = false
            btScanLiveTimer.stop()
            if (btScanProc.running) btScanProc.running = false
            if (!btStatusProc.running) btStatusProc.running = true
        } else {
            root.btScanning = true
            if (!btScanProc.running) btScanProc.running = true
            btScanLiveTimer.restart()
        }
    }

    // ── Connect / disconnect / forget ─────────────────────────────────────────
    Process { id: btConnProc; property string _cmd: ""; property string _lastMac: ""; property string _capturedPct: ""
        command: ["bash", "-c", btConnProc._cmd]
        onExited: function(code) {
            root.btConnecting = ""
            if (code === 0) {
                root.btConnectedMac = btConnProc._lastMac
                btConnFeedbackTimer.restart()
                // Restore the volume that was active before the connect.
                // _capturedPct was snapshot in btConnect() before the process started.
                root.btSetSinkVolume(btConnProc._lastMac, btConnProc._capturedPct)
            }
            if (!btStatusProc.running) btStatusProc.running = true
        }
    }
    Timer { id: btConnFeedbackTimer; interval: 2500; repeat: false
        onTriggered: root.btConnectedMac = "" }
    // ── BT volume preservation ────────────────────────────────────────────────
    // Earphones implement A2DP Absolute Volume: after the profile negotiates they
    // advertise their hardware level (often 100%) back to PipeWire, overwriting
    // whatever pactl set a moment before.  The fix is a three-shot retry loop:
    //   shot 1 — immediate, catches the initial 100% default on sink creation
    //   shot 2 — +800 ms, catches the late A2DP re-sync after codec negotiation
    //   shot 3 — via @DEFAULT_SINK@ in case PipeWire remapped the default by then
    // capturedPct is snapshotted BEFORE any connect/switch so the slider value
    // at the time of the action is preserved, not whatever it drifts to afterward.
    Process { id: btSinkVolProc; property string _cmd: ""
        command: ["bash", "-c", btSinkVolProc._cmd]
        onExited: { if (!volReadProc.running) volReadProc.running = true }
    }
    function btSetSinkVolume(mac, capturedPct) {
        const macFrag = mac.replace(/:/g, "_").toLowerCase()
        const pct = capturedPct || (Math.round(root.volumeValue * 100) + "%")
        btSinkVolProc._cmd =
            "PCT='" + pct + "'; FRAG='" + macFrag + "'; " +
            // Wait up to 6 s for the BT sink to appear in pactl
            "for i in $(seq 1 12); do " +
            "  SINK=$(pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -i \"$FRAG\" | head -1); " +
            "  [ -n \"$SINK\" ] && break; sleep 0.5; " +
            "done; " +
            "[ -z \"$SINK\" ] && exit 0; " +
            // Shot 1 — immediately after sink appears
            "pactl set-sink-volume \"$SINK\" \"$PCT\" 2>/dev/null; " +
            // Shot 2 — after A2DP codec negotiation settles (~800 ms later)
            "sleep 0.8; pactl set-sink-volume \"$SINK\" \"$PCT\" 2>/dev/null; " +
            // Shot 3 — via default alias in case PipeWire remapped it
            "pactl set-sink-volume @DEFAULT_SINK@ \"$PCT\" 2>/dev/null; true"
        if (!btSinkVolProc.running) btSinkVolProc.running = true
    }

    // "Set Default" — capture volume NOW (before the switch can disturb it),
    // then restore after the sink switch completes.
    Process { id: btDefaultSinkProc; property string _cmd: ""
                                     property string _capturedPct: ""
                                     property string _mac: ""
        command: ["bash", "-c", btDefaultSinkProc._cmd]
        onExited: {
            if (_mac !== "") root.btSetSinkVolume(_mac, _capturedPct)
            if (!volReadProc.running) volReadProc.running = true
        }
    }
    function btSetDefaultSink(mac) {
        const macFrag = mac.replace(/:/g, "_").toLowerCase()
        // Snapshot NOW before any sink switch can change the level
        btDefaultSinkProc._capturedPct = Math.round(root.volumeValue * 100) + "%"
        btDefaultSinkProc._mac = mac
        btDefaultSinkProc._cmd =
            "FRAG='" + macFrag + "'; " +
            "SINK=$(pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -i \"$FRAG\" | head -1); " +
            "[ -z \"$SINK\" ] && SINK=$(pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -i '" + mac.toLowerCase() + "' | head -1); " +
            "[ -z \"$SINK\" ] && { echo 'No BT sink found for " + mac + "' >&2; exit 1; }; " +
            "pactl set-default-sink \"$SINK\"; " +
            "pactl list short sink-inputs 2>/dev/null | awk '{print $1}' | " +
            "  xargs -r -I{} pactl move-sink-input {} \"$SINK\" 2>/dev/null; " +
            "command -v wpctl >/dev/null && wpctl set-default \"$SINK\" 2>/dev/null; true"
        if (!btDefaultSinkProc.running) btDefaultSinkProc.running = true
    }
    function btConnect(mac) {
        root.btConnecting = mac; btConnProc._lastMac = mac
        // Snapshot volume before connect so btSetSinkVolume can restore it
        btConnProc._capturedPct = Math.round(root.volumeValue * 100) + "%"
        btConnProc._cmd = "bluetoothctl connect " + mac
        if (!btConnProc.running) btConnProc.running = true
    }
    function btDisconnect(mac) {
        root.btConnecting = mac; btConnProc._lastMac = mac
        btConnProc._cmd = "bluetoothctl disconnect " + mac
        if (!btConnProc.running) btConnProc.running = true
    }
    function btForget(mac) {
        if (root.btExpandedMac === mac) root.btExpandedMac = ""
        btConnProc._cmd = "bluetoothctl remove " + mac
        if (!btConnProc.running) btConnProc.running = true
        // Auto-scan so the forgotten device can be rediscovered immediately
        if (!root.btScanning) root.toggleBtScan()
    }

    // ── Audio profile query (PipeWire-native) ────────────────────────────────
    // Card existence via pw-dump (always present with PipeWire, no pipewire-pulse needed).
    // Active profile via pactl compat layer (present when pipewire-pulse is installed,
    // which is standard on all major distros using PipeWire).
    Process { id: btProfileQueryProc; property string _mac: ""; property var _lines: []
        command: ["bash", "-c",
            "CARD=\"bluez_card.$(echo '" + btProfileQueryProc._mac + "' | tr ':' '_')\"; " +
            "pw-dump 2>/dev/null | grep -qF \"$CARD\" && echo CARD_EXISTS; " +
            "pactl list cards 2>/dev/null | awk \"/Name: $CARD/{f=1} f&&/Active Profile:/{print; f=0}\""
        ]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) { btProfileQueryProc._lines.push(l.trim()) }}
        onRunningChanged: if (running) _lines = []
        onExited: {
            const mac = btProfileQueryProc._mac
            const hasCard = btProfileQueryProc._lines.some(function(x) { return x === "CARD_EXISTS" })
            const h = Object.assign({}, root.btHasAudioCard)
            h[mac] = hasCard
            root.btHasAudioCard = h
            const line = _lines.find(function(x) { return x.startsWith("Active Profile:") })
            if (line) {
                const o = Object.assign({}, root.btActiveProfile)
                o[mac] = line.replace("Active Profile:", "").trim()
                root.btActiveProfile = o
            }
        }
    }
    function btQueryProfile(mac) {
        btProfileQueryProc._mac = mac
        if (!btProfileQueryProc.running) btProfileQueryProc.running = true
    }

    // ── Profile set (pactl set-card-profile) ─────────────────────────────────
    Process { id: btSetProfileProc; property string _cmd: ""
        command: ["bash", "-c", btSetProfileProc._cmd]
        onExited: if (!btProfileQueryProc.running) btProfileQueryProc.running = true
    }
    function btSetProfile(mac, profile) {
        const card = "bluez_card." + mac.replace(/:/g, "_")
        btSetProfileProc._cmd = "pactl set-card-profile " + card + " " + profile
        if (!btSetProfileProc.running) btSetProfileProc.running = true
    }

    // ── File send: zenity file picker → bluetooth-sendto ─────────────────────
    Process { id: btSendProc; property string _cmd: ""
        command: ["bash", "-c", btSendProc._cmd]
    }
    function btSendFile(mac) {
        const esc = mac.replace(/'/g, "'\\''")
        btSendProc._cmd =
            "FILE=$(zenity --file-selection --title='Send via Bluetooth' 2>/dev/null) && " +
            "[ -n \"$FILE\" ] && " +
            "bluetooth-sendto --device='" + esc + "' \"$FILE\" &"
        if (!btSendProc.running) btSendProc.running = true
    }

    // ── File receive: start/stop obexd auto-accept to ~/Downloads ─────────────
    property bool btReceiving: false
    property bool btDiscoverable: false
    Process { id: btObexProc; property string _cmd: ""
        command: ["bash", "-c", btObexProc._cmd]
        onExited: root.btReceiving = false
    }
    function toggleBtReceive() {
        if (root.btReceiving) {
            btObexProc._cmd = "pkill -f 'obexd.*auto-accept' 2>/dev/null; true"
            root.btReceiving = false
            if (!btObexProc.running) btObexProc.running = true
        } else {
            root.btReceiving = true
            btObexProc._cmd =
                "pkill -f 'obexd.*auto-accept' 2>/dev/null; " +
                "/usr/lib/bluetooth/obexd --root \"${HOME}/Downloads\" --auto-accept &"
            if (!btObexProc.running) btObexProc.running = true
        }
    }

    // ── Recorder ─────────────────────────────────────────────────────────────
    // ── Recorder ─────────────────────────────────────────────────────────
    // Saves to ~/Videos/Recordings/. On stop: waits for wf-recorder to flush,
    // then extracts a frame thumbnail (ffmpeg → ImageMagick fallback) and fires
    // notify-send -i <thumb> so the notification toast shows a preview.
    property bool isRecording: false
    property string _recFile: ""   // set when recording starts

    Process { id: recCheckProc
        command:["bash","-c","pgrep -x wf-recorder > /dev/null && echo 1 || echo 0"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){ root.isRecording=l.trim()==="1" } }
        Component.onCompleted: running=true
    }
    Timer { interval:3000; repeat:true; running:true
        onTriggered: if(!recCheckProc.running) recCheckProc.running=true }

    Process { id: recProc; property string _cmd:""; command:["bash","-c",recProc._cmd]
        onRunningChanged: if(!running) recStopRefreshTimer.restart()
    }
    Timer { id:recStopRefreshTimer; interval:500; repeat:false
        onTriggered: if(!recCheckProc.running) recCheckProc.running=true }

    // Runs the post-stop thumbnail + notification independently of recProc
    // so blocking on ffmpeg never stalls the main process.
    Process { id: recNotifyProc; property string _cmd:""
        command:["bash","-c",recNotifyProc._cmd] }

    function toggleRecorder(){
        if(root.isRecording){
            const savedFile = root._recFile
            root._recFile = ""
            recProc._cmd = "pkill -SIGINT wf-recorder"
            if(!recProc.running) recProc.running=true

            const sf = savedFile.replace(/'/g, "'\''")
            recNotifyProc._cmd =
                "sleep 2; " +
                "FILE='" + sf + "'; " +
                "[ -f \"$FILE\" ] || FILE=$(ls -t ~/Videos/Recordings/*.mp4 2>/dev/null | head -1); " +
                "[ -f \"$FILE\" ] || exit 0; " +
                "THUMB=/tmp/qs_rec_thumb.jpg; " +
                "ffmpeg -y -loglevel quiet -ss 00:00:01 -i \"$FILE\" -vframes 1 -q:v 3 \"$THUMB\" 2>/dev/null || " +
                "magick \"${FILE}[24]\" -resize '640x360>' \"$THUMB\" 2>/dev/null || " +
                "magick \"${FILE}[0]\"  -resize '640x360>' \"$THUMB\" 2>/dev/null || true; " +
                "BASE=$(basename \"$FILE\"); " +
                "if [ -f \"$THUMB\" ]; then " +
                "  notify-send -a Recorder -i \"$THUMB\" '\uf70b Recording Saved' \"$BASE\"; " +
                "else " +
                "  notify-send -a Recorder -i media-record '\uf70b Recording Saved' \"$BASE\"; " +
                "fi"
            if(!recNotifyProc.running) recNotifyProc.running=true
        } else {
            const home   = Quickshell.env("HOME")
            const folder = home + "/Videos/Recordings"
            const ts     = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")
            const dest   = folder + "/recording-" + ts + ".mp4"
            root._recFile = dest
            const sf2    = dest.replace(/'/g, "'\\''")
            const sfo    = folder.replace(/'/g, "'\\''")
            const s      = home + "/.config/hyprcandy/scripts/recorder.sh"
            const ss     = s.replace(/'/g, "'\\''")
            recProc._cmd =
                "mkdir -p '" + sfo + "'; " +
                "setsid -f bash -c \"[ -x '" + ss + "' ] && '" + ss + "' || " +
                "wf-recorder -f '" + sf2 + "'\" &>/dev/null &"
            if(!recProc.running) recProc.running=true
        }
    }

    // ── Screenshot — delegates to the rofi screenshot script ───────────────
    // Runs ~/.config/hypr/scripts/screenshot.sh via setsid -f so the rofi
    // menu opens independently and the startmenu can close immediately.
    Process { id: ssProc; command: ["setsid", "-f",
        Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh"] }
    function takeScreenshot(){
        root.menuVisible = false
        if (!ssProc.running) ssProc.running = true
    }
    Process { id: logoutProc; command:["bash","-c","hyprctl dispatch exit"] }
    Process { id: powerProc; property string _cmd:""; command:["bash","-c",powerProc._cmd] }

    // ── User icon — process on menu open + watch for changes ────────────────
    property string _userIconPath: ""
    property string _lastIconTime: "0"

    Process { id: smIconProc
        property string _dst: "/tmp/qs_sm_user_circle.png"
        property string _src: Quickshell.env("HOME")+"/.config/hyprcandy/user-icon.png"
        command:["bash","-c",
            "SRC='" + smIconProc._src + "'; DST='" + smIconProc._dst + "'; "+
            "[ -f \"$SRC\" ] || exit 1; "+
            "magick \"$SRC\" -resize 96x96^ -gravity center -extent 96x96 "+
            "  \\( +clone -alpha extract -fill black -colorize 100 "+
            "     -fill white -draw 'circle 48,48 48,0' \\) "+
            "  -alpha off -compose CopyOpacity -composite -strip \"$DST\""]
        onExited: function(code){
            if(code===0) root._userIconPath = smIconProc._dst+"?"+Date.now()
        }
    }

    // Watch user icon file for changes (same as CC sidebar)
    Timer {
        id: smIconWatchTimer
        interval: 1000; running: true; repeat: true
        onTriggered: {
            _smIconCheck.running = true
        }
    }

    Process { id: _smIconCheck
        command: ["bash", "-c",
            "SRC=\"$HOME/.config/hyprcandy/user-icon.png\"; "+
            "[ -f \"$SRC\" ] && stat -c %Y \"$SRC\" || echo 0"]
        onExited: function(code) {
            const newTime = _smIconCheck._stdout.trim()
            if (newTime && newTime !== "0" && newTime !== root._lastIconTime) {
                root._lastIconTime = newTime
                if (!smIconProc.running) smIconProc.running = true
            }
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { _smIconCheck._stdout = line.trim() }
        }
        property string _stdout: ""
    }

    // Process icon when menu opens
    Connections {
        target: root
        function onMenuVisibleChanged() {
            if (root.menuVisible && !smIconProc.running) {
                smIconProc.running = true
            }
        }
    }

    // ── Close on real-window focus ────────────────────────────────────────────
    //  HyprlandFocusedClient.address changes whenever Hyprland reports a newly
    //  focused *client* (a regular XDG toplevel window).  Layer shells — waybar,
    //  rofi, the dock, other quickshell panels — are NOT tracked as focused
    //  clients, so interacting with them leaves the menu open as intended.
    //  Only clicking into a real app window closes the menu.
    Connections {
        target: HyprlandFocusedClient
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "") {
                root.menuVisible = false
            }
        }
    }

    // ── Panel window ─────────────────────────────────────────────────────────
    PanelWindow {
        id: panel
        visible: root.menuVisible
        WlrLayershell.namespace: "quickshell:startmenu"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: !root.waybarAtBottom; bottom: root.waybarAtBottom; right: true }
        margins { top: 6; right: root.waybarSideMargin; bottom: 6 }
        width: 340
        height: mainCol.implicitHeight + 32
        color: "transparent"

        Rectangle {
            id: panelRect
            anchors.fill: parent
            color: root.cPanelBg
            radius: root.waybarOuterRadius
            focus: true
            border.width: 1; border.color: Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.40)
            scale: root.menuVisible ? 1.0 : 0.92
            transformOrigin: Item.TopRight
            Behavior on scale { NumberAnimation { duration:160; easing.type:Easing.OutCubic } }
            Keys.onEscapePressed: root.menuVisible = false
            Connections { target: root; function onMenuVisibleChanged() { if(root.menuVisible) panelRect.forceActiveFocus() } }

            ColumnLayout {
                id: mainCol
                anchors { top:parent.top; left:parent.left; right:parent.right; margins:16 }
                spacing: 10

                // ── Row 1: user + power ────────────────────────────────────
                RowLayout { Layout.fillWidth:true; spacing:8
                    // User avatar — circular PNG pre-rendered by ImageMagick
                    Rectangle { width:36;height:36;radius:18;color:root.cSurfHi
                        Image { id:smAvatar; anchors.fill:parent; fillMode:Image.PreserveAspectCrop; source:root._userIconPath?"file://"+root._userIconPath:""; smooth:true; mipmap:true; visible:root._userIconPath!=="" }
                        Text { anchors.centerIn:parent; visible:!smAvatar.visible; text:"󰀄"; font.pixelSize:20; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar }
                    }
                    ColumnLayout { Layout.fillWidth:true; spacing:1
                        Text { text:Quickshell.env("USER"); color:root.cOnSurf; font.pixelSize:13; font.weight:Font.Medium }
                        Text { text:Qt.formatDate(root._now,"ddd d MMM")+" · "+Qt.formatTime(root._now,"hh:mm"); color:root.cOnSurfVar; font.pixelSize:10 }
                    }
                    // Recorder + screenshot
                    Rectangle {
                        width:30;height:30;radius:15
                        color: root.isRecording
                            ? "transparent"
                            : rrh.containsMouse
                                ? Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.18)
                                : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                        border.width:1
                        border.color: root.isRecording
                            ? Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.85)
                            : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.55)
                        Behavior on color{ColorAnimation{duration:100}}

                        // Bold gradient fill while recording — visible in both light + dark themes
                        Rectangle {
                            anchors.fill:parent; radius:parent.radius
                            visible: root.isRecording
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position:0.0; color:Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.85) }
                                GradientStop { position:1.0; color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.70) }
                            }
                        }

                        Text { anchors.centerIn:parent; text:"󰑋"; font.pixelSize:15; font.family:"Symbols Nerd Font Mono"
                            color: root.isRecording ? root.cOnPrim : root.cOnSurfVar
                            Behavior on color{ColorAnimation{duration:100}}
                            SequentialAnimation on opacity { running:root.isRecording; loops:Animation.Infinite
                                NumberAnimation{to:0.3;duration:500}
                                NumberAnimation{to:1.0;duration:500}
                            }
                        }
                        MouseArea{id:rrh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.toggleRecorder()}
                    }
                    Rectangle {
                        width:30;height:30;radius:15
                        color:ssh.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18):Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                        border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.55)
                        Behavior on color{ColorAnimation{duration:100}}
                        Text { anchors.centerIn:parent; text:"󰹑"; font.pixelSize:15; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar }
                        MouseArea{id:ssh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.takeScreenshot()}
                    }
                    Rectangle {
                    height: 24; width: 45; radius: 8
                    color: clsH.containsMouse
                        ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.0)
                        : "transparent"
                    }
                    Rectangle {
                    height: 24; width: 24; radius: 8
                    color: clsH.containsMouse
                        ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.9)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    
                    Text { anchors.centerIn: parent; text: "×"
                        font.pixelSize: 12; color: root.cOnSurfVar }
                    MouseArea { id: clsH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.menuVisible = false }
                    }
                }

                Rectangle { Layout.fillWidth:true; height:1; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.25) }

                // ── Brightness ────────────────────────────────────────────
                RowLayout { Layout.fillWidth:true; spacing:10
                    Text { text:"󰃟"; font.pixelSize:17; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary }
                    Text { text:"Brightness"; color:root.cOnSurfVar; font.pixelSize:13; Layout.preferredWidth:72 }
                    SliderBg {
                        Layout.fillWidth:true; height:20
                        value:root.backlightValue
                        onMoved: function(v){ root.backlightValue=v; root.setBacklight(v) }
                        gradA:root.cInvPrimary; gradB:root.cOnPrim; track:root.cOutVar
                    }
                    Text { text:Math.round(root.backlightValue*100)+"%"; color:root.cOnSurfVar; font.pixelSize:11; Layout.preferredWidth:30; horizontalAlignment:Text.AlignRight }
                }

                // ── Volume ────────────────────────────────────────────────
                RowLayout { Layout.fillWidth:true; spacing:10
                    Text { text:root.volumeMuted?"󰖁":"󰕾"; font.pixelSize:17; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary
                        MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.toggleMute()}
                    }
                    Text { text:"Volume"; color:root.cOnSurfVar; font.pixelSize:13; Layout.preferredWidth:72 }
                    SliderBg {
                        Layout.fillWidth:true; height:20
                        value:root.volumeValue
                        onMoved: function(v){ root.volumeValue=v; root.setVolume(v) }
                        gradA:root.cInvPrimary; gradB:root.cOnPrim; track:root.cOutVar
                    }
                    Text { text:Math.round(root.volumeValue*100)+"%"; color:root.cOnSurfVar; font.pixelSize:11; Layout.preferredWidth:30; horizontalAlignment:Text.AlignRight }
                }

                Rectangle { Layout.fillWidth:true; height:1; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.25) }

                // ── Network + Bluetooth ────────────────────────────────────
                ColumnLayout { Layout.fillWidth:true; spacing:4
                    // ── Header row: wifi status | wifi expand | bt power | bt expand
                    RowLayout { Layout.fillWidth:true; spacing:8
                        Text { text:"󰤨"; font.pixelSize:15; font.family:"Symbols Nerd Font Mono"
                            color:root.networkStatus==="connected"?root.cPrimary:root.cOnSurfVar }
                        ColumnLayout { Layout.fillWidth:true; spacing:0
                            Text { text:root.networkSSID||"Not connected"; color:root.cOnSurf; font.pixelSize:12; elide:Text.ElideRight }
                            Text { text:root.networkStatus; color:root.cOnSurfVar; font.pixelSize:10; opacity:0.7; visible:root.networkStatus!=="" }
                        }
                        // Wifi expand button
                        Rectangle {
                            width:24;height:24;radius:6
                            color:nxh.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.15):"transparent"
                            border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.55)
                            Behavior on color{ColorAnimation{duration:100}}
                            Text { anchors.centerIn:parent; text:root.networkExpanded?"󰁆":"󰁄"; font.pixelSize:13; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary }
                            MouseArea{id:nxh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{
                                root.networkExpanded=!root.networkExpanded
                                if(root.networkExpanded) {
                                    if(!netSavedProc.running) netSavedProc.running=true
                                    if(!netScanProc.running) netScanProc.running=true
                                }
                            }}
                        }

                        // Thin divider between wifi and BT controls
                        Rectangle { width:1; height:20; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.4) }

                        // BT power icon — click toggles power
                        Text {
                            font.pixelSize:15; font.family:"Symbols Nerd Font Mono"
                            text: root.btPowered ? "󰂱" : "󰂲"
                            color: root.btPowered ? root.cPrimary : root.cOnSurfVar
                            Behavior on color{ColorAnimation{duration:150}}
                            MouseArea{anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:root.toggleBtPower()}
                        }
                        // BT expand button
                        Rectangle {
                            width:24;height:24;radius:6
                            color:bxh.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.15):"transparent"
                            border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.55)
                            Behavior on color{ColorAnimation{duration:100}}
                            Text { anchors.centerIn:parent; text:root.btExpanded?"󰁆":"󰁄"; font.pixelSize:13; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary }
                            MouseArea{id:bxh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{
                                root.btExpanded=!root.btExpanded
                                if(root.btExpanded){
                                    if(!btStatusProc.running) btStatusProc.running=true
                                }
                            }}
                        }
                    }

                    // ── Wifi network list (expanded) ─────────────────────────
                    Column {
                        visible:root.networkExpanded
                        Layout.fillWidth:true
                        width: parent.width
                        spacing:2

                        Repeater {
                            model: root.networkList
                            delegate: Column {
                                id: netDelegate
                                required property var modelData
                                property bool _showPass: false
                                width: parent.width
                                spacing:2

                                Rectangle {
                                    width:parent.width; height:34; radius:8
                                    color:nh.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.10):Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.5)
                                    Behavior on color{ColorAnimation{duration:100}}
                                    border.width:netDelegate.modelData.active?1:0; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.5)
                                    RowLayout { anchors.fill:parent; anchors.leftMargin:8; anchors.rightMargin:8; spacing:6
                                        Text { text:netDelegate.modelData.signal>70?"󰤨":netDelegate.modelData.signal>40?"󰤥":netDelegate.modelData.signal>20?"󰤢":"󰤟"; font.pixelSize:12; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar }
                                        Text { Layout.fillWidth:true; text:netDelegate.modelData.ssid; color:root.cOnSurf; font.pixelSize:11; elide:Text.ElideRight }
                                        Text { text:"󰒃"; font.pixelSize:10; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar; opacity:0.5; visible:netDelegate.modelData.secure }
                                        Text { text:root.netConnecting_&&root.netConnectTarget===netDelegate.modelData.ssid?"󰒖":""; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary; RotationAnimator on rotation{from:0;to:360;duration:800;loops:Animation.Infinite;running:root.netConnecting_&&root.netConnectTarget===netDelegate.modelData.ssid} }
                                        // Success checkmark
                                        Text { text:"󰄬"; font.pixelSize:12; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary
                                            visible: root.netConnectedSSID===netDelegate.modelData.ssid
                                            opacity: root.netConnectedSSID===netDelegate.modelData.ssid ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 400 } } }
                                    }
                                    MouseArea{id:nh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{
                                        if(netDelegate.modelData.active) return
                                        // If network is saved (previously connected), reconnect directly — no password prompt
                                        if(netDelegate.modelData.saved || !netDelegate.modelData.secure)
                                            root.connectNetwork(netDelegate.modelData.ssid,"")
                                        else
                                            netDelegate._showPass=!netDelegate._showPass
                                    }}
                                }

                                // Password entry (when secure + expanded)
                                Row { visible:netDelegate._showPass; width:parent.width; spacing:4
                                    Rectangle { width:parent.width-34-4; height:30; radius:8; color:Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.7); border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.5)
                                        RowLayout { anchors.fill:parent; anchors.leftMargin:8; anchors.rightMargin:8; spacing:4
                                            TextInput { id:pwIn; Layout.fillWidth:true; echoMode:root.netPasswordVisible?TextInput.Normal:TextInput.Password; color:root.cOnSurf; font.pixelSize:11; onAccepted:{ root.connectNetwork(netDelegate.modelData.ssid,text); netDelegate._showPass=false } }
                                            Text { text:pwIn.text===""?"Password":""; color:Qt.rgba(root.cOnSurfVar.r,root.cOnSurfVar.g,root.cOnSurfVar.b,0.5); font.pixelSize:11; font.italic:true; anchors.verticalCenter:pwIn.verticalCenter; visible:pwIn.text===""&& !pwIn.activeFocus }
                                            Text { text:root.netPasswordVisible?"󰈉":"󰈈"; font.pixelSize:12; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar; MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.netPasswordVisible=!root.netPasswordVisible} }
                                        }
                                    }
                                    Rectangle { width:30;height:30;radius:8; color:root.cPrimary
                                        Text { anchors.centerIn:parent; text:"󰌑"; font.pixelSize:12; font.family:"Symbols Nerd Font Mono"; color:root.cOnPrim }
                                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked: {
                                            root.connectNetwork(netDelegate.modelData.ssid, pwIn.text)
                                            netDelegate._showPass=false
                                        }}
                                    }
                                }
                            }
                        }

                        // Scanning indicator
                        Text {
                            visible:netScanProc.running&&root.networkList.length===0
                            text:"Scanning..."; color:root.cOnSurfVar; font.pixelSize:11; font.italic:true
                            leftPadding:12
                        }
                    }

                    // ── Bluetooth panel (expanded) ────────────────────────────
                    Column {
                        visible: root.btExpanded
                        Layout.fillWidth: true
                        width: parent.width
                        spacing: 2

                        // Toolbar: Scan + Discoverable + Receive
                        Row {
                            width: parent.width; spacing: 6
                            // Discoverable toggle
                            Rectangle {
                                height: 26; radius: 8; width: 96
                                color: root.btDiscoverable
                                    ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.20)
                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                                border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45)
                                Behavior on color{ColorAnimation{duration:120}}
                                RowLayout { anchors.centerIn:parent; spacing:4
                                    Text { text:"󰂯"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"
                                        color:root.btDiscoverable?root.cPrimary:root.cOnSurfVar }
                                    Text { text:root.btDiscoverable?"Visible":"Hidden"; font.pixelSize:9; color:root.cOnSurfVar }
                                }
                                MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                    onClicked: root.btPowered ? root.toggleBtDiscoverable() : root.toggleBtPower() }
                            }
                            // Scan button
                            Rectangle {
                                height: 26; radius: 8
                                width: 82
                                color: root.btScanning
                                    ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.20)
                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                                border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45)
                                Behavior on color{ColorAnimation{duration:120}}
                                RowLayout { anchors.centerIn:parent; spacing:4
                                    Text {
                                        text:"󰑪"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"
                                        color: root.btScanning ? root.cPrimary : root.cOnSurfVar
                                        RotationAnimator on rotation { from:0;to:360;duration:1000;loops:Animation.Infinite;running:root.btScanning }
                                    }
                                    Text { text: root.btScanning ? "Scanning…" : "Scan"; font.pixelSize:10; color:root.cOnSurfVar }
                                }
                                MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                    onClicked: root.btPowered ? root.toggleBtScan() : root.toggleBtPower() }
                            }
                            // Receive files toggle
                            Rectangle {
                                height: 26; radius: 8
                                width: 110
                                color: root.btReceiving
                                    ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.20)
                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                                border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45)
                                Behavior on color{ColorAnimation{duration:120}}
                                RowLayout { anchors.centerIn:parent; spacing:4
                                    Text { text:"󰶫"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.btReceiving?root.cPrimary:root.cOnSurfVar }
                                    Text { text: root.btReceiving ? "Receiving…" : "Receive Files"; font.pixelSize:10; color:root.cOnSurfVar }
                                }
                                MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor; onClicked: root.toggleBtReceive() }
                            }
                        }

                        // BT off notice
                        Text {
                            visible: !root.btPowered
                            text: "Bluetooth is off"
                            color: root.cOnSurfVar; font.pixelSize:11; font.italic:true
                            leftPadding:4; topPadding:4
                        }

                        // Device list
                        Repeater {
                            model: root.btDevices
                            delegate: Column {
                                id: btDelegate
                                required property var modelData
                                required property int index
                                width: parent.width
                                spacing: 2

                                // Main device row
                                Rectangle {
                                    id: btDevRow
                                    width: parent.width; height: 34; radius: 8
                                    color: bth.containsMouse
                                        ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.10)
                                        : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.5)
                                    Behavior on color{ColorAnimation{duration:100}}
                                    border.width: btDelegate.modelData.connected ? 1 : 0
                                    border.color: Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.5)

                                    RowLayout { anchors.fill:parent; anchors.leftMargin:8; anchors.rightMargin:8; spacing:6
                                        // Per-device-type icon based on BlueZ Icon class
                                        Text {
                                            font.pixelSize:13; font.family:"Symbols Nerd Font Mono"
                                            color: btDelegate.modelData.connected ? root.cPrimary : root.cOnSurfVar
                                            text: {
                                                const ic = (btDelegate.modelData.icon||"").toLowerCase()
                                                if (ic==="audio-headset"||ic==="audio-headphones"||ic==="audio-headset-gateway") return "󰋎"
                                                if (ic==="audio-card"||ic.includes("speaker"))    return "󰓃"
                                                if (ic==="input-keyboard")  return "󰌌"
                                                if (ic==="input-mouse")     return "󰍽"
                                                if (ic==="input-gaming")    return "󰊗"
                                                if (ic==="phone")           return "󰏲"
                                                if (ic==="computer")        return "󰇄"
                                                if (ic.includes("watch")||ic.includes("wearable")) return "󰓹"
                                                if (ic==="printer")         return "󰐪"
                                                if (ic==="camera-photo")    return "󰄀"
                                                if (ic==="camera-video")    return "󰕧"
                                                if (ic==="modem"||ic==="network-wireless") return "󰤨"
                                                return "󰂯"
                                            }
                                        }
                                        Text { Layout.fillWidth:true; text:btDelegate.modelData.name; color:root.cOnSurf; font.pixelSize:11; elide:Text.ElideRight }

                                        // Connecting spinner
                                        Text { text:"󰒖"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary
                                            visible: root.btConnecting===btDelegate.modelData.mac
                                            RotationAnimator on rotation{from:0;to:360;duration:800;loops:Animation.Infinite;running:root.btConnecting===btDelegate.modelData.mac} }

                                        // Success checkmark
                                        Text { text:"󰄬"; font.pixelSize:12; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary
                                            visible: root.btConnectedMac===btDelegate.modelData.mac
                                            opacity: root.btConnectedMac===btDelegate.modelData.mac ? 1.0 : 0.0
                                            Behavior on opacity { NumberAnimation { duration: 400 } } }

                                        // Options expand arrow
                                        Text {
                                            text: root.btExpandedMac===btDelegate.modelData.mac ? "󰅀" : "󰅂"
                                            font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar
                                            MouseArea { anchors.fill:parent; anchors.margins:-6; cursorShape:Qt.PointingHandCursor
                                                onClicked: function(e) {
                                                    e.accepted=true
                                                    const m = btDelegate.modelData.mac
                                                    if(root.btExpandedMac===m){
                                                        root.btExpandedMac=""
                                                    } else {
                                                        root.btExpandedMac=m
                                                        root.btQueryProfile(m)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    MouseArea{id:bth;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;z:-1
                                        onClicked: {
                                            if(root.btConnecting!==""){return}
                                            if(btDelegate.modelData.connected) root.btDisconnect(btDelegate.modelData.mac)
                                            else root.btConnect(btDelegate.modelData.mac)
                                        }
                                    }
                                }

                                // Options panel (expanded per device)
                                Rectangle {
                                    visible: root.btExpandedMac === btDelegate.modelData.mac
                                    width: parent.width
                                    height: visible ? optCol.implicitHeight + 12 : 0
                                    radius: 8
                                    color: Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.35)
                                    border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.3)
                                    clip: true

                                    Column {
                                        id: optCol
                                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:6 }
                                        spacing: 6

                                        // ── Audio device controls: profile pills ─────────────
                                        // Shown for any device the OS registers a bluez PulseAudio
                                        // card for — phones, laptops, speakers, headsets etc.
                                        // Printers and gamepad-class devices never get a bluez card.
                                        RowLayout {
                                            width: parent.width; spacing: 4
                                            visible: root.btHasAudioCard[btDelegate.modelData.mac] === true
                                            Text { text:"Profile:"; font.pixelSize:10; color:root.cOnSurfVar; Layout.preferredWidth:40 }
                                            ProfilePill { pLabel:"A2DP";    pProfile:"a2dp-sink";         pMac:btDelegate.modelData.mac }
                                            ProfilePill { pLabel:"HSP/HFP"; pProfile:"headset-head-unit"; pMac:btDelegate.modelData.mac }
                                            ProfilePill { pLabel:"Off";     pProfile:"off";               pMac:btDelegate.modelData.mac }
                                            Item { Layout.fillWidth:true }
                                        }

                                        // ── Action buttons row ────────────────────────────────
                                        // Audio devices: Default Output + Repair + Forget
                                        // Other devices: Send File + Repair + Forget
                                        RowLayout {
                                            width: parent.width; spacing: 4

                                            // "Set as Default Output" — any device with an audio card, when connected
                                            Rectangle {
                                                height:22; radius:6; implicitWidth: sdLbl.implicitWidth + 20
                                                visible: btDelegate.modelData.connected &&
                                                         root.btHasAudioCard[btDelegate.modelData.mac] === true
                                                color: sdh.containsMouse
                                                    ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.22)
                                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.8)
                                                border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.50)
                                                Behavior on color{ColorAnimation{duration:100}}
                                                RowLayout { id: sdLbl; anchors.centerIn:parent; spacing:4
                                                    Text { text:"󰓃"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary }
                                                    Text { text:"Default Output"; font.pixelSize:10; color:root.cOnSurf }
                                                }
                                                MouseArea { id:sdh; anchors.fill:parent; hoverEnabled:true
                                                    cursorShape:Qt.PointingHandCursor
                                                    onClicked: root.btSetDefaultSink(btDelegate.modelData.mac) }
                                            }

                                            // Trust toggle — non-audio, non-auto-trust devices
                                            // (keyboards, mice, unknown) default untrusted.
                                            // Watches and phones are auto-trusted so they don't show this.
                                            Rectangle {
                                                id: trustRect
                                                height: 22; radius: 6; implicitWidth: trLbl.implicitWidth + 20
                                                property bool _isTrusted: root.btIsTrusted(btDelegate.modelData.mac)
                                                visible: {
                                                    // Trust toggle: file-capable non-audio devices only
                                                    // watches, phones/tablets, computers, printers
                                                    // Excluded: audio devices, gamepads, keyboards, mice
                                                    const ic = (btDelegate.modelData.icon || "").toLowerCase()
                                                    return ic === "phone"              ||
                                                           ic === "computer"           ||
                                                           ic === "printer"            ||
                                                           ic.includes("watch")        ||
                                                           ic.includes("wearable")
                                                }
                                                color: trh.containsMouse
                                                    ? (trustRect._isTrusted
                                                        ? Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.18)
                                                        : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.20))
                                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.8)
                                                border.width: 1
                                                border.color: trustRect._isTrusted
                                                    ? Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.5)
                                                    : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45)
                                                Behavior on color { ColorAnimation { duration: 100 } }
                                                RowLayout { id: trLbl; anchors.centerIn: parent; spacing: 4
                                                    Text {
                                                        // 󰒃 = shield-lock (trusted)  󰒄 = shield-off (untrusted)
                                                        text: trustRect._isTrusted ? "󰒃" : "󰒄"
                                                        font.pixelSize: 11; font.family: "Symbols Nerd Font Mono"
                                                        color: trustRect._isTrusted ? root.cErr : root.cPrimary
                                                    }
                                                    Text {
                                                        text: trustRect._isTrusted ? "Untrust" : "Trust"
                                                        font.pixelSize: 10
                                                        color: trustRect._isTrusted ? root.cErr : root.cOnSurf
                                                    }
                                                }
                                                MouseArea { id: trh; anchors.fill: parent; hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.btSetTrust(btDelegate.modelData.mac, !trustRect._isTrusted)
                                                }
                                            }

                                            // Send File — phones, watches, and non-audio devices
                                            Rectangle {
                                                height:22; radius:6; implicitWidth: sfLbl.implicitWidth + 20
                                                visible: {
                                                    // Send File: watches, phones/tablets, computers, printers
                                                    // Not audio devices, not gamepads/keyboards/mice
                                                    const ic = (btDelegate.modelData.icon || "").toLowerCase()
                                                    return ic === "phone"           ||
                                                           ic === "computer"        ||
                                                           ic === "printer"         ||
                                                           ic.includes("watch")     ||
                                                           ic.includes("wearable")
                                                }
                                                color:sfh.containsMouse
                                                    ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.20)
                                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.8)
                                                border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45)
                                                Behavior on color{ColorAnimation{duration:100}}
                                                RowLayout { id: sfLbl; anchors.centerIn:parent; spacing:4
                                                    Text { text:"󰏢"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar }
                                                    Text { text:"Send File"; font.pixelSize:10; color:root.cOnSurfVar }
                                                }
                                                MouseArea{id:sfh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                                                    onClicked: root.btSendFile(btDelegate.modelData.mac) }
                                            }

                                            Item { Layout.fillWidth: true }

                                            // Repair
                                            Rectangle {
                                                height:22; radius:6; implicitWidth: rpLbl.implicitWidth + 20
                                                color:rph.containsMouse
                                                    ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.22)
                                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.8)
                                                border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45)
                                                Behavior on color{ColorAnimation{duration:100}}
                                                RowLayout { id: rpLbl; anchors.centerIn:parent; spacing:4
                                                    Text { text:"󰑓"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar }
                                                    Text { text:"Repair"; font.pixelSize:10; color:root.cOnSurfVar }
                                                }
                                                MouseArea{id:rph;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                                                    onClicked: root.btRepair(btDelegate.modelData.mac) }
                                            }

                                            // Forget
                                            Rectangle {
                                                height:22; radius:6; implicitWidth: fgLbl.implicitWidth + 20
                                                color:fgh.containsMouse
                                                    ? Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.18)
                                                    : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.8)
                                                border.width:1; border.color:Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.45)
                                                Behavior on color{ColorAnimation{duration:100}}
                                                RowLayout { id: fgLbl; anchors.centerIn:parent; spacing:4
                                                    Text { text:"󰆴"; font.pixelSize:11; font.family:"Symbols Nerd Font Mono"; color:root.cErr; opacity:0.8 }
                                                    Text { text:"Forget"; font.pixelSize:10; color:root.cErr; opacity:0.8 }
                                                }
                                                MouseArea{id:fgh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor
                                                    onClicked: root.btForget(btDelegate.modelData.mac) }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // No paired devices / BT off hint
                        Text {
                            visible: root.btPowered && root.btDevices.length === 0 && !btStatusProc.running
                            text: "No paired devices — use Scan to discover"
                            color: root.cOnSurfVar; font.pixelSize:10; font.italic:true
                            leftPadding:4
                        }
                        // Status loading indicator — only on first load (no devices yet)
                        Text {
                            visible: btStatusProc.running && root.btDevices.length === 0
                            text: "Loading…"; color:root.cOnSurfVar; font.pixelSize:10; font.italic:true
                            leftPadding:4
                        }
                    }
                }

                Rectangle { Layout.fillWidth:true; height:1; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.25) }

                // ── Power / actions grid ──────────────────────────────────
                GridLayout { Layout.fillWidth:true; columns:4; rowSpacing:6; columnSpacing:6
                    Repeater {
                        model:[
                            {i:"",l:"Lock",    cmd:"~/.config/hypr/scripts/power.sh lock",  logout:false},
                            {i:"",l:"Reboot",  cmd:"~/.config/hypr/scripts/power.sh reboot",        logout:false},
                            {i:"󰤄",l:"Sleep",   cmd:"~/.config/hypr/scripts/power.sh suspend",        logout:false},
                            {i:"",l:"Shutdown",cmd:"~/.config/hypr/scripts/power.sh shutdown",       logout:false},
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            Layout.fillWidth:true; height:52; radius:12
                            color:ph.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18):Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                            border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.40)
                            Behavior on color{ColorAnimation{duration:120}}
                            ColumnLayout { anchors.centerIn:parent; spacing:2
                                Text { Layout.alignment:Qt.AlignHCenter; text:modelData.i; font.pixelSize:18; font.family:"Symbols Nerd Font Mono"; color:ph.containsMouse?root.cPrimary:root.cOnSurfVar; Behavior on color{ColorAnimation{duration:120}} }
                                Text { Layout.alignment:Qt.AlignHCenter; text:modelData.l; color:root.cOnSurfVar; font.pixelSize:9 }
                            }
                            MouseArea{id:ph;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{ root.menuVisible=false; powerProc._cmd=modelData.cmd; if(!powerProc.running) powerProc.running=true }}
                        }
                    }
                }

                // Logout button (full width)
                Rectangle {
                    Layout.fillWidth:true; height:36; radius:12
                    color:logh.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18):Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                    border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.40)
                    Behavior on color{ColorAnimation{duration:120}}
                    RowLayout { anchors.centerIn:parent; spacing:8
                        Text { text:"󰗼"; font.pixelSize:16; font.family:"Symbols Nerd Font Mono"; color:logh.containsMouse?root.cPrimary:root.cOnSurfVar; Behavior on color{ColorAnimation{duration:120}} }
                        Text { text:"Logout"; color:logh.containsMouse?root.cPrimary:root.cOnSurfVar; font.pixelSize:12; font.weight:Font.Medium; Behavior on color{ColorAnimation{duration:120}} }
                    }
                    MouseArea{id:logh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{ root.menuVisible=false; if(!logoutProc.running) logoutProc.running=true }}
                }

                Item { height:4 }
            }
        }
    }

    // ── ProfilePill: BT audio profile selector button ─────────────────────────
    // Defined at root level so it is accessible from both outside and inside
    // Repeater delegates without crossing pragma ComponentBehavior:Bound scopes.
    component ProfilePill: Rectangle {
        id: pill
        required property string pLabel
        required property string pProfile
        required property string pMac
        property bool isActive: (root.btActiveProfile[pMac] || "").indexOf(pProfile) >= 0
        height: 24; radius: 6
        width: pillLbl.implicitWidth + 20
        color: isActive
            ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.25)
            : Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.8)
        border.width: 1
        border.color: isActive
            ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.7)
            : Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.4)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text {
            id: pillLbl; anchors.centerIn: parent; text: pill.pLabel
            font.pixelSize: 10; color: pill.isActive ? root.cPrimary : root.cOnSurfVar
        }
        MouseArea {
            anchors.fill: parent; anchors.margins: -1; cursorShape: Qt.PointingHandCursor
            onClicked: root.btSetProfile(pill.pMac, pill.pProfile)
        }
    }

    // ── Inline slider component ───────────────────────────────────────────────
    // Track: radius 4, 1px cPrimary border outline
    // Fill: inversePrimary→onPrimary horizontal gradient
    // Thumb: 3px-wide vertical bar, full track height, cPrimary border
    // Supports scroll wheel (+/- 2% per tick)
    component SliderBg: Item {
        id: sl
        property real value: 0.0
        property color gradA:  root.cInvPrimary
        property color gradB:  root.cOnPrim
        property color track:  root.cOutVar
        property color accent: root.cPrimary
        signal moved(real v)

        // Trough — taller, with inner padding so fill + thumb sit inside it
        // Inner padding: 3px top+bottom, so fill height = trackH - 6
        readonly property int trackH: 14       // full trough height
        readonly property int pad:    3         // inner vertical padding
        readonly property int innerH: trackH - pad * 2   // = 8

        Item {
            y: (parent.height - sl.trackH) / 2
            width: parent.width; height: sl.trackH

            // Trough background
            Rectangle {
                anchors.fill: parent; radius: sl.trackH / 2
                color: Qt.rgba(sl.track.r, sl.track.g, sl.track.b, 0.28)
                border.width: 1; border.color: Qt.rgba(sl.accent.r, sl.accent.g, sl.accent.b, 0.55)
            }

            // Gradient fill — inset by pad, clipped to left portion
            Item {
                x: sl.pad; y: sl.pad
                width:  Math.max(0, (parent.width - sl.pad * 2) * sl.value)
                height: sl.innerH
                clip:   true
                Rectangle {
                    // Full-width gradient so proportions stay consistent regardless of fill amount
                    width:  parent.parent.width - sl.pad * 2
                    height: sl.innerH
                    radius: sl.innerH / 2
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: sl.gradA }
                        GradientStop { position: 1.0; color: sl.gradB }
                    }
                }
            }

            // Thumb — dot-circle glyph (󰟃 nf-md-dots) sitting inside the trough
            // Sized to innerH so it never overflows the trough boundary
            Text {
                text: "󰟃"
                font.family: "Symbols Nerd Font Mono"
                font.pixelSize: sl.innerH + 2   // slightly larger than inner for crisp rendering
                color: sl.accent
                style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.25)
                // Centre vertically in trough; x tracks fill edge
                x: {
                    const tw = parent.width - sl.pad * 2
                    const cx = sl.pad + tw * sl.value - implicitWidth / 2
                    return Math.max(sl.pad - implicitWidth/2 + 1,
                           Math.min(parent.width - sl.pad - implicitWidth/2 - 1, cx))
                }
                y: (sl.trackH - implicitHeight) / 2
            }
        }

        MouseArea {
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
            preventStealing: true
            onPressed:         function(m){ const v=Math.max(0,Math.min(1,m.x/width)); sl.value=v; sl.moved(v) }
            onPositionChanged: function(m){ if(pressed){ const v=Math.max(0,Math.min(1,m.x/width)); sl.value=v; sl.moved(v) } }
            onWheel:           function(e){
                const step = 0.02 * (e.angleDelta.y > 0 ? 1 : -1)
                const v = Math.max(0, Math.min(1, sl.value + step))
                sl.value = v; sl.moved(v)
            }
        }
    }
}
