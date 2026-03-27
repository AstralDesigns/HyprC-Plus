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

    IpcHandler { target: "startmenu"
        function toggle() { root.menuVisible = !root.menuVisible }
        function open()   { root.menuVisible = true }
        function close()  { root.menuVisible = false }
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
            if(ssid) root._netBuf.push({active:inuse==="*",secure:sec!=="",signal:parseInt(sig)||0,ssid:ssid})
        }}
        onRunningChanged: if(running) { root._netBuf=[] } else { root.networkList=root._netBuf.slice() }
    }
    Process { id: netConnProc; property string _cmd:""; command:["bash","-c",netConnProc._cmd]
        onRunningChanged: if(!running){ root.netConnecting_=false; if(!netStatusProc.running) netStatusProc.running=true }
    }
    function connectNetwork(ssid, password){
        const esc=ssid.replace(/'/g,"'\\''")
        if(password) netConnProc._cmd="nmcli device wifi connect '"+esc+"' password '"+password.replace(/'/g,"'\\''")+"'"
        else netConnProc._cmd="nmcli connection up '"+esc+"' 2>/dev/null || nmcli device wifi connect '"+esc+"'"
        root.netConnecting_=true; root.netConnectTarget=ssid
        if(!netConnProc.running) netConnProc.running=true
    }

    // ── Recorder ─────────────────────────────────────────────────────────────
    property bool isRecording: false
    Process { id: recCheckProc
        command:["bash","-c","pgrep -x wf-recorder > /dev/null && echo 1 || echo 0"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){ root.isRecording=l.trim()==="1" } }
        Component.onCompleted: running=true
    }
    Timer { interval:3000; repeat:true; running:true; onTriggered: if(!recCheckProc.running) recCheckProc.running=true }
    Process { id: recProc; property string _cmd:""; command:["bash","-c",recProc._cmd]
        onRunningChanged: if(!running) recStopRefreshTimer.restart()
    }
    Timer { id:recStopRefreshTimer; interval:500; repeat:false; onTriggered: if(!recCheckProc.running) recCheckProc.running=true }
    function toggleRecorder(){
        if(root.isRecording){
            recProc._cmd="pkill -SIGINT wf-recorder"
            if(!recProc.running) recProc.running=true
        } else {
            // setsid -f detaches from QS process group so it lives independently
            const s=Quickshell.env("HOME")+"/.config/hyprcandy/scripts/recorder.sh"
            recProc._cmd="setsid -f bash -c \"[ -x '"+s+"' ]&&'"+s+"'||wf-recorder -f ~/Videos/record_\$(date +%Y%m%d_%H%M%S).mp4\" &>/dev/null &"
            if(!recProc.running) recProc.running=true
        }
    }
    // Screenshot: close menu first, then fire-and-forget via setsid so it
    // doesn't inherit the QS process group (killing it won't kill startmenu)
    Process { id: ssProc; property string _cmd:""; command:["bash","-c",ssProc._cmd] }
    function takeScreenshot(){
        root.menuVisible=false
        const s=Quickshell.env("HOME")+"/.config/hyprcandy/scripts/screenshot.sh"
        ssProc._cmd="sleep 0.3 && ([ -x '"+s+"' ]&&setsid -f '"+s+"' &>/dev/null || setsid -f grimblast --notify copy area &>/dev/null) &"
        if(!ssProc.running) ssProc.running=true
    }
    Process { id: logoutProc; command:["bash","-c","hyprctl dispatch exit"] }
    Process { id: powerProc; property string _cmd:""; command:["bash","-c",powerProc._cmd] }

    // ── Panel window ─────────────────────────────────────────────────────────
    PanelWindow {
        id: panel
        visible: root.menuVisible
        WlrLayershell.namespace: "quickshell:startmenu"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors { top: !root.waybarAtBottom; bottom: root.waybarAtBottom; right: true }
        margins { top: 2; right: root.waybarSideMargin; bottom: 2 }
        width: 340
        height: mainCol.implicitHeight + 32
        color: "transparent"

        HyprlandFocusGrab {
            id: focusGrab
            windows: [panel]
            active: false
            onCleared: { if(!active) root.menuVisible = false }
        }
        Connections { target: root; function onMenuVisibleChanged() {
            if(root.menuVisible) grabDelayTimer.restart()
            else focusGrab.active = false
        }}
        Timer { id:grabDelayTimer; interval:80; repeat:false; onTriggered: { if(root.menuVisible) focusGrab.active=true } }

        Rectangle {
            id: panelRect
            anchors.fill: parent
            color: root.cPanelBg
            radius: 20
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
                    // User avatar — layer.enabled composites children through rounded mask
                    Rectangle { width:36;height:36;radius:18;color:root.cSurfHi
                        layer.enabled:true
                        Image { anchors.fill:parent; fillMode:Image.PreserveAspectCrop; source:"file://"+Quickshell.env("HOME")+"/.config/hyprcandy/user-icon.png"; smooth:true; visible:status===Image.Ready }
                        Text { anchors.centerIn:parent; visible:parent.children[0].status!==Image.Ready; text:"󰀄"; font.pixelSize:20; font.family:"Symbols Nerd Font Mono"; color:root.cOnSurfVar }
                    }
                    ColumnLayout { Layout.fillWidth:true; spacing:1
                        Text { text:Quickshell.env("USER"); color:root.cOnSurf; font.pixelSize:13; font.weight:Font.Medium }
                        Text { text:Qt.formatDate(new Date(),"ddd d MMM")+" · "+Qt.formatTime(new Date(),"hh:mm"); color:root.cOnSurfVar; font.pixelSize:10 }
                    }
                    // Recorder + screenshot
                    Rectangle {
                        width:30;height:30;radius:15
                        color:rrh.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18):Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                        border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.55)
                        Behavior on color{ColorAnimation{duration:100}}
                        Text { anchors.centerIn:parent; text:"󰑋"; font.pixelSize:15; font.family:"Symbols Nerd Font Mono"
                            color:root.isRecording?root.cErr:root.cOnSurfVar
                            SequentialAnimation on opacity { running:root.isRecording; loops:Animation.Infinite
                                NumberAnimation{to:0.2;duration:500}
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
                }

                Rectangle { Layout.fillWidth:true; height:1; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.25) }

                // ── Brightness ────────────────────────────────────────────
                RowLayout { Layout.fillWidth:true; spacing:10
                    Text { text:"󰃟"; font.pixelSize:16; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary }
                    Text { text:"Brightness"; color:root.cOnSurfVar; font.pixelSize:12; Layout.preferredWidth:68 }
                    SliderBg {
                        Layout.fillWidth:true; height:16
                        value:root.backlightValue
                        onMoved: function(v){ root.backlightValue=v; root.setBacklight(v) }
                        gradA:root.cInvPrimary; gradB:root.cOnPrim; track:root.cOutVar
                    }
                    Text { text:Math.round(root.backlightValue*100)+"%"; color:root.cOnSurfVar; font.pixelSize:10; Layout.preferredWidth:28; horizontalAlignment:Text.AlignRight }
                }

                // ── Volume ────────────────────────────────────────────────
                RowLayout { Layout.fillWidth:true; spacing:10
                    Text { text:root.volumeMuted?"󰖁":"󰕾"; font.pixelSize:16; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary
                        MouseArea{anchors.fill:parent;cursorShape:Qt.PointingHandCursor;onClicked:root.toggleMute()}
                    }
                    Text { text:"Volume"; color:root.cOnSurfVar; font.pixelSize:12; Layout.preferredWidth:68 }
                    SliderBg {
                        Layout.fillWidth:true; height:16
                        value:root.volumeValue
                        onMoved: function(v){ root.volumeValue=v; root.setVolume(v) }
                        gradA:root.cInvPrimary; gradB:root.cOnPrim; track:root.cOutVar
                    }
                    Text { text:Math.round(root.volumeValue*100)+"%"; color:root.cOnSurfVar; font.pixelSize:10; Layout.preferredWidth:28; horizontalAlignment:Text.AlignRight }
                }

                Rectangle { Layout.fillWidth:true; height:1; color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.25) }

                // ── Network ────────────────────────────────────────────────
                ColumnLayout { Layout.fillWidth:true; spacing:4
                    RowLayout { Layout.fillWidth:true; spacing:10
                        Text { text:"󰤨"; font.pixelSize:15; font.family:"Symbols Nerd Font Mono"
                            color:root.networkStatus==="connected"?root.cPrimary:root.cOnSurfVar }
                        ColumnLayout { Layout.fillWidth:true; spacing:0
                            Text { text:root.networkSSID||"Not connected"; color:root.cOnSurf; font.pixelSize:12; elide:Text.ElideRight }
                            Text { text:root.networkStatus; color:root.cOnSurfVar; font.pixelSize:10; opacity:0.7; visible:root.networkStatus!=="" }
                        }
                        Rectangle {
                            width:24;height:24;radius:6
                            color:nxh.containsMouse?Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.15):"transparent"
                            border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.55)
                            Behavior on color{ColorAnimation{duration:100}}
                            Text { anchors.centerIn:parent; text:root.networkExpanded?"󰁆":"󰁄"; font.pixelSize:13; font.family:"Symbols Nerd Font Mono"; color:root.cPrimary }
                            MouseArea{id:nxh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{
                                root.networkExpanded=!root.networkExpanded
                                if(root.networkExpanded&&!netScanProc.running) netScanProc.running=true
                            }}
                        }
                    }

                    // Network list (expanded)
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
                                    }
                                    MouseArea{id:nh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{
                                        if(netDelegate.modelData.active) return
                                        if(netDelegate.modelData.secure) netDelegate._showPass=!netDelegate._showPass
                                        else root.connectNetwork(netDelegate.modelData.ssid,"")
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
                    color:logh.containsMouse?Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.18):Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.6)
                    border.width:1; border.color:Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.40)
                    Behavior on color{ColorAnimation{duration:120}}
                    RowLayout { anchors.centerIn:parent; spacing:8
                        Text { text:"󰗼"; font.pixelSize:16; font.family:"Symbols Nerd Font Mono"; color:logh.containsMouse?root.cErr:root.cOnSurfVar; Behavior on color{ColorAnimation{duration:120}} }
                        Text { text:"Logout"; color:logh.containsMouse?root.cErr:root.cOnSurfVar; font.pixelSize:12; font.weight:Font.Medium; Behavior on color{ColorAnimation{duration:120}} }
                    }
                    MouseArea{id:logh;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:{ root.menuVisible=false; if(!logoutProc.running) logoutProc.running=true }}
                }

                Item { height:4 }
            }
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
        property color gradA:  root.cInvPrimary   // inversePrimary — passed by callers too
        property color gradB:  root.cOnPrim        // onPrimary
        property color track:  root.cOutVar        // outlineVariant
        property color accent: root.cPrimary       // live matugen primary — border + thumb
        signal moved(real v)

        // Track (height 8, radius 4, 1px primary border)
        Item {
            y:(parent.height-8)/2; width:parent.width; height:8

            Rectangle {
                anchors.fill:parent; radius:4
                color:Qt.rgba(sl.track.r,sl.track.g,sl.track.b,0.28)
                border.width:1; border.color:Qt.rgba(sl.accent.r,sl.accent.g,sl.accent.b,0.6)
            }

            // Filled gradient — inner rect sized to full track width, clip Item limits visible area
            Item {
                x:1; y:1
                width:  Math.max(0, (parent.width-2) * sl.value)
                height: parent.height - 2
                clip:   true
                Rectangle {
                    width:  sl.width   // full slider width so gradient proportions are consistent
                    height: parent.height
                    radius: 3
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position:0.0; color:sl.gradA }
                        GradientStop { position:1.0; color:sl.gradB }
                    }
                }
            }

            // Thumb — circle centered on the fill edge
            Rectangle {
                width:12; height:12; radius:6
                x: Math.max(-4, Math.min(parent.width-8, (parent.width)*sl.value - 6))
                y: (parent.height-12)/2
                color:  sl.accent
                border.width:1; border.color:Qt.rgba(sl.accent.r,sl.accent.g,sl.accent.b,0.9)
            }
        }

        MouseArea {
            anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
            preventStealing:true
            onPressed:        function(m){ const v=Math.max(0,Math.min(1,m.x/width)); sl.value=v; sl.moved(v) }
            onPositionChanged:function(m){ if(pressed){ const v=Math.max(0,Math.min(1,m.x/width)); sl.value=v; sl.moved(v) } }
            onWheel:          function(e){
                const step=0.02*(e.angleDelta.y>0?1:-1)
                const v=Math.max(0,Math.min(1,sl.value+step))
                sl.value=v; sl.moved(v)
            }
        }
    }
}
