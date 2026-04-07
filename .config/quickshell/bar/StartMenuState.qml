pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  StartMenuState — brightness, volume, network, bluetooth, recorder,
//  screenshot, user icon. All state + processes live in the bar process.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: sm
    visible: false

    // ── Visibility ────────────────────────────────────────────────────────
    property bool menuVisible: false
    function toggle() { sm.menuVisible = !sm.menuVisible }
    function open()   {
        sm.menuVisible = true
        if (!volReadProc.running) volReadProc.running = true
    }
    function close()  { sm.menuVisible = false }

    // ── Network scan state ──────────────────────────────────────────────
    property bool netScanProcRunning: false
    property bool netSavedProcRunning: false
    function startNetScan() {
        if (!netSavedProc.running) netSavedProc.running = true
        if (!netScanProc.running) netScanProc.running = true
    }

    // ── BT status state ─────────────────────────────────────────────────
    property bool btStatusProcRunning: false
    function startBtStatus() {
        if (!btStatusProc.running) btStatusProc.running = true
    }

    // ── Brightness ───────────────────────────────────────────────────────────
    property real backlightValue: 1.0; property real backlightMax: 100
    property bool _backlightUserChanging: false
    Timer { id: backlightUserChangingTimer; interval: 400; repeat: false
        onTriggered: { sm._backlightUserChanging = false } }
    Process { id: blReadProc
        command:["brightnessctl","-m"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){
            const p=l.split(",")
            if(p.length>=5){
                sm.backlightMax=parseFloat(p[4])||4882
                if (!sm._backlightUserChanging)
                    sm.backlightValue=parseFloat(p[3].replace("%",""))/100
            }
        }}
        Component.onCompleted: running=true
    }
    Process { id: blSetProc; property string _val:""; property string _queued:""
        command:["brightnessctl","s",blSetProc._val]
        onExited: { if(_queued!==""){ _val=_queued; _queued=""; running=true } else { backlightUserChangingTimer.restart() } }
    }
    function setBacklight(v){
        sm._backlightUserChanging = true
        backlightUserChangingTimer.restart()
        const n=String(Math.round(v*sm.backlightMax))
        if(blSetProc.running){ blSetProc._queued=n } else { blSetProc._val=n; blSetProc.running=true }
    }
    // Initial poll + fast polling to match volume slider responsiveness
    Timer { interval:250; running:true; repeat:false; onTriggered: if(!blReadProc.running) blReadProc.running=true }
    Timer { interval:200; repeat:true; running:true
        onTriggered: { if(!blReadProc.running) blReadProc.running=true } }

    // ── Volume ────────────────────────────────────────────────────────────────
    property real volumeValue: 0.5; property bool volumeMuted: false
    Process { id: volReadProc; property var _b:[]
        command:["bash","-c","pactl get-sink-volume @DEFAULT_SINK@ && pactl get-sink-mute @DEFAULT_SINK@"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){ const vm=l.match(/(\d+)%/); if(vm) sm.volumeValue=parseInt(vm[1])/100; if(l.includes("Mute:")) sm.volumeMuted=l.includes("yes") } }
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
    // Poll volume every 200ms so slider reflects external keybind changes
    Timer { interval:200; repeat:true; running:true
        onTriggered: { if(!volReadProc.running) volReadProc.running=true } }

    // ── Clock tick ────────────────────────────────────────────────────────
    property date _now: new Date()
    Timer { interval:10000; repeat:true; running:true; onTriggered: sm._now = new Date() }

    // ── Network ────────────────────────────────────────────────────────────────
    property bool networkExpanded: false
    property var networkList: []
    property string networkStatus: ""; property string networkSSID: ""
    property bool netConnecting_: false
    property string netConnectTarget: ""; property bool netPasswordVisible: false

    Process { id: netStatusProc
        command:["bash","-c","nmcli --escape no -t -f DEVICE,STATE,CONNECTION dev | awk -F: 'NR==1||/wlan|wifi|wlp/{print;exit}'"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){
            const idx1=l.indexOf(":"), idx2=l.indexOf(":",idx1+1)
            if(idx1>0&&idx2>0){
                sm.networkStatus=l.substring(idx1+1,idx2)
                sm.networkSSID=l.substring(idx2+1)
            }
        }}
        Component.onCompleted: running=true
    }
    Timer { interval:8000; repeat:true; running:true; onTriggered: if(!netStatusProc.running) netStatusProc.running=true }

    property var _netBuf: []
    property var _savedNets: []
    Process { id: netSavedProc
        command: ["bash", "-c", "nmcli --escape no -t -f NAME con show 2>/dev/null"]
        running: true
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            const n = l.trim(); if (n) sm._savedNets.push(n)
        }}
        onRunningChanged: {
            sm.netSavedProcRunning = running
            if (running) sm._savedNets = []
        }
    }
    Process { id: netScanProc
        command:["bash","-c","nmcli --escape no -t -f IN-USE,SECURITY,SIGNAL,SSID dev wifi list 2>/dev/null | head -25"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){
            const c1=l.indexOf(":"), c2=l.indexOf(":",c1+1), c3=l.indexOf(":",c2+1)
            if(c3<0) return
            const inuse=l.substring(0,c1)
            const sec=l.substring(c1+1,c2)
            const sig=l.substring(c2+1,c3)
            const ssid=l.substring(c3+1)
            const saved = sm._savedNets.indexOf(ssid) >= 0
            if(ssid) sm._netBuf.push({active:inuse==="*",secure:sec!=="",signal:parseInt(sig)||0,ssid:ssid,saved:saved})
        }}
        onRunningChanged: {
            sm.netScanProcRunning = running
            if(running) { sm._netBuf=[] } else { sm.networkList=sm._netBuf.slice() }
        }
    }
    Process { id: netConnProc; property string _cmd:""; property string _lastSSID:"";
        command:["bash","-c",netConnProc._cmd]
        onExited: function(code) {
            sm.netConnecting_=false
            if (code === 0) { sm.netConnectedSSID = netConnProc._lastSSID; netConnFeedbackTimer.restart() }
            if(!netStatusProc.running) netStatusProc.running=true
        }
    }
    Timer { id: netConnFeedbackTimer; interval: 2500; repeat: false
        onTriggered: sm.netConnectedSSID = "" }
    function connectNetwork(ssid, password){
        const esc=ssid.replace(/'/g,"'\\''")
        if(password) netConnProc._cmd="nmcli device wifi connect '"+esc+"' password '"+password.replace(/'/g,"'\\''")+"'"
        else netConnProc._cmd="nmcli connection up '"+esc+"' 2>/dev/null || nmcli device wifi connect '"+esc+"'"
        sm.netConnecting_=true; sm.netConnectTarget=ssid; netConnProc._lastSSID=ssid
        if(!netConnProc.running) netConnProc.running=true
    }

    // ── Bluetooth ─────────────────────────────────────────────────────────────
    property bool   btExpanded:    false
    property bool   btPowered:     false
    property bool   btScanning:    false
    property var    btDevices:     []
    property string btConnecting:  ""
    property string btExpandedMac: ""
    property var    btActiveProfile: ({})
    property var    btHasAudioCard:  ({})
    property string btConnectedMac: ""
    property string netConnectedSSID: ""
    property var    btTrusted: ({})
    property bool   btDiscoverable: false
    property bool   btReceiving: false

    // ── BT pairing agent state ────────────────────────────────────────────────
    // bt-agent.py sits on a FIFO at /tmp/qs_bt_cmd and handles BlueZ
    // RequestConfirmation / RequestPinCode / Authorize D-Bus calls.
    // Without a registered agent, BlueZ times-out every new-device pairing with
    // org.bluez.Error.AuthenticationTimeout after ~30 s.
    property string _btFifo: "/tmp/qs_bt_cmd"

    // Pairing dialog state
    property bool   btPairDialogVisible: false
    property string btPairDialogType:    ""   // "confirm" | "pin" | "passkey" | "authorize"
    property string btPairDialogMac:     ""
    property string btPairDialogName:    ""
    property string btPairDialogPasskey: ""

    // Incoming file dialog state
    property bool   btFileDialogVisible: false
    property string btFileDialogMac:     ""
    property string btFileDialogName:    ""
    property string btFileDialogFile:    ""
    property int    btFileDialogSize:    0
    property string btFileDialogTransfer: ""

    property string _btTrustDir: Quickshell.env("HOME") + "/.config/hyprcandy/bt-trust"

    function _btTrustFile(mac) {
        return sm._btTrustDir + "/" + mac.replace(/:/g, "_") + ".trust"
    }
    function btIsTrusted(mac) {
        return sm.btTrusted[mac] === true
    }
    function btIsAutoTrust(mac) {
        const dev = sm.btDevices.find(function(d) { return d.mac === mac })
        if (!dev) return false
        const ic = (dev.icon || "").toLowerCase()
        return ic === "audio-headset"        || ic === "audio-headset-gateway" ||
               ic === "audio-headphones"     || ic === "audio-card"            ||
               ic.includes("speaker")        ||
               ic === "phone"                || ic === "computer"              ||
               ic.includes("watch")          || ic.includes("wearable")
    }

    // ── Status poll ──────────────────────────────────────────────────────────
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
                sm.btPowered = l.slice(8).trim() === "yes"
            else if (l.startsWith("DISCOVERABLE:"))
                sm.btDiscoverable = l.slice(13).trim() === "yes"
            else if (l.startsWith("DEV:")) {
                const p = l.slice(4).split("|")
                if (p.length >= 3)
                    btStatusProc._buf.push({ mac:p[0], name:p[1]||p[0], connected:p[2]==="1", icon:p[3]||"" })
            }
        }}
        onRunningChanged: {
            sm.btStatusProcRunning = running
            if (running) _buf = []
        }
        onExited: {
            sm.btDevices = _buf.slice()
            btTrustReadProc._macs = sm.btDevices.map(function(d) { return d.mac })
            if (!btTrustReadProc.running) btTrustReadProc.running = true
            sm.btDevices.forEach(function(d) {
                if (sm.btIsAutoTrust(d.mac) && sm.btTrusted[d.mac] === undefined) {
                    sm.btSetTrust(d.mac, true)
                }
            })
            if (!btStatusProc._autoReconnectDone && sm.btPowered) {
                btStatusProc._autoReconnectDone = true
                const disconnected = sm.btDevices.filter(function(x) { return !x.connected })
                if (disconnected.length > 0) {
                    btAutoReconnProc._macs = disconnected.map(function(x) { return x.mac })
                    if (!btAutoReconnProc.running) btAutoReconnProc.running = true
                }
            }
        }
        property bool _autoReconnectDone: false
        Component.onCompleted: running = true
    }

    Process { id: btAutoReconnProc; property var _macs: []
        command: ["bash", "-c",
            "for mac in " + btAutoReconnProc._macs.join(" ") + "; do " +
            "  bluetoothctl connect $mac 2>/dev/null; sleep 1; " +
            "done"]
        onExited: { if (!btStatusProc.running) btStatusProc.running = true }
    }

    // ── Trust management ──────────────────────────────────────────────────────
    Process { id: btTrustReadProc; property var _macs: []
        command: ["bash", "-c",
            "mkdir -p '" + sm._btTrustDir + "'; " +
            "for mac in " + btTrustReadProc._macs.join(" ") + "; do " +
            "  f='" + sm._btTrustDir + "/'$(echo $mac | tr ':' '_')'.trust'; " +
            "  [ -f \"$f\" ] && echo \"TRUSTED:$mac\" || echo \"UNTRUSTED:$mac\"; " +
            "done"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (l.startsWith("TRUSTED:")) {
                const mac = l.slice(8).trim()
                const o = Object.assign({}, sm.btTrusted); o[mac] = true; sm.btTrusted = o
            } else if (l.startsWith("UNTRUSTED:")) {
                const mac = l.slice(10).trim()
                const o = Object.assign({}, sm.btTrusted); o[mac] = false; sm.btTrusted = o
            }
        }}
    }

    Process { id: btTrustSetProc; property string _cmd: ""
        command: ["bash", "-c", btTrustSetProc._cmd]
        onExited: {
            btTrustReadProc._macs = sm.btDevices.map(function(d) { return d.mac })
            if (!btTrustReadProc.running) btTrustReadProc.running = true
        }
    }
    function btSetTrust(mac, trusted) {
        const f = "'" + sm._btTrustDir + "/'$(echo " + mac + " | tr ':' '_')'.trust'"
        if (trusted) {
            btTrustSetProc._cmd =
                "mkdir -p '" + sm._btTrustDir + "' && touch " + f + " && " +
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
        btPowerProc._cmd = sm.btPowered ? "bluetoothctl power off" : "bluetoothctl power on"
        if (!btPowerProc.running) btPowerProc.running = true
    }
    function toggleBtDiscoverable() {
        btPowerProc._cmd = sm.btDiscoverable
            ? "bluetoothctl discoverable off"
            : "bluetoothctl discoverable on && bluetoothctl pairable on"
        if (!btPowerProc.running) btPowerProc.running = true
    }
    function btRepair(mac) {
        // Remove stale pairing entry; the agent handles any passkey exchange
        sm.btConnecting = mac; btConnProc._lastMac = mac
        btConnProc._cmd =
            "bluetoothctl remove " + mac + " 2>/dev/null; sleep 0.5; " +
            "bluetoothctl pair "   + mac + " 2>/dev/null; sleep 0.3; " +
            "bluetoothctl connect "+ mac + " 2>/dev/null"
        if (!btConnProc.running) btConnProc.running = true
    }

    // ── BT pairing agent ──────────────────────────────────────────────────────
    // Create FIFO then start bt-agent.py once at startup.
    Process { id: btFifoInitProc
        command: ["bash", "-c",
            "[ -p '" + sm._btFifo + "' ] || mkfifo '" + sm._btFifo + "'"]
        onExited: { if (!btAgentProc.running) btAgentProc.running = true }
        Component.onCompleted: running = true
    }
    Process { id: btAgentProc
        property string _dir: Quickshell.env("HOME") + "/.config/quickshell/notifications"
        command: ["python3", btAgentProc._dir + "/bt-agent.py"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(line) {
            const l = line.trim(); if (!l) return
            let ev; try { ev = JSON.parse(l) } catch(e) { return }
            switch (ev.type) {
                case "pair_confirm":
                    sm.btPairDialogType    = "confirm"
                    sm.btPairDialogMac     = ev.mac    || ""
                    sm.btPairDialogName    = ev.name   || ev.mac || ""
                    sm.btPairDialogPasskey = ev.passkey || ""
                    sm.btPairDialogVisible = true
                    sm.menuVisible         = true
                    break
                case "pair_pin":
                    sm.btPairDialogType    = ev.needs_passkey ? "passkey" : "pin"
                    sm.btPairDialogMac     = ev.mac   || ""
                    sm.btPairDialogName    = ev.name  || ev.mac || ""
                    sm.btPairDialogPasskey = ""
                    sm.btPairDialogVisible = true
                    sm.menuVisible         = true
                    break
                case "pair_authorize":
                    sm.btPairDialogType    = "authorize"
                    sm.btPairDialogMac     = ev.mac   || ""
                    sm.btPairDialogName    = ev.name  || ev.mac || ""
                    sm.btPairDialogPasskey = ""
                    sm.btPairDialogVisible = true
                    sm.menuVisible         = true
                    break
                case "pair_cancelled":
                    if (sm.btPairDialogMac === (ev.mac || ""))
                        sm.btPairDialogVisible = false
                    break
                case "file_request":
                    sm.btFileDialogMac      = ev.mac      || ""
                    sm.btFileDialogName     = ev.name     || ev.mac || ""
                    sm.btFileDialogFile     = ev.filename || ""
                    sm.btFileDialogSize     = ev.size     || 0
                    sm.btFileDialogTransfer = ev.transfer || ""
                    sm.btFileDialogVisible  = true
                    sm.menuVisible          = true
                    break
                case "file_cancelled":
                    sm.btFileDialogVisible = false
                    break
            }
        }}
        onExited: { if (!btAgentRestartTimer.running) btAgentRestartTimer.start() }
    }
    Timer { id: btAgentRestartTimer; interval: 3000; repeat: false
        onTriggered: { if (!btAgentProc.running) btAgentProc.running = true } }

    // Send a command line to the agent via the FIFO
    Process { id: btSendCmdProc; property string _cmd: ""
        command: ["bash", "-c", "echo " + btSendCmdProc._cmd + " >> '" + sm._btFifo + "'"]
    }
    function btSendCmd(line) {
        btSendCmdProc._cmd = "'" + line.replace(/'/g, "'\\''") + "'"
        if (!btSendCmdProc.running) btSendCmdProc.running = true
    }
    function btAcceptPair() {
        const mac = sm.btPairDialogMac
        if (sm.btPairDialogType === "pin" || sm.btPairDialogType === "passkey")
            sm.btSendCmd("pin_pair " + mac + " " + sm.btPairDialogPasskey)
        else
            sm.btSendCmd("accept_pair " + mac)
        sm.btPairDialogVisible = false
        sm.btConnecting = mac
    }
    function btRejectPair() {
        sm.btSendCmd("reject_pair " + sm.btPairDialogMac)
        sm.btPairDialogVisible = false
    }
    function btAcceptFile() {
        sm.btSendCmd("accept_file " + sm.btFileDialogTransfer)
        sm.btFileDialogVisible = false
    }
    function btRejectFile() {
        sm.btSendCmd("reject_file " + sm.btFileDialogTransfer)
        sm.btFileDialogVisible = false
    }

    // ── Discovery scan ─────────────────────────────────────────────────────────
    Process { id: btScanProc
        command: ["bash", "-c",
            "bluetoothctl --timeout 20 scan on 2>/dev/null; " +
            "bluetoothctl scan off 2>/dev/null"
        ]
        onExited: {
            sm.btScanning = false
            btScanLiveTimer.stop()
            if (!btStatusProc.running) btStatusProc.running = true
        }
    }
    Timer { id: btScanLiveTimer; interval: 3000; repeat: true
        onTriggered: if (!btStatusProc.running) btStatusProc.running = true }
    function toggleBtScan() {
        if (sm.btScanning) {
            sm.btScanning = false
            btScanLiveTimer.stop()
            if (btScanProc.running) btScanProc.running = false
            if (!btStatusProc.running) btStatusProc.running = true
        } else {
            sm.btScanning = true
            if (!btScanProc.running) btScanProc.running = true
            btScanLiveTimer.restart()
        }
    }

    // ── Connect / disconnect / forget ─────────────────────────────────────────
    Process { id: btConnProc; property string _cmd: ""; property string _lastMac: ""; property string _capturedPct: ""
        command: ["bash", "-c", btConnProc._cmd]
        onExited: function(code) {
            sm.btConnecting = ""
            if (code === 0) {
                sm.btConnectedMac = btConnProc._lastMac
                btConnFeedbackTimer.restart()
                sm.btSetSinkVolume(btConnProc._lastMac, btConnProc._capturedPct)
            }
            if (!btStatusProc.running) btStatusProc.running = true
        }
    }
    Timer { id: btConnFeedbackTimer; interval: 2500; repeat: false
        onTriggered: sm.btConnectedMac = "" }

    // ── BT volume preservation ────────────────────────────────────────────────
    Process { id: btSinkVolProc; property string _cmd: ""
        command: ["bash", "-c", btSinkVolProc._cmd]
        onExited: { if (!volReadProc.running) volReadProc.running = true }
    }
    function btSetSinkVolume(mac, capturedPct) {
        const macFrag = mac.replace(/:/g, "_").toLowerCase()
        const pct = capturedPct || (Math.round(sm.volumeValue * 100) + "%")
        btSinkVolProc._cmd =
            "PCT='" + pct + "'; FRAG='" + macFrag + "'; " +
            "for i in $(seq 1 12); do " +
            "  SINK=$(pactl list short sinks 2>/dev/null | awk '{print $2}' | grep -i \"$FRAG\" | head -1); " +
            "  [ -n \"$SINK\" ] && break; sleep 0.5; " +
            "done; " +
            "[ -z \"$SINK\" ] && exit 0; " +
            "pactl set-sink-volume \"$SINK\" \"$PCT\" 2>/dev/null; " +
            "sleep 0.8; pactl set-sink-volume \"$SINK\" \"$PCT\" 2>/dev/null; " +
            "pactl set-sink-volume @DEFAULT_SINK@ \"$PCT\" 2>/dev/null; true"
        if (!btSinkVolProc.running) btSinkVolProc.running = true
    }

    Process { id: btDefaultSinkProc; property string _cmd: ""
                                     property string _capturedPct: ""
                                     property string _mac: ""
        command: ["bash", "-c", btDefaultSinkProc._cmd]
        onExited: {
            if (_mac !== "") sm.btSetSinkVolume(_mac, _capturedPct)
            if (!volReadProc.running) volReadProc.running = true
        }
    }
    function btSetDefaultSink(mac) {
        const macFrag = mac.replace(/:/g, "_").toLowerCase()
        btDefaultSinkProc._capturedPct = Math.round(sm.volumeValue * 100) + "%"
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
        sm.btConnecting = mac; btConnProc._lastMac = mac
        btConnProc._capturedPct = Math.round(sm.volumeValue * 100) + "%"
        btConnProc._cmd = "bluetoothctl connect " + mac
        if (!btConnProc.running) btConnProc.running = true
    }
    function btDisconnect(mac) {
        sm.btConnecting = mac; btConnProc._lastMac = mac
        btConnProc._cmd = "bluetoothctl disconnect " + mac
        if (!btConnProc.running) btConnProc.running = true
    }
    function btForget(mac) {
        if (sm.btExpandedMac === mac) sm.btExpandedMac = ""
        btConnProc._cmd = "bluetoothctl remove " + mac
        if (!btConnProc.running) btConnProc.running = true
        if (!sm.btScanning) sm.toggleBtScan()
    }

    // ── Audio profile query ────────────────────────────────────────────────────────
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
            const h = Object.assign({}, sm.btHasAudioCard)
            h[mac] = hasCard
            sm.btHasAudioCard = h
            const line = _lines.find(function(x) { return x.startsWith("Active Profile:") })
            if (line) {
                const o = Object.assign({}, sm.btActiveProfile)
                o[mac] = line.replace("Active Profile:", "").trim()
                sm.btActiveProfile = o
            }
        }
    }
    function btQueryProfile(mac) {
        btProfileQueryProc._mac = mac
        if (!btProfileQueryProc.running) btProfileQueryProc.running = true
    }

    Process { id: btSetProfileProc; property string _cmd: ""
        command: ["bash", "-c", btSetProfileProc._cmd]
        onExited: if (!btProfileQueryProc.running) btProfileQueryProc.running = true
    }
    function btSetProfile(mac, profile) {
        const card = "bluez_card." + mac.replace(/:/g, "_")
        btSetProfileProc._cmd = "pactl set-card-profile " + card + " " + profile
        if (!btSetProfileProc.running) btSetProfileProc.running = true
    }

    // ── File send ─────────────────────────────────────────────────────────────
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

    // ── File receive ─────────────────────────────────────────────────────────────
    Process { id: btObexProc; property string _cmd: ""
        command: ["bash", "-c", btObexProc._cmd]
        onExited: sm.btReceiving = false
    }
    function toggleBtReceive() {
        if (sm.btReceiving) {
            btObexProc._cmd = "pkill -f 'obexd.*auto-accept' 2>/dev/null; true"
            sm.btReceiving = false
            if (!btObexProc.running) btObexProc.running = true
        } else {
            sm.btReceiving = true
            btObexProc._cmd =
                "pkill -f 'obexd.*auto-accept' 2>/dev/null; " +
                "/usr/lib/bluetooth/obexd --root \"${HOME}/Downloads\" --auto-accept &"
            if (!btObexProc.running) btObexProc.running = true
        }
    }

    // ── Recorder ─────────────────────────────────────────────────────────
    property bool isRecording: false
    property string _recFile: ""

    Process { id: recCheckProc
        command:["bash","-c","pgrep -x wf-recorder > /dev/null && echo 1 || echo 0"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){ sm.isRecording=l.trim()==="1" } }
        Component.onCompleted: running=true
    }
    Timer { interval:3000; repeat:true; running:true
        onTriggered: if(!recCheckProc.running) recCheckProc.running=true }

    Process { id: recProc; property string _cmd:""; command:["bash","-c",recProc._cmd]
        onRunningChanged: if(!running) recStopRefreshTimer.restart()
    }
    Timer { id:recStopRefreshTimer; interval:500; repeat:false
        onTriggered: if(!recCheckProc.running) recCheckProc.running=true }

    Process { id: recNotifyProc; property string _cmd:""
        command:["bash","-c",recNotifyProc._cmd] }

    function toggleRecorder(){
        if(sm.isRecording){
            const savedFile = sm._recFile
            sm._recFile = ""
            recProc._cmd = "pkill -SIGINT wf-recorder"
            if(!recProc.running) recProc.running=true

            const sf = savedFile.replace(/'/g, "'\\''")
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
            sm._recFile = dest
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

    // ── Screenshot ───────────────────────────────────────────────────────────────
    Process { id: ssProc; command: ["setsid", "-f",
        Quickshell.env("HOME") + "/.config/hypr/scripts/screenshot.sh"] }
    function takeScreenshot(){
        sm.menuVisible = false
        if (!ssProc.running) ssProc.running = true
    }

    // ── Power/logout ──────────────────────────────────────────────────────
    Process { id: logoutProc; command:["bash","-c","hyprctl dispatch exit"] }
    Process { id: powerProc; property string _cmd:""; command:["bash","-c",powerProc._cmd] }

    function runPowerCmd(cmd) {
        powerProc._cmd = cmd
        if (!powerProc.running) powerProc.running = true
    }
    function logout() {
        if (!logoutProc.running) logoutProc.running = true
    }

    // ── User icon ────────────────────────────────────────────────────────────────
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
            if(code===0) sm._userIconPath = smIconProc._dst+"?"+Date.now()
        }
    }

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
            if (newTime && newTime !== "0" && newTime !== sm._lastIconTime) {
                sm._lastIconTime = newTime
                if (!smIconProc.running) smIconProc.running = true
            }
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { _smIconCheck._stdout = line.trim() }
        }
        property string _stdout: ""
    }
}
