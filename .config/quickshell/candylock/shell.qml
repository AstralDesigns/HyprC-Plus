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
    property string _m3primary:              "#f7af91"
    property string _m3onPrimary:            "#170700"
    property string _m3background:           "#170700"
    property string _m3inversePrimary:       "#6f2900"
    property string _m3surfaceContainerHigh: "#1e1613"
    property string _m3onSurface:            "#f8dfd5"
    property string _m3onSurfaceVariant:     "#dab9ad"
    property string _m3outlineVariant:       "#665046"
    property string _m3error:               "#ffb4ab"
    property string _m3primaryFixedDim:      "#f7af91"
    property string _m3secondary:            "#e7bfb0"
    property string _m3onSecondary:          "#160701"
    property string _m3tertiary:             "#c9cb90"
    property string _m3onTertiary:           "#141500"
    property string _m3secondaryFixedDim:    "#e7bfb0"
    property string _m3tertiaryFixedDim:     "#c9cb90"

    readonly property color cPrimary:           Qt.color(_m3primary)
    readonly property color cOnSurf:            Qt.color(_m3onSurface)
    readonly property color cOnSurfVar:         Qt.color(_m3onSurfaceVariant)
    readonly property color cBg:                Qt.color(_m3background)
    readonly property color cInvPrimary:        Qt.color(_m3inversePrimary)
    readonly property color cSurfHi:            Qt.color(_m3surfaceContainerHigh)
    readonly property color cOutVar:            Qt.color(_m3outlineVariant)
    readonly property color cErr:               Qt.color(_m3error)
    readonly property color cPrimFixedDim:      Qt.color(_m3primaryFixedDim)
    readonly property color cSecondary:         Qt.color(_m3secondary)
    readonly property color cOnSecondary:       Qt.color(_m3onSecondary)
    readonly property color cTertiary:          Qt.color(_m3tertiary)
    readonly property color cSecondaryFixedDim: Qt.color(_m3secondaryFixedDim)
    readonly property color cTertiaryFixedDim:  Qt.color(_m3tertiaryFixedDim)

    // Outer panel tint
    readonly property color cPanel: Qt.rgba(
        Qt.color(_m3inversePrimary).r, Qt.color(_m3inversePrimary).g,
        Qt.color(_m3inversePrimary).b, 0.62)
    // Sub-card backgrounds
    readonly property color cCardDark: Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.80)
    readonly property color cCardWarm: Qt.rgba(
        Qt.color(_m3inversePrimary).r, Qt.color(_m3inversePrimary).g,
        Qt.color(_m3inversePrimary).b, 0.65)

    function parseColors(t) {
        const re=/property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while((m=re.exec(t))!==null) switch(m[1]) {
            case "m3primary":              root._m3primary=m[2]; break
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
    // Reads from the same cache that waybar-weather.sh writes, respects
    // the waybar weather codes and humidity override logic exactly.
    property string weatherUnit: "metric"
    property string weatherIcon: "󰖐"  // nf-md-weather_cloudy fallback
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

    // Icon map — exact 1:1 match with waybar-weather.sh (same icons, same logic)
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
    // Read from waybar's shared cache file directly (same source as waybar-weather.sh)
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

    Process {
        id:mediaProc
        command:["playerctl","-F","metadata","--format","{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}"]
        stdout: SplitParser {
            splitMarker:"\n"
            onRead: function(l){
                const p=l.split("\t")
                if(p.length>=4){
                    root.mediaStatus=p[0].trim()||"Stopped"
                    const newUrl=p[1].trim()
                    if(newUrl!==root.mediaArtUrl){
                        root.mediaArtUrl=newUrl
                        root._circularArtPath=""
                        if(newUrl) artConvProc.launch(newUrl)
                    }
                    root.mediaTitle=p[2].trim()||"No media"
                    root.mediaArtist=p[3].trim()
                }
            }
        }
        Component.onCompleted: running=true
    }

    // ImageMagick: art → 192px circle PNG
    // Uses -draw 'fill white circle cx,cy cx,cy-r' which is the reliable form
    Process {
        id:artConvProc
        property string _dst: "/tmp/qs_art_circle.png"
        property string _cmd: "true"
        command:["bash","-c", artConvProc._cmd]
        function launch(url) {
            const src = url.startsWith("file://") ? url.substring(7) : url
            // Shell-escape src via printf %q equivalent: single-quote the path
            _cmd = "SRC='" + src.replace(/'/g, "'\\''") + "'; " +
                   "DST='" + _dst + "'; " +
                   "[ -f \"$SRC\" ] || { " +
                   "  curl -sf --max-time 10 \"$SRC\" -o /tmp/qs_art_raw.png 2>/dev/null && SRC=/tmp/qs_art_raw.png; " +
                   "}; " +
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

    // ImageMagick: user icon → 192px circle PNG at startup
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

    Process { id:ctlProc; property string _cmd:""; command:["bash","-c",ctlProc._cmd] }
    function playerAction(cmd){ ctlProc._cmd="playerctl "+cmd; if(!ctlProc.running) ctlProc.running=true }

    // ── Session lock ──────────────────────────────────────────────────────────
    WlSessionLock { id:sessionLock; locked:true
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

                // ── UNIFIED BLUR PANEL ────────────────────────────────────────
                // FIX: clip:true on Rectangle clips to the bounding RECTANGLE,
                // not to the radius — blurred content bled to the four 90° corners.
                //
                // Correct approach:
                //   1. centerPanel is a plain Item (no clip, no radius of its own).
                //   2. layer.enabled:true renders ALL children to a single FBO.
                //   3. layer.effect MultiEffect uses roundMask's layer alpha to crop
                //      the FBO to the rounded shape before compositing to screen.
                //   4. roundMask has opacity:0 so it is invisible in the scene, but
                //      its layer (captured before opacity compositing) still provides
                //      the white-filled rounded rect texture that MultiEffect reads.
                Item {
                    id:centerPanel
                    anchors.centerIn:parent
                    width:660
                    height:panelCol.implicitHeight+56
                    // No clip:true — clipping is handled by the MultiEffect mask below.

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled:      true
                        maskSource:       roundMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin:  1.0
                    }

                    // Mask shape — white rounded rect rendered to its own FBO.
                    // opacity:0 hides it from the scene while still supplying the
                    // layer texture (Qt captures the FBO before the opacity pass).
                    Rectangle {
                        id: roundMask
                        anchors.fill: parent
                        radius: 32
                        color: "white"
                        opacity: 0
                        layer.enabled: true
                    }

                    // Blurred wallpaper slice
                    Item {
                        anchors.fill:parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect {
                            blurEnabled:true; blur:1.0; blurMax:64
                        }
                        AnimatedImage {
                            x: -centerPanel.x; y: -centerPanel.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath?"file://"+root.wallpaperPath:""
                            fillMode:Image.PreserveAspectCrop; smooth:true; playing:true; cache:true
                            visible: root.wallpaperPath!==""
                        }
                    }

                    // Panel tint + border — radius matches roundMask exactly (32)
                    Rectangle {
                        anchors.fill:parent; radius:32; color:root.cPanel
                        border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.1)
                    }

                    ColumnLayout {
                        id:panelCol
                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:24 }
                        spacing:16

                        // ══════ ROW 1: clock card  |  info card + pin card ══════
                        RowLayout {
                            Layout.fillWidth:true; spacing:14

                            // ── CLOCK CARD ─────────────────────────────────────
                            // Fixed width, height matches the right column's combined height
                            Rectangle {
                                id:clockCard
                                Layout.preferredWidth:148
                                // Match right column height: infoCard + spacing + pinCard
                                Layout.preferredHeight:rightCol.implicitHeight
                                radius:20
                                color:root.cCardDark
                                border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                ColumnLayout {
                                    anchors.centerIn:parent; spacing:0
                                    Text {
                                        Layout.alignment:Qt.AlignHCenter
                                        text:root.clockHour; color:root.cPrimary
                                        font.family:"C059"; font.pixelSize:86; font.italic:true; font.weight:Font.Bold
                                        lineHeight:0.88
                                    }
                                    // cod-circle_small_full separator (codicon U+EA71)
                                    Text {
                                        Layout.alignment:Qt.AlignHCenter
                                        text:"󰫢  󰫢"
                                        color:root.cTertiary
                                        font.family:"codicon"
                                        font.pixelSize:14
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

                            // ── RIGHT COLUMN ────────────────────────────────────
                            ColumnLayout {
                                id:rightCol
                                Layout.fillWidth:true; spacing:10

                                // DATE + USER ICON + WEATHER + PIN — all in one card
                                Rectangle {
                                    id:infoCard
                                    Layout.fillWidth:true
                                    height:infoCardCol.implicitHeight+36
                                    radius:20
                                    color:root.cCardWarm
                                    border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                    ColumnLayout {
                                        id:infoCardCol
                                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:20 }
                                        spacing:14

                                        // Date — Primary
                                        Text {
                                            Layout.fillWidth:true
                                            text:root.clockDate; color:root.cPrimary
                                            font.family:"C059"; font.pixelSize:24; font.italic:true; font.weight:Font.DemiBold
                                            horizontalAlignment:Text.AlignHCenter
                                        }

                                        // User icon + weather row
                                        RowLayout {
                                            Layout.fillWidth:true; spacing:20; Layout.alignment:Qt.AlignHCenter

                                            // Circular user icon — ImageMagick pre-processed
                                            Item {
                                                width:88; height:88

                                                Image {
                                                    id:userImg
                                                    anchors.fill:parent
                                                    source: root._userIconPath!=="" ? ("file://" + root._userIconPath.split("?")[0] + "?v=" + root._userIconPath.split("?")[1]) : ""
                                                    fillMode:Image.PreserveAspectFit
                                                    smooth:true; cache:false
                                                    visible:status===Image.Ready
                                                }
                                                // Fallback glyph
                                                Rectangle {
                                                    anchors.fill:parent; radius:44; color:root.cSurfHi
                                                    visible:userImg.status!==Image.Ready
                                                    Text {
                                                        anchors.centerIn:parent
                                                        text:"󰀄"; font.pixelSize:40; font.family:"Symbols Nerd Font Mono"
                                                        color:root.cOnSurfVar
                                                    }
                                                }
                                                // Decorative ring
                                                Rectangle {
                                                    anchors.fill:parent; radius:44; color:"transparent"
                                                    border.width:2
                                                    border.color:Qt.rgba(root.cSecondary.r,root.cSecondary.g,root.cSecondary.b,0.60)
                                                }
                                            }

                                            // Weather — temp + icon
                                            ColumnLayout {
                                                Layout.fillWidth:true; spacing:4; Layout.alignment:Qt.AlignVCenter
                                                Text {
                                                    Layout.alignment:Qt.AlignHCenter
                                                    text:root.weatherTemp; color:root.cOnSurf
                                                    font.family:"C059"; font.pixelSize:28; font.italic:true; font.weight:Font.DemiBold
                                                }
                                                Text {
                                                    Layout.alignment:Qt.AlignHCenter
                                                    text:root.weatherIcon; color:root.cPrimary
                                                    font.pixelSize:24; font.family:"Symbols Nerd Font Mono"
                                                }
                                            }
                                        }

                                        // Subtle divider
                                        Rectangle {
                                            Layout.fillWidth:true; height:1
                                            color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.30)
                                        }

                                        // ── PIN ENTRY (inline, no separate card) ──────────
                                        Item {
                                            Layout.alignment:Qt.AlignHCenter
                                            width:220; height:44

                                            Rectangle {
                                                anchors.fill:parent; radius:22
                                                color:Qt.rgba(root.cBg.r,root.cBg.g,root.cBg.b,0.75)
                                                border.width:2
                                                border.color: root.authFailed ? root.cErr
                                                    : (root.authChecking
                                                        ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.40)
                                                        : root.cPrimary)
                                                Behavior on border.color { ColorAnimation{duration:250} }
                                            }
                                            // Placeholder
                                            RowLayout {
                                                anchors.centerIn:parent; spacing:7
                                                visible:root.pinEntry.length===0 && !root.authChecking
                                                Text {
                                                    text:"󰀄"
                                                    font.family:"Symbols Nerd Font Mono"; font.pixelSize:14
                                                    color:root.cPrimary; opacity:0.90
                                                }
                                                Text {
                                                    text:Quickshell.env("USER")
                                                    font.family:"C059"; font.pixelSize:14; font.italic:true
                                                    color:root.cPrimary; opacity:0.90
                                                }
                                            }
                                            // Spinner
                                            Text {
                                                anchors.centerIn:parent; visible:root.authChecking
                                                text:"󰶘"
                                                font.family:"Symbols Nerd Font Mono"; font.pixelSize:18; color:root.cPrimary
                                                RotationAnimator on rotation { from:0; to:360; duration:900; loops:Animation.Infinite; running:root.authChecking }
                                            }
                                            // Dots
                                            Row {
                                                anchors.centerIn:parent; spacing:6
                                                visible:root.pinEntry.length>0 && !root.authChecking
                                                Repeater { model:root.pinEntry.length; delegate:Rectangle{width:9;height:9;radius:5;color:root.cPrimary;opacity:0.90} }
                                            }
                                        }

                                        // Error text — bottom of card, no extra bottom margin
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

                        // ══════ ROW 2: media card | dials card ══════════════════
                        RowLayout {
                            Layout.fillWidth:true; spacing:14; Layout.bottomMargin:4

                            // ── MEDIA CARD ──────────────────────────────────────
                            Rectangle {
                                Layout.fillWidth:true
                                height:mediaCardCol.implicitHeight+32
                                radius:20
                                color:root.cCardWarm
                                border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                ColumnLayout {
                                    id:mediaCardCol
                                    anchors { left:parent.left; right:parent.right; top:parent.top; margins:18 }
                                    spacing:8

                                    // Album disc
                                    Item {
                                        Layout.alignment:Qt.AlignHCenter
                                        width:96; height:96

                                        Rectangle { anchors.fill:parent; radius:48; color:root.cSurfHi }

                                        // Pre-processed circular art
                                        Image {
                                            id:artImg
                                            anchors.fill:parent
                                            source: root._circularArtPath!==""
                                                ? ("file://" + root._circularArtPath.split("?")[0] + "?v=" + root._circularArtPath.split("?")[1])
                                                : ""
                                            fillMode:Image.PreserveAspectFit
                                            smooth:true; cache:false
                                            visible:root._circularArtPath!==""&&status===Image.Ready
                                        }
                                        Text {
                                            anchors.centerIn:parent; visible:!artImg.visible
                                            text:"󰽲"
                                            font.pixelSize:40; font.family:"Symbols Nerd Font Mono"
                                            color:root.cOnSurfVar; opacity:0.35
                                        }

                                        // Smooth rotation — ~22fps feel via short duration
                                        // Spindle removed; image itself rotates
                                        RotationAnimator on rotation {
                                            from:0; to:360
                                            duration:100000
                                            loops:Animation.Infinite
                                            running:root.mediaStatus==="Playing"
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth:true
                                        text:root.mediaTitle; color:root.cOnSurf
                                        font.pixelSize:13; font.weight:Font.DemiBold
                                        horizontalAlignment:Text.AlignHCenter; elide:Text.ElideRight
                                    }
                                    Text {
                                        Layout.fillWidth:true
                                        text:root.mediaArtist; color:root.cOnSurfVar
                                        font.pixelSize:11; horizontalAlignment:Text.AlignHCenter
                                        elide:Text.ElideRight; visible:text!==""
                                    }

                                    // Controls
                                    RowLayout {
                                        Layout.alignment:Qt.AlignHCenter; spacing:10
                                        Repeater {
                                            model:[
                                                {i:"󰒮",c:"previous"},
                                                {i:root.mediaStatus==="Playing"?"󰏤":"󰐊",c:"play-pause"},
                                                {i:"󰒭",c:"next"}
                                            ]
                                            delegate: Rectangle {
                                                required property var modelData
                                                required property int index
                                                width:34; height:34; radius:6
                                                readonly property bool isPlay: index===1
                                                color: mha.containsMouse
                                                    ? (isPlay
                                                        ? Qt.rgba(root.cOnSurf.r,root.cOnSurf.g,root.cOnSurf.b,0.22)
                                                        : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18))
                                                    : "transparent"
                                                border.width:1
                                                border.color: isPlay
                                                    ? Qt.rgba(root.cOnSurf.r,root.cOnSurf.g,root.cOnSurf.b,0.65)
                                                    : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.50)
                                                Behavior on color { ColorAnimation{duration:100} }
                                                Text {
                                                    anchors.centerIn:parent
                                                    text:modelData.i; font.pixelSize:16; font.family:"Symbols Nerd Font Mono"
                                                    color: mha.containsMouse
                                                        ? (parent.isPlay ? root.cOnSurf : root.cPrimary)
                                                        : root.cOnSurfVar
                                                    Behavior on color { ColorAnimation{duration:100} }
                                                }
                                                MouseArea { id:mha; anchors.fill:parent; hoverEnabled:true; onClicked:root.playerAction(modelData.c) }
                                            }
                                        }
                                    }
                                }
                            }

                            // ── DIALS CARD ──────────────────────────────────────
                            Rectangle {
                                id:dialsCard
                                Layout.preferredWidth:116
                                // Self-sizing: derive height from own column content
                                height:dialsCol.implicitHeight + 32
                                radius:20
                                color:root.cCardDark
                                border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                ColumnLayout {
                                    id:dialsCol
                                    // Fill width, pin to top+bottom with equal padding — never clips
                                    anchors {
                                        left:parent.left; right:parent.right
                                        top:parent.top; bottom:parent.bottom
                                        margins:14
                                    }
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
                                            readonly property color arcColor: index===0 ? root.cPrimFixedDim
                                                : (index===1 ? root.cSecondaryFixedDim : root.cTertiaryFixedDim)

                                            // Fill available column space equally; min height keeps label visible
                                            Layout.fillWidth:true
                                            Layout.fillHeight:true
                                            Layout.minimumHeight:88

                                            Canvas {
                                                id:arcC
                                                // Centre the 72px canvas within whatever height the item gets
                                                anchors.horizontalCenter:parent.horizontalCenter
                                                anchors.top:parent.top
                                                anchors.topMargin: Math.max(0, (parent.height - 72 - 14) / 2)
                                                width:72; height:72
                                                property color dialCol: parent.arcColor
                                                property color onS:     root.cOnSurf
                                                property real  cv:      parent.arcVal
                                                property string gt:     parent.arcText
                                                property string gl:     parent.arcGlyph
                                                onDialColChanged: requestPaint()
                                                onOnSChanged:     requestPaint()
                                                onCvChanged:      requestPaint()
                                                onGtChanged:      requestPaint()
                                                Component.onCompleted: requestPaint()
                                                onPaint: {
                                                    const ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                                                    const cx=width/2, cy=height/2, r=27, lw=5
                                                    const s=0.75*Math.PI, e=2.25*Math.PI
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
                                                // Label sits below the canvas, centered
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

                // Hidden TextInput
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
