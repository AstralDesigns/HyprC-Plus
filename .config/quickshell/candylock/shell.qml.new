pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

ShellRoot {
    id: root

    property string _m3primary:              "#f7af91"
    property string _m3onPrimary:            "#170700"
    property string _m3onSecondary:          "#170700"
    property string _m3background:           "#170700"
    property string _m3inversePrimary:       "#6f2900"
    property string _m3surfaceContainerHigh: "#1e1613"
    property string _m3onSurface:            "#f8dfd5"
    property string _m3onSurfaceVariant:     "#dab9ad"
    property string _m3outlineVariant:       "#665046"
    property string _m3error:               "#ffb4ab"
    property string _m3primaryFixedDim:      "#f7af91"
    property string _m3primaryFixed:         "#ffdbcc"

    readonly property color cPrimary:      Qt.color(_m3primary)
    readonly property color cOnPrim:       Qt.color(_m3onPrimary)
    readonly property color cOnSurf:       Qt.color(_m3onSurface)
    readonly property color cOnSurfVar:    Qt.color(_m3onSurfaceVariant)
    readonly property color cBg:           Qt.color(_m3background)
    readonly property color cInvPrimary:   Qt.color(_m3inversePrimary)
    readonly property color cSurfHi:       Qt.color(_m3surfaceContainerHigh)
    readonly property color cOutVar:       Qt.color(_m3outlineVariant)
    readonly property color cErr:          Qt.color(_m3error)
    readonly property color cPrimFixedDim: Qt.color(_m3primaryFixedDim)
    readonly property color cPanel: Qt.rgba(
        Qt.color(_m3inversePrimary).r, Qt.color(_m3inversePrimary).g,
        Qt.color(_m3inversePrimary).b, 0.60)

    function parseColors(t) {
        const re=/property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while((m=re.exec(t))!==null) switch(m[1]) {
            case "m3primary":                 root._m3primary=m[2]; break
            case "m3onPrimary":               root._m3onPrimary=m[2]; break
            case "m3onSecondary":             root._m3onSecondary=m[2]; break
            case "m3background":              root._m3background=m[2]; break
            case "m3inversePrimary":          root._m3inversePrimary=m[2]; break
            case "m3surfaceContainerHigh":    root._m3surfaceContainerHigh=m[2]; break
            case "m3onSurface":               root._m3onSurface=m[2]; break
            case "m3onSurfaceVariant":        root._m3onSurfaceVariant=m[2]; break
            case "m3outlineVariant":          root._m3outlineVariant=m[2]; break
            case "m3error":                   root._m3error=m[2]; break
            case "m3primaryFixedDim":         root._m3primaryFixedDim=m[2]; break
            case "m3primaryFixed":            root._m3primaryFixed=m[2]; break
        }
    }
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME")||(Quickshell.env("HOME")+"/.cache"))+"/quickshell/wallpaper/MatugenColors.qml"
        watchChanges:true; onFileChanged:reload(); onLoaded:root.parseColors(text())
    }

    property string wallpaperPath: ""
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME")||(Quickshell.env("HOME")+"/.config"))+"/wallpaper/wallpaper.ini"
        watchChanges:true; onFileChanged:reload()
        onLoaded: { const m=text().match(/^wallpaper\s*=\s*(.+)$/m); if(m) root.wallpaperPath=m[1].trim().replace(/^~/,Quickshell.env("HOME")) }
    }

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

    property string clockHour:Qt.formatTime(new Date(),"hh")
    property string clockMin: Qt.formatTime(new Date(),"mm")
    property string clockDate:Qt.formatDate(new Date(),"dddd, d MMMM")
    Timer { interval:5000; repeat:true; running:true; onTriggered:{
        root.clockHour=Qt.formatTime(new Date(),"hh")
        root.clockMin=Qt.formatTime(new Date(),"mm")
        root.clockDate=Qt.formatDate(new Date(),"dddd, d MMMM")
    }}

    property string weatherIcon:"󰖐"; property string weatherTemp:"--°"
    function wmoIcon(c,d){ if(c===0)return d?"󰖙":"󰖔"; if(c<=3)return"󰖕"; if(c<=48)return""; if(c<=55)return"󰖗"; if(c<=67)return"󰖖"; if(c<=77)return"󰜗"; if(c<=82)return"󰙾"; return"󰖓" }
    Process {
        id:wxProc; property var _b:[]
        command:["bash","-c","WF=/tmp/qs-weather-cache.json; LF=/tmp/qs-loc-cache; AGE=$(($(date +%s)-$(stat -c%Y \"$WF\" 2>/dev/null||echo 0))); [ -f \"$WF\" ]&&[ $AGE -lt 300 ]&&{ cat \"$WF\"; exit 0; }; [ -f \"$LF\" ]&&[ $(($(date +%s)-$(stat -c%Y \"$LF\" 2>/dev/null||echo 0))) -lt 3600 ]&&LOC=$(cat \"$LF\")||{ LOC=$(curl -sf --max-time 5 'https://ipinfo.io/loc' 2>/dev/null||echo '0,0'); echo \"$LOC\">\"$LF\"; }; LAT=${LOC%,*}; LON=${LOC#*,}; curl -sf --max-time 12 \"https://api.open-meteo.com/v1/forecast?latitude=$LAT&longitude=$LON&current=temperature_2m,is_day,weather_code&timezone=auto\" -o \"$WF\" 2>/dev/null&&cat \"$WF\""]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){wxProc._b.push(l)} }
        onRunningChanged: if(running) _b=[]
        onExited: function(){ try{ const w=JSON.parse(_b.join("")); if(w.current){ root.weatherIcon=root.wmoIcon(w.current.weather_code||0,w.current.is_day||1); root.weatherTemp=Math.round(w.current.temperature_2m||0)+"°" } }catch(e){} _b=[] }
        Component.onCompleted: running=true
    }
    Timer { interval:300000; repeat:true; running:true; onTriggered: if(!wxProc.running) wxProc.running=true }

    property real cpuUsage:0; property real memUsage:0; property real tempC:0; property bool tempOk:false
    Behavior on cpuUsage { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    Behavior on memUsage { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    Behavior on tempC    { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    property var _prevCpu:null
    Process {
        id:sysProc; property var _b:[]
        command:["bash","-c","head -1 /proc/stat; grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; for z in /sys/class/thermal/thermal_zone*/; do t=$(cat \"$z/temp\" 2>/dev/null); y=$(cat \"$z/type\" 2>/dev/null); [ -n \"$t\" ]&&echo \"$y:$t\"; done"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){sysProc._b.push(l.trim())} }
        onRunningChanged: if(running) _b=[]
        onExited: function(){
            const lines=_b.slice(); _b=[]
            const cm=lines[0]?lines[0].match(/cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/):null
            if(cm){ const u=+cm[1],n=+cm[2],s=+cm[3],i=+cm[4],cur={total:u+n+s+i,idle:i}; if(root._prevCpu){ const dt=cur.total-root._prevCpu.total,di=cur.idle-root._prevCpu.idle; if(dt>0) root.cpuUsage=(dt-di)/dt }; root._prevCpu=cur }
            let mi={}; for(const l of lines){ const mm=l.match(/^(\w+):\s*(\d+)\s*kB/); if(mm) mi[mm[1]]=parseInt(mm[2])*1024 }
            if(mi.MemTotal&&mi.MemAvailable) root.memUsage=(mi.MemTotal-mi.MemAvailable)/mi.MemTotal
            for(const l of lines){ const tm=l.match(/^([^:]+):(\d+)$/); if(!tm) continue; const v=parseInt(tm[2])/1000; if(v>0&&v<150&&tm[1].toLowerCase().includes("cpu")){ root.tempC=v; root.tempOk=true; break } }
        }
    }
    Timer { interval:1500; repeat:true; running:true; onTriggered:if(!sysProc.running) sysProc.running=true
        Component.onCompleted: sysProc.running=true
    }

    property string mediaStatus:"Stopped"; property string mediaTitle:"No media"
    property string mediaArtist:""; property string mediaArtUrl:""
    Process {
        id:mediaProc
        command:["playerctl","-F","metadata","--format","{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){ const p=l.split("\t"); if(p.length>=4){ root.mediaStatus=p[0].trim()||"Stopped"; root.mediaArtUrl=p[1].trim(); root.mediaTitle=p[2].trim()||"No media"; root.mediaArtist=p[3].trim() } } }
        Component.onCompleted: running=true
    }
    Process { id:ctlProc; property string _cmd:""; command:["bash","-c",ctlProc._cmd] }
    function playerAction(cmd){ ctlProc._cmd="playerctl "+cmd; if(!ctlProc.running) ctlProc.running=true }

    property var cavaBars:[]; property int cavaN:32; readonly property int cavaRange:15
    Process { id:cavaMgr; command:["python3",Quickshell.env("HOME")+"/.config/quickshell/candylock-media/cava.py","--manager","--bars","32","--range","15"]
        Component.onCompleted: running=true
    }
    Timer { interval:1500; running:true; repeat:false; onTriggered:cavaProc.running=true }
    Process {
        id:cavaProc
        command:["bash","-c","SOCK=\"${XDG_RUNTIME_DIR}/hyprcandy-lock/cava.sock\"; while true; do [ -S \"$SOCK\" ]&&nc -U \"$SOCK\" 2>/dev/null; sleep 3; done"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(line){
            const parts=line.trim().split(";").filter(v=>/^\d+$/.test(v))
            if(parts.length<2) return
            const n=Math.min(parts.length,64),prev=root.cavaBars,nb=new Array(n)
            for(let i=0;i<n;i++){ const raw=Math.min(parseInt(parts[i]),root.cavaRange)/root.cavaRange,p=(prev&&prev[i])?prev[i]:0; nb[i]=raw>p?p*0.25+raw*0.75:p*0.55+raw*0.45 }
            root.cavaN=n; root.cavaBars=nb
        }}
    }

    WlSessionLock { id:sessionLock; locked:true
        WlSessionLockSurface {
            Rectangle {
                id:mainRect; anchors.fill:parent; color:root.cBg; focus:true
                Keys.onPressed: function(ev){ if(!ev.isAutoRepeat) pinInput.forceActiveFocus() }

                AnimatedImage {
                    anchors.fill:parent
                    source: root.wallpaperPath ? "file://"+root.wallpaperPath : ""
                    fillMode:Image.PreserveAspectCrop
                    smooth:true; mipmap:true; cache:true; playing:true; asynchronous:true
                    visible: root.wallpaperPath !== ""
                }

                Item {
                    id:centerPanel
                    anchors.centerIn:parent
                    width:440; height:centerCol.implicitHeight+56
                    clip:true

                    Item {
                        anchors.fill:parent
                        layer.enabled: root.wallpaperPath !== ""
                        layer.effect: MultiEffect { blurEnabled:true; blur:1.0; blurMax:64 }
                        AnimatedImage {
                            x:-centerPanel.x; y:-centerPanel.y
                            width:mainRect.width; height:mainRect.height
                            source: root.wallpaperPath ? "file://"+root.wallpaperPath : ""
                            fillMode:Image.PreserveAspectCrop
                            smooth:true; playing:true; cache:true
                            visible: root.wallpaperPath !== ""
                        }
                    }

                    Rectangle {
                        anchors.fill:parent; radius:32; color:root.cPanel
                        border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.28)
                    }

                    ColumnLayout {
                        id:centerCol
                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:28 }
                        spacing:0

                        // ── Media disc + cava ──────────────────────────────────
                        Item {
                            Layout.alignment:Qt.AlignHCenter; Layout.topMargin:4
                            readonly property int ds:110; readonly property int gap:7; readonly property int bm:20
                            readonly property int rs: ds+2*(gap+bm+2)
                            width:rs; height:rs; Layout.preferredWidth:rs; Layout.preferredHeight:rs

                            Canvas {
                                id:cavaCanvas; anchors.fill:parent
                                property color pri:root.cPrimary
                                onPriChanged: requestPaint()
                                Connections { target:root; function onCavaBarsChanged(){ cavaCanvas.requestPaint() } }
                                onPaint: {
                                    const ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                                    const bars=root.cavaBars, N=root.cavaN
                                    if(!bars||N<2) return
                                    const p=parent, cx=width/2, cy=height/2
                                    const rI=p.ds/2+p.gap, bmax=p.bm
                                    const dA=2*Math.PI/N, s0=-Math.PI/2
                                    ctx.lineCap="round"
                                    for(let i=0;i<N;i++){
                                        const amp=bars[i]||0; if(amp<0.01) continue
                                        const a=s0+(i+0.5)*dA, len=Math.max(2,amp*bmax)
                                        const c=Math.cos(a), s=Math.sin(a)
                                        ctx.lineWidth=1.5+amp*1.5
                                        ctx.strokeStyle=Qt.rgba(pri.r,pri.g,pri.b,0.25+amp*0.75).toString()
                                        ctx.beginPath(); ctx.moveTo(cx+rI*c,cy+rI*s); ctx.lineTo(cx+(rI+len)*c,cy+(rI+len)*s); ctx.stroke()
                                    }
                                }
                            }

                            Item {
                                id:disc; anchors.centerIn:parent
                                width:parent.ds; height:parent.ds
                                layer.enabled:true

                                Rectangle {
                                    anchors.fill:parent; radius:width/2; color:root.cSurfHi; clip:true
                                    Image {
                                        anchors.fill:parent; fillMode:Image.PreserveAspectCrop
                                        source: root.mediaArtUrl !== "" ? root.mediaArtUrl : ""
                                        visible:root.mediaArtUrl !== ""; smooth:true; mipmap:true
                                    }
                                    Text {
                                        anchors.centerIn:parent; visible:root.mediaArtUrl===""
                                        text:"󰽲"; font.pixelSize:44; font.family:"Symbols Nerd Font Mono"
                                        color:root.cOnSurfVar; opacity:0.35
                                    }
                                }
                                Rectangle {
                                    anchors.centerIn:parent; width:22; height:22; radius:11; color:"transparent"
                                    border.width:3; border.color:Qt.rgba(root.cBg.r,root.cBg.g,root.cBg.b,0.85); z:2
                                }
                                Rectangle {
                                    anchors.centerIn:parent; width:13; height:13; radius:7
                                    color:root.cPrimary; z:3
                                }
                                RotationAnimator { target:disc; from:0; to:360; duration:14000; loops:Animation.Infinite; running:root.mediaStatus==="Playing" }
                            }
                        }

                        Text {
                            Layout.fillWidth:true; Layout.topMargin:10
                            text:root.mediaTitle; color:root.cOnSurf
                            font.pixelSize:14; font.weight:Font.DemiBold
                            horizontalAlignment:Text.AlignHCenter; elide:Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth:true; Layout.topMargin:2
                            text:root.mediaArtist; color:root.cOnSurfVar
                            font.pixelSize:11; horizontalAlignment:Text.AlignHCenter
                            elide:Text.ElideRight; visible:text!==""
                        }
                        RowLayout {
                            Layout.alignment:Qt.AlignHCenter; Layout.topMargin:10; spacing:12
                            Repeater {
                                model:[{i:"󰒮",c:"previous"},{i:root.mediaStatus==="Playing"?"󰏤":"󰐊",c:"play-pause"},{i:"󰒭",c:"next"}]
                                delegate: Rectangle {
                                    required property var modelData
                                    width:36; height:36; radius:18
                                    color:mha.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18):"transparent"
                                    border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.45)
                                    Behavior on color{ColorAnimation{duration:100}}
                                    Text { anchors.centerIn:parent; text:modelData.i; font.pixelSize:17; font.family:"Symbols Nerd Font Mono"; color:mha.containsMouse?root.cPrimary:root.cOnSurfVar; Behavior on color{ColorAnimation{duration:100}} }
                                    MouseArea { id:mha; anchors.fill:parent; hoverEnabled:true; onClicked:root.playerAction(modelData.c) }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth:true; height:1; Layout.topMargin:16; Layout.bottomMargin:4; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.28) }

                        // ── Time / user icon row ───────────────────────────────
                        RowLayout {
                            Layout.fillWidth:true; Layout.topMargin:4; spacing:12

                            Item {
                                width:64; height:64; Layout.alignment:Qt.AlignVCenter
                                Rectangle {
                                    anchors.fill:parent; radius:width/2; color:root.cSurfHi; clip:true
                                    Image {
                                        anchors.fill:parent; fillMode:Image.PreserveAspectCrop
                                        source:"file://"+Quickshell.env("HOME")+"/.config/hyprcandy/user-icon.png"
                                        smooth:true; mipmap:true; visible:status===Image.Ready
                                    }
                                    Text {
                                        anchors.centerIn:parent
                                        visible:parent.children[0].status!==Image.Ready
                                        text:"󰀄"; font.pixelSize:28; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar
                                    }
                                }
                                Rectangle {
                                    anchors.fill:parent; radius:width/2; color:"transparent"
                                    border.width:2; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.55)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth:true; spacing:-10; Layout.alignment:Qt.AlignVCenter
                                Text {
                                    Layout.alignment:Qt.AlignHCenter
                                    text:root.clockHour; color:root.cOnSurf
                                    font.family:"C059"; font.pixelSize:84; font.italic:true; font.weight:Font.Bold; lineHeight:0.88
                                }
                                Text {
                                    Layout.alignment:Qt.AlignHCenter
                                    text:root.clockMin; color:root.cPrimary
                                    font.family:"C059"; font.pixelSize:84; font.italic:true; font.weight:Font.Bold; lineHeight:0.88
                                }
                            }
                        }

                        RowLayout {
                            Layout.alignment:Qt.AlignHCenter; Layout.topMargin:6; spacing:16
                            Text { text:root.clockDate; color:root.cOnSurfVar; font.pixelSize:13; font.family:"C059"; font.italic:true }
                            RowLayout { spacing:5
                                Text { text:root.weatherIcon; font.pixelSize:15; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary }
                                Text { text:root.weatherTemp; color:root.cOnSurfVar; font.pixelSize:13 }
                            }
                        }

                        Rectangle { Layout.fillWidth:true; height:1; Layout.topMargin:12; Layout.bottomMargin:4; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.28) }

                        // ── System gauges (CPU / RAM / Temp) ──────────────────
                        RowLayout {
                            Layout.fillWidth:true; Layout.topMargin:4; spacing:0
                            Repeater {
                                model:[
                                    {g:"󰻠",l:"CPU", v:root.cpuUsage, t:Math.round(root.cpuUsage*100)+"%"},
                                    {g:"󰍛",l:"RAM", v:root.memUsage, t:Math.round(root.memUsage*100)+"%"},
                                    {g:"󰔏",l:"Temp",v:root.tempOk?Math.min(root.tempC/100,1):0,t:root.tempOk?Math.round(root.tempC)+"°":"N/A"}
                                ]
                                delegate: Item {
                                    required property var modelData
                                    Layout.fillWidth:true; height:76
                                    Canvas {
                                        id:arcC; anchors.top:parent.top; anchors.horizontalCenter:parent.horizontalCenter
                                        width:68; height:68
                                        property color pri:root.cPrimary
                                        property color onS:root.cOnSurf
                                        property real val:modelData.v
                                        property string glyph:modelData.g
                                        property string vt:modelData.t
                                        onPriChanged:requestPaint(); onOnSChanged:requestPaint(); onValChanged:requestPaint()
                                        onPaint: {
                                            const ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                                            const cx=width/2,cy=height/2,r=26,lw=4.5,s=0.75*Math.PI,e=2.25*Math.PI
                                            ctx.lineWidth=lw; ctx.lineCap="round"
                                            ctx.beginPath(); ctx.arc(cx,cy,r,s,e); ctx.strokeStyle=Qt.rgba(onS.r,onS.g,onS.b,0.08).toString(); ctx.stroke()
                                            if(val>0.005){ ctx.beginPath(); ctx.arc(cx,cy,r,s,s+val*(e-s)); ctx.strokeStyle=pri.toString(); ctx.stroke() }
                                            ctx.fillStyle=Qt.rgba(pri.r,pri.g,pri.b,0.9).toString(); ctx.font="14px 'Symbols Nerd Font Mono'"; ctx.textAlign="center"; ctx.textBaseline="alphabetic"; ctx.fillText(glyph,cx,cy)
                                            ctx.fillStyle=Qt.rgba(onS.r,onS.g,onS.b,0.85).toString(); ctx.font="bold 9px monospace"; ctx.textBaseline="top"; ctx.fillText(vt,cx,cy+3)
                                        }
                                    }
                                    Text { anchors.bottom:parent.bottom; anchors.horizontalCenter:parent.horizontalCenter; text:modelData.l; color:root.cOnSurfVar; font.pixelSize:9 }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth:true; height:1; Layout.topMargin:12; Layout.bottomMargin:8; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.28) }

                        // ── PIN pill (hyprlock style) ──────────────────────────
                        Item {
                            Layout.alignment:Qt.AlignHCenter; Layout.bottomMargin:0
                            width:280; height:54

                            Rectangle {
                                anchors.fill:parent; radius:27; color:Qt.rgba(root.cBg.r,root.cBg.g,root.cBg.b,0.55)
                                border.width:2
                                border.color: root.authFailed
                                    ? root.cErr
                                    : (root.authChecking
                                        ? Qt.rgba(root.cPrimFixedDim.r,root.cPrimFixedDim.g,root.cPrimFixedDim.b,0.45)
                                        : root.cPrimFixedDim)
                                Behavior on border.color { ColorAnimation{duration:250} }
                            }

                            RowLayout {
                                anchors.centerIn:parent; spacing:8
                                visible:root.pinEntry.length===0 && !root.authChecking
                                Text { text:"󰀄"; font.family:"Symbols Nerd Font Mono"; font.pixelSize:15; color:root.cPrimFixedDim; opacity:0.80 }
                                Text {
                                    text:"       "+Quickshell.env("USER")+"       "
                                    font.family:"C059"; font.pixelSize:14; font.italic:true
                                    color:root.cPrimFixedDim; opacity:0.80
                                }
                            }

                            Text {
                                anchors.centerIn:parent; visible:root.authChecking
                                text:"󰒖"; font.family:"Symbols Nerd Font Mono"; font.pixelSize:20; color:root.cPrimary
                                RotationAnimator on rotation { from:0; to:360; duration:900; loops:Animation.Infinite; running:root.authChecking }
                            }

                            Row {
                                anchors.centerIn:parent; spacing:6
                                visible:root.pinEntry.length>0 && !root.authChecking
                                Repeater { model:root.pinEntry.length; delegate:Rectangle{width:10;height:10;radius:5;color:root.cPrimary;opacity:0.90} }
                            }
                        }

                        Text {
                            Layout.alignment:Qt.AlignHCenter
                            text:root.authFailed?"Wrong password":""
                            color:root.cErr; font.pixelSize:12; font.italic:true
                            opacity:root.authFailed?1:0
                            Behavior on opacity { NumberAnimation{duration:200} }
                        }

                        Item { height:4 }
                    }
                }

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
