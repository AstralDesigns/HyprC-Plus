pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

ShellRoot {
    id: root

    // ── Matugen colors ──────────────────────────────────────────────────────
    property string _m3sourceColor:	     "#a57c44"
    property string _m3primary:              "#f7af91"
    property string _m3primaryContainer:     "#a37c48"
    property string _m3onPrimary:            "#170700"
    property string _m3background:           "#170700"
    property string _m3inversePrimary:       "#6f2900"
    property string _m3surfaceContainerHigh: "#1e1613"
    property string _m3onSurface:            "#f8dfd5"
    property string _m3onSurfaceVariant:     "#dab9ad"
    property string _m3outlineVariant:       "#665046"
    property string _m3error:                "#ffb4ab"
    property string _m3primaryFixedDim:      "#f7af91"
    property string _m3secondary:            "#e7bfb0"
    property string _m3secondaryContainer:   "#61503b"
    property string _m3onSecondary:          "#160701"
    property string _m3tertiary:             "#c9cb90"
    property string _m3onTertiary:           "#141500"
    property string _m3secondaryFixedDim:    "#e7bfb0"
    property string _m3tertiaryFixedDim:     "#c9cb90"

    readonly property color cSourceColor:	Qt.color(_m3sourceColor)
    readonly property color cPrimary:           Qt.color(_m3primary)
    readonly property color cOnPrimary:         Qt.color(_m3onPrimary)
    readonly property color cPrimaryContainer:  Qt.color(_m3primaryContainer)
    readonly property color cOnSurf:            Qt.color(_m3onSurface)
    readonly property color cOnSurfVar:         Qt.color(_m3onSurfaceVariant)
    readonly property color cBg:                Qt.color(_m3background)
    readonly property color cInvPrimary:        Qt.color(_m3inversePrimary)
    readonly property color cSurfHi:            Qt.color(_m3surfaceContainerHigh)
    readonly property color cOutVar:            Qt.color(_m3outlineVariant)
    readonly property color cErr:               Qt.color(_m3error)
    readonly property color cPrimFixedDim:      Qt.color(_m3primaryFixedDim)
    readonly property color cSecondary:         Qt.color(_m3secondary)
    readonly property color cSecondaryContainer:Qt.color(_m3secondaryContainer)
    readonly property color cOnSecondary:       Qt.color(_m3onSecondary)
    readonly property color cTertiary:          Qt.color(_m3tertiary)
    readonly property color cSecondaryFixedDim: Qt.color(_m3secondaryFixedDim)
    readonly property color cTertiaryFixedDim:  Qt.color(_m3tertiaryFixedDim)

    // Outer panel tint
    readonly property color cPanel: Qt.rgba(
        Qt.color(_m3inversePrimary).r, Qt.color(_m3inversePrimary).g,
        Qt.color(_m3inversePrimary).b, 0.65)
    // Sub-card backgrounds
    readonly property color cCardDark: Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.60)
    readonly property color cCardWarm: Qt.rgba(
        Qt.color(_m3background).r, Qt.color(_m3background).g,
        Qt.color(_m3background).b, 0.30)

    function parseColors(t) {
        const re=/property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while((m=re.exec(t))!==null) switch(m[1]) {
            case "m3sourceColor":   	   root._m3sourceColor=m[2]; break
            case "m3primary":              root._m3primary=m[2]; break
            case "m3primaryContainer":     root._m3primaryContainer=m[2]; break
            case "m3onPrimary":            root._m3onPrimary=m[2]; break
            case "m3background":           root._m3background=m[2]; break
            case "m3inversePrimary":       root._m3inversePrimary=m[2]; break
            case "m3surfaceContainerHigh": root._m3surfaceContainerHigh=m[2]; break
            case "m3onSurface":            root._m3onSurface=m[2]; break
            case "m3onSurfaceVariant":     root._m3onSurfaceVariant=m[2]; break
            case "m3outlineVariant":       root._m3outlineVariant=m[2]; break
            case "m3error":                root._m3error=m[2]; break
            case "m3primaryFixedDim":      root._m3primaryFixedDim=m[2]; break
            case "m3secondary":            root._m3secondary=m[2]; break
            case "m3secondaryContainer":   root._m3secondaryContainer=m[2]; break
            case "m3onSecondary":          root._m3onSecondary=m[2]; break
            case "m3tertiary":             root._m3tertiary=m[2]; break
            case "m3onTertiary":           root._m3onTertiary=m[2]; break
            case "m3secondaryFixedDim":    root._m3secondaryFixedDim=m[2]; break
            case "m3tertiaryFixedDim":     root._m3tertiaryFixedDim=m[2]; break
        }
    }
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME")||(Quickshell.env("HOME")+"/.cache"))+"/quickshell/wallpaper/MatugenColors.qml"
        watchChanges:true; onFileChanged:reload(); onLoaded:root.parseColors(text())
    }

    // ── Wallpaper ────────────────────────────────────────────────────────────
    property string wallpaperPath: ""
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME")||(Quickshell.env("HOME")+"/.config"))+"/wallpaper/wallpaper.ini"
        watchChanges:true; onFileChanged:reload()
        onLoaded: { const m=text().match(/^wallpaper\s*=\s*(.+)$/m); if(m) root.wallpaperPath=m[1].trim().replace(/^~/,Quickshell.env("HOME")) }
    }

    // ── Auth ─────────────────────────────────────────────────────────────────
    property string pinEntry:""; property bool authFailed:false; property bool authChecking:false
    property string _pendingPin:""; property bool focusPinRequest:false
    function submitPin() {
        if(authChecking||root.pinEntry.length===0) return
        root._pendingPin=root.pinEntry; root.pinEntry=""; root.authChecking=true; root.authFailed=false
        authProc.running=true
    }
    Timer { id:failTimer; interval:2500; onTriggered:{ root.authFailed=false; root.focusPinRequest=!root.focusPinRequest } }
    Process {
        id:authProc; stdinEnabled:true
        command:[Quickshell.env("HOME")+"/.config/quickshell/candylock/pam_auth"]
        onRunningChanged: if(running){ write(root._pendingPin+"\n"); root._pendingPin="" }
        onExited: function(code){ root.authChecking=false; if(code===0){ sessionLock.locked=false; Qt.quit() } else{ root.authFailed=true; failTimer.restart() } }
    }

    // ── Clock ────────────────────────────────────────────────────────────────
    property string clockHour:Qt.formatTime(new Date(),"hh")
    property string clockMin: Qt.formatTime(new Date(),"mm")
    property string clockDate:Qt.formatDate(new Date(),"dddd, d MMMM")
    Timer { interval:5000; repeat:true; running:true; onTriggered:{
        root.clockHour=Qt.formatTime(new Date(),"hh")
        root.clockMin=Qt.formatTime(new Date(),"mm")
        root.clockDate=Qt.formatDate(new Date(),"dddd, d MMMM")
    }}

    // ── Weather ───────────────────────────────────────────────────────────────
    property string weatherUnit: "metric"
    property string weatherIcon: "󰖐"
    property string weatherTemp: "--°"
    property real   _wxTempC: 0; property real _wxHumidity: 0
    property int    _wxCode: 0;  property int  _wxIsDay: 1

    FileView {
        path: "/tmp/waybar-weather-unit"
        watchChanges:true; onFileChanged:reload()
        onLoaded: {
            const u=text().trim()
            if(u==="imperial"||u==="metric") root.weatherUnit=u
            root._updateWeatherDisplay()
        }
    }

    function wmoIcon(code, isDay, humidity) {
        if(code===0)  return isDay?"󰖙":"󰖔"                           // clear day/night
        if(code<=2)   return isDay?"󰖕":"󰼱"                           // mainly clear
        if(code===3)  return humidity>=85
            ?(isDay?"":"")                                            // overcast+humid (rainy)
            :(isDay?"󰼰":"󰖑")                                          // overcast
        if(code<=48)  return isDay?"":""                             // fog
        if(code<=55)  return "󰖗"                                                  // drizzle
        if(code<=57)  return "󰖒"                                                  // freezing drizzle
        if(code===61) return "󰖗"                                                  // slight rain
        if(code<=63)  return "󰖖"                                                  // moderate rain
        if(code<=65)  return "󰙾"                                                  // heavy rain
        if(code<=67)  return "󰙿"                                                  // freezing rain
        if(code===77) return "󰖘"                                                  // snow grains
        if(code<=77)  return "󰜗"                                                  // snow
        if(code<=82)  return "󰙾"                                                  // rain showers
        if(code<=86)  return "󰼶"                                                  // snow showers
        if(code<=99)  return "󰖓"                                                  // thunderstorm
        return "󰖐"                                                                 // unknown
    }

    function _updateWeatherDisplay() {
        root.weatherIcon = root.wmoIcon(root._wxCode, root._wxIsDay, root._wxHumidity)
        if (root._wxTempC === 0 && root._wxCode === 0 && root._wxHumidity === 0) {
            root.weatherTemp = "--°"; return
        }
        if (root.weatherUnit === "imperial") {
            root.weatherTemp = Math.round(root._wxTempC * 9/5 + 32) + "°F"
        } else {
            root.weatherTemp = Math.round(root._wxTempC) + "°C"
        }
    }
    Process {
        id:wxProc; property var _b:[]
        command:["bash","-c",
            "WF=/tmp/astal-weather-cache.json; LF=/tmp/waybar-weather-ipinfo.json; " +
            "AGE=$(($(date +%s)-$(stat -c%Y \"$WF\" 2>/dev/null||echo 0))); " +
            "[ -f \"$WF\" ]&&[ $AGE -lt 300 ]&&{ cat \"$WF\"; exit 0; }; " +
            "[ -f \"$LF\" ]&&LOC=$(jq -r '.loc//\"0,0\"' \"$LF\" 2>/dev/null)||LOC=$(curl -sf --max-time 5 'https://ipinfo.io/json'|jq -r '.loc//\"0,0\"'); " +
            "LAT=${LOC%,*}; LON=${LOC#*,}; " +
            "curl -sf --max-time 12 \"https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,relative_humidity_2m,is_day,weather_code&timezone=auto\" -o \"$WF\" 2>/dev/null&&cat \"$WF\""]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){ wxProc._b.push(l) } }
        onRunningChanged: if(running) _b=[]
        onExited: function(){
            try {
                const w = JSON.parse(_b.join(""))
                if (w.current) {
                    root._wxTempC    = w.current.temperature_2m    || 0
                    root._wxCode     = w.current.weather_code      || 0
                    root._wxIsDay    = (w.current.is_day !== undefined ? w.current.is_day : 1)
                    root._wxHumidity = w.current.relative_humidity_2m || 0
                    root._updateWeatherDisplay()
                }
            } catch(e) {}
            _b=[]
        }
        Component.onCompleted: running=true
    }
    Timer { interval:300000; repeat:true; running:true; onTriggered:if(!wxProc.running) wxProc.running=true }

    // ── System monitor ────────────────────────────────────────────────────────
    property real cpuUsage:0; property real memUsage:0; property real tempC:0; property bool tempOk:false
    Behavior on cpuUsage { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    Behavior on memUsage { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    Behavior on tempC    { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    property var _prevCpu: null
    Process {
        id:sysProc; property var _b:[]
        command:["bash","-c",
            "head -1 /proc/stat; " +
            "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; " +
            "for z in /sys/class/thermal/thermal_zone*/; do " +
            "  t=$(cat \"$z/temp\" 2>/dev/null); y=$(cat \"$z/type\" 2>/dev/null); " +
            "  [ -n \"$t\" ]&&echo \"$y:$t\"; done"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){sysProc._b.push(l.trim())} }
        onRunningChanged: if(running) _b=[]
        onExited: function(){
            const lines=_b.slice(); _b=[]
            const cm=lines[0]?lines[0].match(/cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/):null
            if(cm){ const u=+cm[1],n=+cm[2],s=+cm[3],i=+cm[4],cur={total:u+n+s+i,idle:i}
                if(root._prevCpu){ const dt=cur.total-root._prevCpu.total,di=cur.idle-root._prevCpu.idle; if(dt>0) root.cpuUsage=(dt-di)/dt }
                root._prevCpu=cur }
            let mi={}; for(const l of lines){ const mm=l.match(/^(\w+):\s*(\d+)\s*kB/); if(mm) mi[mm[1]]=parseInt(mm[2])*1024 }
            if(mi.MemTotal&&mi.MemAvailable) root.memUsage=(mi.MemTotal-mi.MemAvailable)/mi.MemTotal
            let found=false
            for(const l of lines){
                const tm=l.match(/^([^:]+):(\d+)$/)
                if(!tm) continue
                const v=parseInt(tm[2])/1000, type=tm[1].toLowerCase()
                if(v>0&&v<120&&(type.includes("x86")||type.includes("pkg"))){
                    root.tempC=v; root.tempOk=true; found=true; break }
            }
            if(!found) for(const l of lines){
                const tm=l.match(/^([^:]+):(\d+)$/)
                if(!tm) continue
                const v=parseInt(tm[2])/1000
                if(v>20&&v<120){ root.tempC=v; root.tempOk=true; break }
            }
        }
    }
    Timer { interval:1500; repeat:true; running:true; onTriggered:if(!sysProc.running) sysProc.running=true
        Component.onCompleted: sysProc.running=true
    }

    // ── Media ─────────────────────────────────────────────────────────────────
    property string mediaStatus:"Stopped"; property string mediaTitle:"No media"
    property string mediaArtist:""; property string mediaArtUrl:""
    property string _circularArtPath: ""
    property string mediaShuffleStatus: "off"   // off | on  (lowercase)
    property string mediaLoopStatus:    "none"  // none | track | playlist  (lowercase)
    property real   mediaPosition: 0            // seconds
    property real   mediaDuration: 0            // seconds
    property real   _posTimestamp: 0             // Date.now() of last position update

    Process {
        id:mediaProc
        command:["playerctl","-F","metadata","--format","{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}\t{{shuffle}}\t{{loop}}"]
        stdout: SplitParser {
            splitMarker:"\n"
            onRead: function(l){
                const p=l.split("\t")
                if(p.length>=6){
                    root.mediaStatus=p[0].trim()||"Stopped"
                    const newUrl=p[1].trim()
                    if(newUrl!==root.mediaArtUrl){
                        root.mediaArtUrl=newUrl
                        root._circularArtPath=""
                        if(newUrl) artConvProc.launch(newUrl)
                    }
                    root.mediaTitle=p[2].trim()||"No media"
                    root.mediaArtist=p[3].trim()
                    root.mediaShuffleStatus = (p[4].trim()||"off").toLowerCase()
                    root.mediaLoopStatus    = (p[5].trim()||"none").toLowerCase()
                }
            }
        }
        Component.onCompleted: running=true
    }

    // ── Position/duration — pipe-delimited for reliable parsing ───────────
    Process {
        id: posProc
        property string _line: ""
        command: ["bash", "-c", "printf '%s|%s\\n' \"$(playerctl position 2>/dev/null)\" \"$(playerctl metadata mpris:length 2>/dev/null)\""]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l){ if(l.trim()) posProc._line = l.trim() } }
        onRunningChanged: if(running) _line = ""
        onExited: function() {
            const parts = _line.split("|")
            if (parts.length >= 2) {
                const pos = parseFloat(parts[0])
                const dur = parseFloat(parts[1]) / 1000000.0
                if (!isNaN(pos) && pos >= 0) { root.mediaPosition = pos; root._posTimestamp = Date.now() }
                if (!isNaN(dur) && dur > 0)   root.mediaDuration = dur
            }
            _line = ""
        }
    }
    // Poll every second while Playing
    Timer {
        interval: 1000; repeat: true
        running: root.mediaStatus === "Playing"
        onTriggered: if (!posProc.running) posProc.running = true
        Component.onCompleted: posProc.running = true
    }
    // Smooth interpolation between polls — advance position by wall-clock elapsed time
    Timer {
        interval: 250; repeat: true
        running: root.mediaStatus === "Playing" && root.mediaDuration > 0 && root._posTimestamp > 0
        onTriggered: {
            const now = Date.now()
            const elapsed = (now - root._posTimestamp) / 1000.0
            root._posTimestamp = now
            root.mediaPosition = Math.min(root.mediaPosition + elapsed, root.mediaDuration)
        }
    }

    // ── Seek ─────────────────────────────────────────────────────────────────
    Process {
        id: seekProc
        property string _cmd: "true"
        command: ["bash", "-c", seekProc._cmd]
        function seek(secs) { _cmd = "playerctl position " + secs.toFixed(1); if(!running) running = true }
    }

    // ── Cava bridge: root-level string updated by lockCavaProc ───────────────
    // Because pragma ComponentBehavior: Bound prevents the process (root scope)
    // from directly accessing Canvas IDs inside the WlSessionLockSurface delegate.
    property string _cavaRaw: ""

    // Radial cava — 64 bars
    Process {
        id: lockCavaProc
        command: {
            const bars = 64
            const maxR = 7
            const cfgPath = "/tmp/qs-lock-cava.ini"
            const lines = [
                "[general]",
                "bars = " + bars,
                "framerate = 60",
                "",
                "[output]",
                "method = raw",
                "raw_target = /dev/stdout",
                "data_format = ascii",
                "ascii_max_range = " + maxR,
                "channels = mono"
            ]
            const quoted = lines.map(l => JSON.stringify(l)).join(" ")
            return ["bash","-c","printf '%s\\n' " + quoted + " > " + cfgPath + " && cava -p " + cfgPath]
        }
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if(!t || t.startsWith("[")) return
                root._cavaRaw = t        // bridge into the UI via root property
            }
        }
        onExited: cavRestartTimer.restart()
    }
    Timer { id:cavRestartTimer; interval:2000; repeat:false
        onTriggered: if(!lockCavaProc.running) lockCavaProc.running = true }

    Connections {
        target: root
        function onMediaStatusChanged() {
            if(root.mediaStatus === "Playing") {
                if(!lockCavaProc.running) lockCavaProc.running = true
            } else {
                lockCavaProc.running = false
                root._cavaRaw = ""
            }
        }
    }

    // ── Art conversion ───────────────────────────────────────────────────────
    Process {
        id:artConvProc
        property string _dst: "/tmp/qs_art_circle.png"
        property string _cmd: "true"
        command:["bash","-c", artConvProc._cmd]
        function launch(url) {
            const src = url.startsWith("file://") ? url.substring(7) : url
            _cmd = "SRC='" + src.replace(/'/g,"'\\''") + "'; " +
                   "DST='" + _dst + "'; " +
                   "[ -f \"$SRC\" ] || { curl -sf --max-time 10 \"$SRC\" -o /tmp/qs_art_raw.png 2>/dev/null && SRC=/tmp/qs_art_raw.png; }; " +
                   "magick \"$SRC\" " +
                   "  -resize 192x192^ -gravity center -extent 192x192 " +
                   "  \\( +clone -alpha extract " +
                   "     -fill black -colorize 100 " +
                   "     -fill white -draw 'circle 96,96 96,0' \\) " +
                   "  -alpha off -compose CopyOpacity -composite " +
                   "  -strip \"$DST\""
            running = true
        }
        onExited: function(code){
            if(code===0) root._circularArtPath = _dst + "?" + Date.now()
        }
    }

    // ── User icon ─────────────────────────────────────────────────────────────
    property string _userIconPath: ""
    Process {
        id:iconConvProc
        property string _dst: "/tmp/qs_user_circle.png"
        property string _src: Quickshell.env("HOME")+"/.config/hyprcandy/user-icon.png"
        command:["bash","-c",
            "SRC='" + iconConvProc._src + "'; " +
            "DST='" + iconConvProc._dst + "'; " +
            "[ -f \"$SRC\" ] || exit 1; " +
            "magick \"$SRC\" " +
            "  -resize 192x192^ -gravity center -extent 192x192 " +
            "  \\( +clone -alpha extract " +
            "     -fill black -colorize 100 " +
            "     -fill white -draw 'circle 96,96 96,0' \\) " +
            "  -alpha off -compose CopyOpacity -composite " +
            "  -strip \"$DST\""]
        onExited: function(code){
            if(code===0) root._userIconPath = iconConvProc._dst + "?" + Date.now()
        }
        Component.onCompleted: running=true
    }

    // ── Player controls ───────────────────────────────────────────────────────
    // Fix: set command directly on each call instead of relying on a bound property.
    Process { id:ctlProc; running:false; onExited: running=false }
    Process { id:pwrProc;  running:false; onExited: running=false }
    property bool _hibernateAvailable: false
    Process {
        id: _hibCheckProc
        // systemd exposes hibernate as a sleep state only when swap/hibernation is configured
        command: ["bash","-c","grep -qw hibernate /sys/power/state 2>/dev/null && echo yes || echo no"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { root._hibernateAvailable = line.trim() === "yes" }
        }
        onExited: running = false
    }
    Process {
        id: suspendIfFlagged
        command: ["/bin/bash", "-c",
            "f=/tmp/.qs-candylock-sleep; [ -f \"$f\" ] && rm -f \"$f\" && systemctl suspend"]
        running: false
        onExited: running = false
    }
    function playerAction(cmd) {
        let argv
        if(cmd === "shuffle") {
            argv = ["playerctl","shuffle","toggle"]
        } else if(cmd === "loop") {
            const order = ["none","track","playlist"]
            const names = ["None","Track","Playlist"]
            const cur   = Math.max(0, order.indexOf(root.mediaLoopStatus))
            argv = ["playerctl","loop", names[(cur + 1) % 3]]
        } else {
            argv = ["playerctl", cmd]
        }
        ctlProc.command = argv
        if(!ctlProc.running) ctlProc.running = true
    }

    // ── Session lock ──────────────────────────────────────────────────────────
    WlSessionLock { id:sessionLock
        locked: false
        Component.onCompleted: locked = true
        onLockedChanged: if (locked) suspendIfFlagged.running = true
        WlSessionLockSurface {
            Rectangle {
                id:mainRect; anchors.fill:parent; color:root.cBg; focus:true
                Keys.onPressed: function(ev){ if(!ev.isAutoRepeat) pinInput.forceActiveFocus() }

                // Wallpaper
                AnimatedImage {
                    id:wallImg
                    anchors.fill:parent
                    source: root.wallpaperPath?"file://"+root.wallpaperPath:""
                    fillMode:Image.PreserveAspectCrop; smooth:true; cache:true; playing:true; asynchronous:true
                    visible: root.wallpaperPath!==""
                }

                Item {
                    id:centerPanel
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter:   parent.verticalCenter
                    anchors.verticalCenterOffset: -36
                    width:660
                    height:panelCol.implicitHeight+42

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled:      true
                        maskSource:       roundMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin:  1.0
                    }

                    Rectangle {
                        id: roundMask
                        anchors.fill: parent
                        radius: 32; color: "white"; opacity: 0
                        layer.enabled: true
                    }

                    Item {
                        anchors.fill:parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect { blurEnabled:true; blur:1.0; blurMax:64 }
                        AnimatedImage {
                            x: -centerPanel.x; y: -centerPanel.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath?"file://"+root.wallpaperPath:""
                            fillMode:Image.PreserveAspectCrop; smooth:true; playing:true; cache:true
                            visible: root.wallpaperPath!==""
                        }
                    }

                    Rectangle {
                        anchors.fill:parent; radius:32; color:root.cPanel
                        border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.1)
                    }

                    ColumnLayout {
                        id:panelCol
                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:24 }
                        spacing:10

                        // ══════ ROW 1: clock card  |  info + pin card ══════════
                        RowLayout {
                            Layout.fillWidth:true; spacing:14

                            // ── CLOCK CARD ──────────────────────────────────────
                            Rectangle {
                                id:clockCard
                                Layout.preferredWidth:148
                                Layout.preferredHeight:rightCol.implicitHeight
                                radius:20; color:root.cCardDark
                                border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                ColumnLayout {
                                    anchors.centerIn:parent; spacing:0
                                    Text {
                                        Layout.alignment:Qt.AlignHCenter
                                        text:root.clockHour; color:Qt.rgba(root.cSecondaryContainer.r, root.cSecondaryContainer.g, root.cSecondaryContainer.b, 1.00)
                                        font.family:"C059"; font.pixelSize:86; font.italic:true; font.weight:Font.Bold
                                        lineHeight:0.88
                                    }
                                    Text {
                                        Layout.alignment:Qt.AlignHCenter
                                        text:"󰫢  󰫢"; color:root.cTertiary
                                        font.family:"codicon"; font.pixelSize:14
                                        topPadding:8; bottomPadding:8
                                    }
                                    Text {
                                        Layout.alignment:Qt.AlignHCenter
                                        text:root.clockMin; color:root.cSecondary
                                        font.family:"C059"; font.pixelSize:86; font.italic:true; font.weight:Font.Bold
                                        lineHeight:0.88
                                    }
                                }
                            }

                            // ── RIGHT COLUMN ─────────────────────────────────────
                            ColumnLayout {
                                id:rightCol
                                Layout.fillWidth:true; spacing:10

                                Rectangle {
                                    id:infoCard
                                    Layout.fillWidth:true
                                    height:infoCardCol.implicitHeight+36
                                    radius:20; color:root.cCardWarm
                                    border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                    ColumnLayout {
                                        id:infoCardCol
                                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:20 }
                                        spacing:14

                                        Text {
                                            Layout.fillWidth:true
                                            text:root.clockDate; color:Qt.rgba(root.cPrimaryContainer.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 1.00)
                                            font.family:"C059"; font.pixelSize:30; font.italic:true; font.weight:Font.DemiBold
                                            horizontalAlignment:Text.AlignHCenter
                                        }

                                        RowLayout {
                                            Layout.fillWidth:true; spacing:20; Layout.alignment:Qt.AlignHCenter

                                            Item {
                                                width:88; height:88
                                                Image {
                                                    id:userImg; anchors.fill:parent
                                                    source: root._userIconPath!=="" ? ("file://"+root._userIconPath.split("?")[0]+"?v="+root._userIconPath.split("?")[1]) : ""
                                                    fillMode:Image.PreserveAspectFit; smooth:true; cache:false
                                                    visible:status===Image.Ready
                                                }
                                                Rectangle {
                                                    anchors.fill:parent; radius:44; color:root.cSurfHi
                                                    visible:userImg.status!==Image.Ready
                                                    Text { anchors.centerIn:parent; text:"󰀄"; font.pixelSize:40; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar }
                                                }
                                                Rectangle {
                                                    anchors.fill:parent; radius:44; color:"transparent"
                                                    border.width:2; border.color:Qt.rgba(root.cSecondary.r,root.cSecondary.g,root.cSecondary.b,0.60)
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth:true; spacing:4; Layout.alignment:Qt.AlignVCenter
                                                Text {
                                                    Layout.alignment:Qt.AlignHCenter
                                                    text:root.weatherTemp; color:root.cSecondary; opacity:0.90
                                                    font.family:"C059"; font.pixelSize:24; font.italic:true; font.weight:Font.DemiBold
                                                }
                                                Text {
                                                    Layout.alignment:Qt.AlignHCenter
                                                    text:root.weatherIcon; color:root.cSecondary; opacity:0.90
                                                    font.pixelSize:24; font.family:"Symbols Nerd Font Mono"
                                                }
                                            }
                                        }

                                        Rectangle {
                                            Layout.fillWidth:true; height:1
                                            color:Qt.rgba(root.cSecondary.r, root.cSecondary.g, root.cSecondary.b, 0.30)
                                        }

                                        // PIN ENTRY
                                        Item {
                                            Layout.alignment:Qt.AlignHCenter; width:220; height:44
                                            Rectangle {
                                                anchors.fill:parent; radius:22
                                                color:Qt.rgba(root.cBg.r,root.cBg.g,root.cBg.b,0.75)
                                                border.width:2
                                                border.color: root.authFailed ? root.cErr
                                                    : (root.authChecking
                                                        ? Qt.rgba(root.cPrimaryContainer.r,root.cPrimaryContainer.g,root.cPrimaryContainer.b,0.40)
                                                        : Qt.rgba(root.cPrimaryContainer.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 1.00))
                                                Behavior on border.color { ColorAnimation{duration:250} }
                                            }
                                            RowLayout {
                                                anchors.centerIn:parent; spacing:7
                                                visible:root.pinEntry.length===0 && !root.authChecking
                                                Text { text:"󰀄"; font.family:"Symbols Nerd Font Mono"; font.pixelSize:14; color:Qt.rgba(root.cPrimaryContainer.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 1.00) }
                                                Text { text:Quickshell.env("USER"); font.family:"C059"; font.pixelSize:14; font.italic:true; color:root.cSecondary; opacity:1.00 }
                                            }
                                            Text {
                                                anchors.centerIn:parent; visible:root.authChecking
                                                text:"󰶘"; font.family:"Symbols Nerd Font Mono"; font.pixelSize:18; color:Qt.rgba(root.cPrimaryContainer.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 1.00)
                                                RotationAnimator on rotation { from:0; to:360; duration:900; loops:Animation.Infinite; running:root.authChecking }
                                            }
                                            Row {
                                                anchors.centerIn:parent; spacing:6
                                                visible:root.pinEntry.length>0 && !root.authChecking
                                                Repeater { model:root.pinEntry.length; delegate:Rectangle{width:9;height:9;radius:5;color:root.cSecondary;opacity:0.90} }
                                            }
                                        }

                                        Text {
                                            Layout.alignment:Qt.AlignHCenter
                                            text:root.authFailed?"Wrong password":""
                                            color:root.cErr; font.pixelSize:11; font.italic:true
                                            opacity:root.authFailed?1:0
                                            Behavior on opacity { NumberAnimation{duration:200} }
                                        }
                                    }
                                }
                            }
                        }

                        // ══════ ROW 2: compact media card | dials card ══════════
                        RowLayout {
                            Layout.fillWidth:true; spacing:14; Layout.bottomMargin:4

                            // ── MEDIA CARD — compact horizontal layout ────────────
                            Rectangle {
                                Layout.fillWidth:true
                                height: mediaCardRow.implicitHeight + 28
                                radius:20; color:root.cCardWarm
                                border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                // ── LEFT: info + progress + controls ───────────────
                                RowLayout {
                                    id: mediaCardRow
                                    anchors { left:parent.left; right:parent.right; top:parent.top; margins:14 }
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        // Title
                                        Text {
                                            Layout.fillWidth:true
                                            text: root.mediaTitle; color: root.cOnSurf
                                            font.pixelSize:13; font.weight:Font.DemiBold
                                            elide:Text.ElideRight
                                        }
                                        // Artist
                                        Text {
                                            Layout.fillWidth:true
                                            text: root.mediaArtist; color: root.cOnSurfVar
                                            font.pixelSize:11; elide:Text.ElideRight
                                            visible: text !== ""
                                        }

                                        // ── Progress / seek bar ───────────────────────
                                        Item {
                                            id: seekBarItem
                                            Layout.fillWidth: true
                                            height: 28
                                            visible: root.mediaDuration > 0

                                            property bool  _drag:     false
                                            property real  _dragNorm: 0
                                            readonly property real _norm: root.mediaDuration > 0
                                                ? (_drag ? _dragNorm
                                                         : Math.max(0, Math.min(1, root.mediaPosition / root.mediaDuration)))
                                                : 0

                                            function _fmt(s) {
                                                const m = Math.floor(s / 60)
                                                const ss = Math.floor(s % 60)
                                                return m + ":" + (ss < 10 ? "0" : "") + ss
                                            }

                                            // Time labels
                                            Text {
                                                anchors.left: parent.left; anchors.top: parent.top
                                                text: seekBarItem._fmt(seekBarItem._drag ? seekBarItem._dragNorm * root.mediaDuration : root.mediaPosition)
                                                color: root.cOnSurfVar; font.pixelSize: 9
                                            }
                                            Text {
                                                anchors.right: parent.right; anchors.top: parent.top
                                                text: seekBarItem._fmt(root.mediaDuration)
                                                color: root.cOnSurfVar; font.pixelSize: 9
                                            }

                                            // Trough
                                            Item {
                                                id: trough
                                                anchors.bottom: parent.bottom
                                                anchors.left: parent.left; anchors.right: parent.right
                                                height: 14

                                                Rectangle {
                                                    anchors.fill: parent; radius: 7
                                                    color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.28)
                                                    border.width: 1
                                                    border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.45)
                                                }

                                                // Gradient fill
                                                Item {
                                                    x: 3; y: 3
                                                    width:  Math.max(0, (trough.width - 6) * seekBarItem._norm)
                                                    height: 8
                                                    clip: true
                                                    Rectangle {
                                                        width:  trough.width - 6
                                                        height: 8; radius: 4
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop { position: 0.0; color: root.cInvPrimary }
                                                            GradientStop { position: 1.0; color: root.cOnSecondary }
                                                        }
                                                    }
                                                }

                                                // Thumb
                                                Text {
                                                    text: "󰟃"
                                                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: 10
                                                    color: root.cPrimary
                                                    style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.25)
                                                    x: {
                                                        const tw = trough.width - 6
                                                        const cx = 3 + tw * seekBarItem._norm - implicitWidth / 2
                                                        return Math.max(1, Math.min(trough.width - implicitWidth - 1, cx))
                                                    }
                                                    y: (trough.height - implicitHeight) / 2
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    preventStealing: true
                                                    function _n(mx) { return Math.max(0, Math.min(1, mx / trough.width)) }
                                                    onPressed:         function(m) { seekBarItem._drag = true;  seekBarItem._dragNorm = _n(m.x) }
                                                    onPositionChanged: function(m) { if(pressed) seekBarItem._dragNorm = _n(m.x) }
                                                    onReleased:        function(m) {
                                                        seekBarItem._dragNorm = _n(m.x)
                                                        seekBarItem._drag = false
                                                        seekProc.seek(_n(m.x) * root.mediaDuration)
                                                    }
                                                    onWheel: function(e) {
                                                        const d = (e.angleDelta.y > 0 ? 1 : -1) * 5
                                                        seekProc.seek(Math.max(0, Math.min(root.mediaDuration, root.mediaPosition + d)))
                                                    }
                                                }
                                            }
                                        }

                                        // ── Controls ──────────────────────────────────
                                        RowLayout {
                                            spacing: 6

                                            Repeater {
                                                model: [
                                                    // shuffle — 󰒞 icon; active when shuffling
                                                    { i:"󰒞",  c:"shuffle",    a: root.mediaShuffleStatus === "on" },
                                                    { i:"󰒮",  c:"previous",   a: false },
                                                    { i: root.mediaStatus === "Playing" ? "󰏤" : "󰐊", c:"play-pause", a: false },
                                                    { i:"󰒭",  c:"next",       a: false },
                                                    // loop: none→󰑗  track→󰑘  playlist→󰑖
                                                    { i: root.mediaLoopStatus === "track" ? "󰑘"
                                                           : (root.mediaLoopStatus === "playlist" ? "󰑖" : "󰑗"),
                                                      c:"loop",
                                                      a: root.mediaLoopStatus !== "none" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    width:30; height:30; radius:6
                                                    readonly property bool isCenter: index === 2
                                                    readonly property bool isActive: modelData.a
                                                    color: bma.containsMouse
                                                        ? (isActive
                                                            ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.25)
                                                            : (isCenter
                                                                ? Qt.rgba(root.cOnSurf.r,root.cOnSurf.g,root.cOnSurf.b,0.22)
                                                                : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18)))
                                                        : (isActive
                                                            ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.15)
                                                            : "transparent")
                                                    border.width: isActive ? 2 : 1
                                                    border.color: isActive
                                                        ? root.cPrimary
                                                        : (isCenter
                                                            ? Qt.rgba(root.cOnSurf.r,root.cOnSurf.g,root.cOnSurf.b,0.65)
                                                            : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.50))
                                                    Behavior on color { ColorAnimation{duration:100} }
                                                    Text {
                                                        anchors.centerIn:parent
                                                        text: modelData.i; font.pixelSize:14; font.family:"Symbols Nerd Font Mono"
                                                        color: bma.containsMouse || parent.isActive
                                                            ? (isCenter ? root.cOnSurf : root.cPrimary)
                                                            : root.cOnSurfVar
                                                        Behavior on color { ColorAnimation{duration:100} }
                                                    }
                                                    MouseArea { id:bma; anchors.fill:parent; hoverEnabled:true; onClicked: root.playerAction(modelData.c) }
                                                }
                                            }
                                        }
                                    }

                                    // ── RIGHT: spinning disc + radial cava ─────────
                                    Item {
                                        width: 170; height: 170
                                        Layout.alignment: Qt.AlignVCenter

                                        // Radial cava canvas — reacts to root._cavaRaw
                                        Canvas {
                                            id: radialCava
                                            anchors.fill: parent
                                            visible: root.mediaStatus === "Playing"
                                            property var _bars: []
                                            property int _barCount: 64

                                            // Watch the root bridge property
                                            Connections {
                                                target: root
                                                function on_CavaRawChanged() {
                                                    if(!root._cavaRaw || !radialCava.visible) return
                                                    const vals = root._cavaRaw.split(";")
                                                    radialCava._bars = []
                                                    for(let i = 0; i < radialCava._barCount; i++) {
                                                        const v = parseInt(vals[i % vals.length])
                                                        radialCava._bars.push(isNaN(v) ? 0 : v / 7.0)
                                                    }
                                                    radialCava.requestPaint()
                                                }
                                            }

                                            onPaint: {
                                                const ctx = getContext("2d")
                                                ctx.reset()
                                                const cx = width / 2, cy = height / 2
                                                const innerR = 52   // 92/2 + 2px gap
                                                const maxBarH = 28  // slim + long like media.js

                                                for(let i = 0; i < _barCount; i++) {
                                                    const amp = _bars[i] || 0
                                                    if(amp < 0.01) continue
                                                    const angle = (i / _barCount) * Math.PI * 2 - Math.PI / 2
                                                    const barH  = 2 + amp * (maxBarH - 2)   // 2px baseline above disc
                                                    ctx.beginPath()
                                                    ctx.strokeStyle = Qt.rgba(root.cPrimary.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 0.40 + amp * 1.00)
                                                    ctx.lineWidth = 1.5
                                                    ctx.lineCap   = "round"
                                                    ctx.moveTo(cx + Math.cos(angle) * innerR,            cy + Math.sin(angle) * innerR)
                                                    ctx.lineTo(cx + Math.cos(angle) * (innerR + barH),   cy + Math.sin(angle) * (innerR + barH))
                                                    ctx.stroke()
                                                }
                                            }
                                        }

                                        // Spinning disc — 92px, centered inside 140px item
                                        Rectangle {
                                            id: artDisc
                                            anchors.centerIn: parent
                                            width: 92; height: 92
                                            radius: 46; color: root.cSurfHi
                                            antialiasing: true
                                            layer.enabled: true
                                            layer.smooth: true

                                            Image {
                                                id: artImg
                                                anchors.fill: parent
                                                source: root._circularArtPath !== ""
                                                    ? ("file://" + root._circularArtPath.split("?")[0] + "?v=" + root._circularArtPath.split("?")[1])
                                                    : ""
                                                fillMode: Image.PreserveAspectCrop
                                                smooth: true; cache: false
                                                visible: root._circularArtPath !== "" && status === Image.Ready
                                            }
                                            Text {
                                                anchors.centerIn: parent; visible: !artImg.visible
                                                text: "󰽲"; font.pixelSize:32; font.family:"Symbols Nerd Font Mono"
                                                color: root.cOnSurfVar; opacity: 0.35
                                            }
                                            RotationAnimator on rotation {
                                                from:0; to:360; duration:16000
                                                loops:Animation.Infinite
                                                running: root.mediaStatus === "Playing"
                                            }
                                        }
                                    }
                                }
                            }

                            // ── DIALS CARD ──────────────────────────────────────
                            Rectangle {
                                id:dialsCard
                                Layout.preferredWidth:116
                                Layout.topMargin: 12
                                height:dialsCol.implicitHeight + 32
                                radius:20; color:root.cCardDark
                                border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                ColumnLayout {
                                    id:dialsCol
                                    anchors { left:parent.left; right:parent.right; top:parent.top; bottom:parent.bottom; margins:14 }
                                    spacing:8

                                    Repeater {
                                        model:3
                                        delegate: Item {
                                            required property int index
                                            readonly property real arcVal: index===0 ? root.cpuUsage
                                                : (index===1 ? root.memUsage
                                                : (root.tempOk ? Math.min(root.tempC/100,1) : 0))
                                            readonly property string arcText: index===0 ? Math.round(root.cpuUsage*100)+"%"
                                                : (index===1 ? Math.round(root.memUsage*100)+"%"
                                                : (root.tempOk ? Math.round(root.tempC)+"°" : "N/A"))
                                            readonly property string arcGlyph: index===0?"󰻠":(index===1?"󰍛":"󰔏")
                                            readonly property string arcLabel: index===0?"CPU":(index===1?"RAM":"Temp")
                                            readonly property color arcColor: index===0 ? Qt.rgba(root.cPrimary.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 1.00)
                                                : (index===1 ? root.cTertiary : root.cSecondary)

                                            Layout.fillWidth:true; Layout.fillHeight:true; Layout.minimumHeight:88

                                            Canvas {
                                                id:arcC
                                                anchors.horizontalCenter:parent.horizontalCenter
                                                anchors.top:parent.top
                                                anchors.topMargin: Math.max(0,(parent.height-72-14)/2)
                                                width:72; height:72
                                                property color dialCol: parent.arcColor
                                                property color onS:     root.cOnSurf
                                                property real  cv:      parent.arcVal
                                                property string gt:     parent.arcText
                                                property string gl:     parent.arcGlyph
                                                onDialColChanged: requestPaint(); onOnSChanged: requestPaint()
                                                onCvChanged: requestPaint(); onGtChanged: requestPaint()
                                                Component.onCompleted: requestPaint()
                                                onPaint: {
                                                    const ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                                                    const cx=width/2,cy=height/2,r=27,lw=5
                                                    const s=0.75*Math.PI,e=2.25*Math.PI
                                                    ctx.lineWidth=lw; ctx.lineCap="round"
                                                    ctx.beginPath(); ctx.arc(cx,cy,r,s,e)
                                                    ctx.strokeStyle=Qt.rgba(onS.r,onS.g,onS.b,0.12).toString(); ctx.stroke()
                                                    if(cv>0.005){
                                                        ctx.beginPath(); ctx.arc(cx,cy,r,s,s+cv*(e-s))
                                                        ctx.strokeStyle=dialCol.toString(); ctx.stroke()
                                                    }
                                                    ctx.fillStyle=Qt.rgba(dialCol.r,dialCol.g,dialCol.b,0.92).toString()
                                                    ctx.font="15px 'Symbols Nerd Font Mono'"
                                                    ctx.textAlign="center"; ctx.textBaseline="alphabetic"
                                                    ctx.fillText(gl,cx,cy+2)
                                                    ctx.fillStyle=Qt.rgba(onS.r,onS.g,onS.b,0.88).toString()
                                                    ctx.font="bold 9px monospace"
                                                    ctx.textBaseline="top"; ctx.fillText(gt,cx,cy+5)
                                                }
                                            }
                                            Text {
                                                anchors.horizontalCenter:parent.horizontalCenter
                                                anchors.bottom:parent.bottom
                                                text:parent.arcLabel; color:root.cOnSurfVar; font.pixelSize:9
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // ── Power buttons row — floats centered below main panel ────────
                Item {
                    id: powerRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top:             centerPanel.bottom
                    anchors.topMargin:       10
                    width:  pwrRowInner.implicitWidth  + 32
                    height: pwrRowInner.implicitHeight + 20

                    // Frosted pill backdrop
                    // Pill mask for clipping blur + tint
                    Rectangle {
                        id: pwrMask
                        anchors.fill: parent; radius: height / 2
                        color: "white"; visible: false; layer.enabled: true
                    }

                    // Blurred wallpaper slice (same technique as centerPanel)
                    Item {
                        anchors.fill: parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
                        layer.smooth: true
                        AnimatedImage {
                            x: -powerRow.x; y: -powerRow.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
                            fillMode: Image.PreserveAspectCrop; smooth: true; playing: true; cache: true
                            visible: root.wallpaperPath !== ""
                        }
                    }

                    // inversePrimary tint overlay
                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: Qt.rgba(root.cInvPrimary.r, root.cInvPrimary.g, root.cInvPrimary.b, 0.65)
                        border.width: 1
                        border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.18)
                    }

                    // Clip pill so blur doesn't leak outside rounded corners
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled:      true
                        maskSource:       pwrMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin:  1.0
                    }

                    Row {
                        id: pwrRowInner
                        anchors.centerIn: parent
                        spacing: 4
                        // ── Suspend ──────────────────────────────────────────
                        Item {
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maSusp.containsMouse ? Qt.rgba(root.cSecondary.r,root.cSecondary.g,root.cSecondary.b,0.20) : "transparent"
                                border.width: 1
                                border.color: _maSusp.containsMouse ? Qt.rgba(root.cSecondary.r,root.cSecondary.g,root.cSecondary.b,0.45) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰒲"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: root.cSecondary; opacity: _maSusp.containsMouse ? 1.0 : 0.72
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maSusp; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","suspend"]; pwrProc.running = true }
                            }
                        }

                        // ── Hibernate (only shown when available on this OS) ──
                        Item {
                            width: 44; height: 44
                            visible: root._hibernateAvailable
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maHib.containsMouse ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.20) : "transparent"
                                border.width: 1
                                border.color: _maHib.containsMouse ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰈉"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: root.cPrimary; opacity: _maHib.containsMouse ? 1.0 : 0.72
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maHib; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","hibernate"]; pwrProc.running = true }
                            }
                        }

                        // ── Reboot ───────────────────────────────────────────
                        Item {
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maRebt.containsMouse ? Qt.rgba(root.cTertiary.r,root.cTertiary.g,root.cTertiary.b,0.20) : "transparent"
                                border.width: 1
                                border.color: _maRebt.containsMouse ? Qt.rgba(root.cTertiary.r,root.cTertiary.g,root.cTertiary.b,0.45) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰑙"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: root.cTertiary; opacity: _maRebt.containsMouse ? 1.0 : 0.72
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maRebt; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","reboot"]; pwrProc.running = true }
                            }
                        }

                        // ── Shutdown ─────────────────────────────────────────
                        Item {
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maShut.containsMouse ? Qt.rgba(root.cPrimary.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 0.20) : "transparent"
                                border.width: 1
                                border.color: _maShut.containsMouse ? Qt.rgba(root.cPrimary.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 0.45) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰐥"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: Qt.rgba(root.cPrimary.r, root.cPrimaryContainer.g, root.cPrimaryContainer.b, 1.00); opacity: _maShut.containsMouse ? 1.0 : 0.72
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maShut; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","poweroff"]; pwrProc.running = true }
                            }
                        }
                    }
                }

                // Hidden TextInput for PIN
                TextInput {
                    id:pinInput; visible:false; focus:true; echoMode:TextInput.Password
                    onTextChanged: root.pinEntry=text
                    Connections {
                        target:root
                        function onPinEntryChanged(){ if(root.pinEntry===""&&pinInput.text!=="") pinInput.clear() }
                        function onFocusPinRequestChanged(){ pinInput.forceActiveFocus() }
                    }
                    Keys.onReturnPressed: root.submitPin()
                    Keys.onEnterPressed:  root.submitPin()
                    Keys.onEscapePressed: { pinInput.clear(); root.pinEntry="" }
                    Component.onCompleted: forceActiveFocus()
                }
            }
        }
    }
}
