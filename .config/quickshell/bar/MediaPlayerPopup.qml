pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

// ── Media Player Popup + Widget ────────────────────────────────────────────
//  Self-contained: owns its own playerctl, art, position, seek, volume, and
//  radial cava processes. UI ported directly from candylock/shell.qml media
//  card with Theme.c* color palette for consistent styling across bar widgets.
//
//  Left-click bar module  → top-layer popup (tracks left-island/bar left
//  margin + top/bottom position, mirrors ClockPopup's popup behavior).
//  Right-click bar module → bottom-layer draggable widget (replaces the old
//  GJS floating media player).

Item {
    id: scope

    readonly property bool _active: MediaPlayerPopupState.visible || MediaPlayerPopupState.widgetVisible

    property var  mediaPlayers:       []
    property int  activePlayerIndex:  0
    readonly property var activePlayer: (mediaPlayers.length > 0 && activePlayerIndex < mediaPlayers.length)
        ? mediaPlayers[activePlayerIndex]
        : null

    property string mediaSource:        activePlayer ? activePlayer.name   : ""
    property string mediaStatus:        activePlayer ? activePlayer.status : "Stopped"
    property string mediaTitle:         activePlayer ? (activePlayer.title || "No media") : "No media"
    property string mediaArtist:        activePlayer ? activePlayer.artist : ""
    property string mediaArtUrl:        activePlayer ? activePlayer.artUrl : ""
    property string _circularArtPath:   activePlayer ? (activePlayer.circularArtPath || "") : ""
    property string mediaShuffleStatus: activePlayer ? activePlayer.shuffle : "off"
    property string mediaLoopStatus:    activePlayer ? activePlayer.loop : "none"
    property real   mediaPosition:      activePlayer ? activePlayer.position : 0
    property real   mediaDuration:      activePlayer ? activePlayer.duration : 0
    property real   _posTimestamp:      activePlayer ? activePlayer._posTimestamp : 0

    property real   _volumePct:         50
    property bool   _volumeMuted:       false
    property string _cavaRaw:           ""

    readonly property bool _playing: mediaStatus === "Playing"
    readonly property bool _anyPlaying: _playing || mediaPlayers.some(p => p.status === "Playing")

    // ── MPRIS Metadata Watcher ────────────────────────────────────────────
    Process {
        id: pctlProc
        command: ["playerctl", "-F", "-a", "metadata", "--format",
            "{{playerName}}\t{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}\t{{shuffle}}\t{{loop}}"]
        running: scope._active
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const p = line.split("\t")
                if (p.length < 1) return
                const name      = p[0].trim()
                if (!name) return
                const status    = (p.length > 1 ? p[1].trim() : "") || "Stopped"
                const url       = p.length > 2 ? p[2].trim() : ""
                const title     = p.length > 3 ? p[3].trim() : ""
                const artist    = p.length > 4 ? p[4].trim() : ""
                const shuffle   = (p.length > 5 ? p[5].trim() : "off").toLowerCase()
                const loop      = (p.length > 6 ? p[6].trim() : "none").toLowerCase()

                let list = scope.mediaPlayers.slice()
                let idx = list.findIndex(item => item.name === name)

                if (status === "Stopped" && !title && !artist) {
                    if (idx >= 0) {
                        list.splice(idx, 1)
                        scope.mediaPlayers = list
                        if (scope.activePlayerIndex >= scope.mediaPlayers.length) {
                            scope.activePlayerIndex = Math.max(0, scope.mediaPlayers.length - 1)
                        }
                    }
                    return
                }

                let item = idx >= 0 ? Object.assign({}, list[idx]) : {
                    name: name,
                    status: "Stopped",
                    artUrl: "",
                    title: "",
                    artist: "",
                    shuffle: "off",
                    loop: "none",
                    position: 0,
                    duration: 0,
                    _posTimestamp: 0,
                    circularArtPath: ""
                }

                const titleChanged = item.title !== title
                const urlChanged   = item.artUrl !== url

                item.status  = status
                item.artUrl  = url
                item.title   = title
                item.artist  = artist
                item.shuffle = shuffle
                item.loop    = loop

                if (titleChanged || urlChanged) {
                    item.position = 0
                    item.duration = 0
                    item._posTimestamp = 0
                    item.circularArtPath = ""
                    if (url) artProc.launchForPlayer(name, url)
                }

                if (idx >= 0) {
                    list[idx] = item
                } else {
                    list.push(item)
                }

                scope.mediaPlayers = list
                if (scope.activePlayerIndex >= scope.mediaPlayers.length) {
                    scope.activePlayerIndex = Math.max(0, scope.mediaPlayers.length - 1)
                }
            }
        }
        onExited: pctlRestartTimer.restart()
    }
    Timer {
        id: pctlRestartTimer; interval: 3000; repeat: false
        onTriggered: if (scope._active && !pctlProc.running) pctlProc.running = true
    }

    // ── Circular Art Generation (ImageMagick) ─────────────────────────────
    Process {
        id: artProc
        property string _dst: "/tmp/qs_mp_widget_art.png"
        property string _cmd: "true"
        property string _targetPlayer: ""
        command: ["bash", "-c", artProc._cmd]
        function launchForPlayer(playerName, url) {
            const s   = 92
            const r   = 46
            const src = url.startsWith("file://") ? url.substring(7) : url
            const esc = src.replace(/'/g, "'\\''")
            const hash = Math.abs((playerName + url).split('').reduce(
                (a,b)=>{a=((a<<5)-a)+b.charCodeAt(0);return a&a},0)).toString(16)
            _targetPlayer = playerName
            _dst = "/tmp/qs_mp_widget_art_" + hash + ".png"
            _cmd = "SRC='" + esc + "'; DST='" + _dst + "'; S=" + s + "; R=" + r + "; " +
                "[ -f \"$SRC\" ] || { curl -sf --max-time 8 \"$SRC\" " +
                "  -o /tmp/qs_mp_widget_raw.png 2>/dev/null && SRC=/tmp/qs_mp_widget_raw.png; }; " +
                "magick \"$SRC\" -resize ${S}x${S}^ -gravity center -extent ${S}x${S} " +
                "  \\( +clone -alpha extract -fill black -colorize 100 " +
                "     -fill white -draw \"roundrectangle 0,0 $((S-1)),$((S-1)) $R,$R\" \\) " +
                "-alpha off -compose CopyOpacity -composite -strip \"$DST\""
            if (running) running = false
            running = true
        }
        onExited: function(code) {
            if (code === 0 && artProc._targetPlayer !== "") {
                const ver = _dst.includes("?") ? _dst : _dst + "?v=" + Date.now()
                let list = scope.mediaPlayers.slice()
                let idx = list.findIndex(p => p.name === artProc._targetPlayer)
                if (idx >= 0) {
                    let item = Object.assign({}, list[idx])
                    item.circularArtPath = ver
                    list[idx] = item
                    scope.mediaPlayers = list
                }
            }
        }
    }

    // ── Track Position & Duration Polling ────────────────────────────────
    Process {
        id: posProc
        property string _raw: ""
        command: ["bash", "-c",
            "P='" + (scope.mediaSource ? scope.mediaSource.replace(/'/g, "'\\''") : "") + "'; " +
            "if [ -n \"$P\" ]; then " +
            "  printf '%s|%s\\n' \"$(playerctl -p \"$P\" position 2>/dev/null)\" \"$(playerctl -p \"$P\" metadata mpris:length 2>/dev/null)\"; " +
            "else " +
            "  printf '%s|%s\\n' \"$(playerctl position 2>/dev/null)\" \"$(playerctl metadata mpris:length 2>/dev/null)\"; " +
            "fi"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { if (l.trim()) posProc._raw = l.trim() }
        }
        onRunningChanged: if (running) _raw = ""
        onExited: function() {
            const parts = _raw.split("|")
            if (parts.length >= 2 && scope.activePlayer) {
                const pos = parseFloat(parts[0])
                const dur = parseFloat(parts[1]) / 1000000.0
                let list = scope.mediaPlayers.slice()
                let idx = scope.activePlayerIndex
                if (idx >= 0 && idx < list.length) {
                    let item = Object.assign({}, list[idx])
                    if (!isNaN(pos) && pos >= 0) {
                        item.position = pos
                        item._posTimestamp = Date.now()
                    }
                    if (!isNaN(dur) && dur > 0) item.duration = dur
                    list[idx] = item
                    scope.mediaPlayers = list
                }
            }
            _raw = ""
        }
    }
    Timer {
        interval: 1000; repeat: true
        running: scope._playing && scope._active
        onTriggered: if (!posProc.running) posProc.running = true
        Component.onCompleted: if (scope._active) posProc.running = true
    }
    Timer {
        interval: 200; repeat: true
        running: scope._playing && scope.mediaDuration > 0 && scope._posTimestamp > 0
        onTriggered: {
            const now     = Date.now()
            const elapsed = (now - scope._posTimestamp) / 1000.0
            let list = scope.mediaPlayers.slice()
            let idx  = scope.activePlayerIndex
            if (idx >= 0 && idx < list.length) {
                let item = Object.assign({}, list[idx])
                item._posTimestamp = now
                item.position = Math.min(item.position + elapsed, item.duration)
                list[idx] = item
                scope.mediaPlayers = list
            }
        }
    }

    // ── Seek Control ──────────────────────────────────────────────────────
    Process {
        id: seekProc
        property string _cmd: "true"
        command: ["bash", "-c", seekProc._cmd]
        function seek(secs) {
            const target = scope.mediaSource ? ("-p '" + scope.mediaSource.replace(/'/g, "'\\''") + "' ") : ""
            _cmd = "playerctl " + target + "position " + secs.toFixed(1)
            if (running) running = false
            running = true
        }
    }

    // ── Playerctl Action Handler ──────────────────────────────────────────
    Process {
        id: ctlProc
        property string _c: "true"
        command: ["bash", "-c", ctlProc._c]
    }
    function playerAction(cmd) {
        let argv
        const target = scope.mediaSource ? ("-p '" + scope.mediaSource.replace(/'/g, "'\\''") + "' ") : ""
        if (cmd === "shuffle") {
            argv = "playerctl " + target + "shuffle toggle"
        } else if (cmd === "loop") {
            const order = ["none", "track", "playlist"]
            const names = ["None", "Track", "Playlist"]
            const cur   = Math.max(0, order.indexOf(scope.mediaLoopStatus))
            argv = "playerctl " + target + "loop " + names[(cur + 1) % 3]
        } else {
            argv = "playerctl " + target + cmd
        }

        if (cmd === "play-pause" && scope.activePlayer) {
            let list = scope.mediaPlayers.slice()
            let idx = scope.activePlayerIndex
            if (idx >= 0 && idx < list.length) {
                let item = Object.assign({}, list[idx])
                item.status = item.status === "Playing" ? "Paused" : "Playing"
                list[idx] = item
                scope.mediaPlayers = list
            }
        }

        ctlProc._c = argv
        if (ctlProc.running) ctlProc.running = false
        ctlProc.running = true
    }

    // ── Volume Control (pactl) ────────────────────────────────────────────
    Process {
        id: volReadProc
        command: ["bash", "-c", "pactl get-sink-volume @DEFAULT_SINK@ | grep -oP '[0-9]+(?=%)' | head -1; " +
                                "pactl get-sink-mute  @DEFAULT_SINK@ | grep -oP '(?<=Mute: )\\w+'"]
        running: scope._active
        stdout: SplitParser {
            splitMarker: "\n"
            property int _lineIdx: 0
            onRead: function(l) {
                const t = l.trim()
                if (!t) return
                if (_lineIdx === 0) {
                    const v = parseInt(t)
                    if (!isNaN(v)) scope._volumePct = Math.min(150, Math.max(0, v))
                } else {
                    scope._volumeMuted = (t === "yes")
                }
                _lineIdx++
            }
        }
        onRunningChanged: if (running) stdout._lineIdx = 0
        onExited: volRefreshTimer.restart()
    }
    Timer { id: volRefreshTimer; interval: 2000; repeat: false
        onTriggered: if (scope._active && !volReadProc.running) volReadProc.running = true }

    Process {
        id: volSetProc
        property string _cmd: "true"
        command: ["bash", "-c", volSetProc._cmd]
    }
    function setVolume(pct) {
        const clamped = Math.max(0, Math.min(150, Math.round(pct)))
        scope._volumePct = clamped
        volSetProc._cmd  = "pactl set-sink-volume @DEFAULT_SINK@ " + clamped + "%"
        if (!volSetProc.running) volSetProc.running = true
    }
    function toggleMute() {
        scope._volumeMuted = !scope._volumeMuted
        volSetProc._cmd = "pactl set-sink-mute @DEFAULT_SINK@ toggle"
        if (!volSetProc.running) volSetProc.running = true
    }

    // ── Radial Cava Visualizer ────────────────────────────────────────────
    Process {
        id: cavaProc
        property string _cfgPath: "/tmp/qs-mp-widget-cava.ini"
        command: {
            const bars  = 64
            const maxR  = 7
            const lines = [
                "[general]", "bars = " + bars, "framerate = 60", "",
                "[output]", "method = raw", "raw_target = /dev/stdout",
                "data_format = ascii", "ascii_max_range = " + maxR, "channels = mono"
            ]
            const args = lines.map(l => "'" + l.replace(/'/g,"'\\''") + "'").join(" ")
            return ["bash", "-c",
                "printf '%s\\n' " + args + " > " + _cfgPath + " && cava -p " + _cfgPath]
        }
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (t && !t.startsWith("[")) scope._cavaRaw = t
            }
        }
        onExited: cavaRestartTimer.restart()
    }
    Timer { id: cavaRestartTimer; interval: 2000; repeat: false
        onTriggered: if (scope._anyPlaying && !cavaProc.running) cavaProc.running = true }

    Connections {
        target: scope
        function on_AnyPlayingChanged() {
            if (scope._anyPlaying) {
                if (!cavaProc.running) cavaProc.running = true
            } else {
                cavaProc.running = false
                scope._cavaRaw = ""
            }
        }
        function on_PlayingChanged() {
            if (scope._playing && !posProc.running) posProc.running = true
        }
        // Central lifecycle for popup + widget shared processes — either
        // surface being open keeps playerctl/volume/cava running; both
        // closing tears everything down.
        function on_ActiveChanged() {
            if (scope._active) {
                if (!pctlProc.running)    pctlProc.running    = true
                if (!volReadProc.running) volReadProc.running = true
                if (scope._anyPlaying && !cavaProc.running) cavaProc.running = true
            } else {
                pctlProc.running    = false
                cavaProc.running    = false
                volReadProc.running = false
            }
        }
    }

    // ── Media Player Card (shared UI for popup + widget) ─────────────────
    component MediaPlayerCard: Rectangle {
        required property var root

        id: mediaCard
        implicitWidth:  450
        implicitHeight: Math.max(mediaCardRow.implicitHeight + 28, 198)
        radius: 20
        color: Theme.blurBackground
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                              Config.barBorderColor.b, Config.barBorderAlpha)

        // Top Glass Sheen
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 40; radius: 40; color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0.06) }
                GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0.00) }
            }
        }

        RowLayout {
            id: mediaCardRow
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
            spacing: 12

            // ── Left Sidebar Pill (Minimized Indicators & Tab Switcher) ───
            Rectangle {
                id: sidebarPill
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 14
                implicitHeight: Math.max(14, 14 + (root.mediaPlayers.length - 1) * 12)
                radius: 7
                color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.7)
                border.width: 1
                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                Behavior on implicitHeight { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    Repeater {
                        model: root.mediaPlayers.length > 0 ? root.mediaPlayers.length : 1
                        delegate: Item {
                            required property int index
                            width: 10; height: 8
                            readonly property var pObj: index < root.mediaPlayers.length ? root.mediaPlayers[index] : null
                            readonly property bool isActive: index === root.activePlayerIndex

                            Rectangle {
                                anchors.centerIn: parent
                                width: parent.isActive ? 6 : 4
                                height: parent.isActive ? 6 : 4
                                radius: width / 2
                                color: parent.isActive
                                    ? Theme.cPrimary
                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.35)
                                Behavior on width { NumberAnimation { duration: 150 } }
                                Behavior on height { NumberAnimation { duration: 150 } }
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -3
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.activePlayerIndex = index
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    preventStealing: true
                    onWheel: function(e) {
                        const count = Math.max(1, root.mediaPlayers.length)
                        if (count <= 1) return
                        if (e.angleDelta.y < 0) {
                            root.activePlayerIndex = (root.activePlayerIndex + 1) % count
                        } else if (e.angleDelta.y > 0) {
                            root.activePlayerIndex = (root.activePlayerIndex - 1 + count) % count
                        }
                    }
                }
            }

            // ── Left Column: Title, Artist, Seek Bar, Volume, Controls ──
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 6

                // Title
                Text {
                    Layout.fillWidth: true
                    text: root.mediaTitle !== "" ? root.mediaTitle : "No media"
                    color: Theme.cOnSurf
                    font.pixelSize: 13; font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                // Artist
                Text {
                    Layout.fillWidth: true
                    text: root.mediaArtist
                    color: Theme.cOnSurfVar
                    font.pixelSize: 11; elide: Text.ElideRight
                    visible: text !== ""
                }

                // ── Seek Bar ──────────────────────────────────────────
                Item {
                    id: seekBarItem
                    Layout.fillWidth: true
                    height: 28
                    visible: root.mediaDuration > 0

                    property bool _drag:     false
                    property real _dragNorm: 0
                    readonly property real _norm: root.mediaDuration > 0
                        ? (_drag ? _dragNorm
                                 : Math.max(0, Math.min(1, root.mediaPosition / root.mediaDuration)))
                        : 0

                    function _fmt(s) {
                        const m  = Math.floor(s / 60)
                        const ss = Math.floor(s % 60)
                        return m + ":" + (ss < 10 ? "0" : "") + ss
                    }

                    Text {
                        anchors.left: parent.left; anchors.top: parent.top
                        text: seekBarItem._fmt(
                            seekBarItem._drag
                                ? seekBarItem._dragNorm * root.mediaDuration
                                : root.mediaPosition)
                        color: Theme.cOnSurfVar; font.pixelSize: 9
                    }
                    Text {
                        anchors.right: parent.right; anchors.top: parent.top
                        text: seekBarItem._fmt(root.mediaDuration)
                        color: Theme.cOnSurfVar; font.pixelSize: 9
                    }

                    Item {
                        id: trough
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        height: 14

                        Rectangle {
                            anchors.fill: parent; radius: 7
                            color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
                            border.width: 1
                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                        }

                        Item {
                            x: 3; y: 3
                            width:  Math.max(0, (trough.width - 6) * seekBarItem._norm)
                            height: 8; clip: true
                            Rectangle {
                                width: trough.width - 6; height: 8; radius: 4
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.cInversePrimary }
                                    GradientStop { position: 1.0; color: Theme.cOnSecondary }
                                }
                            }
                        }

                        Text {
                            text: "󰟃"
                            font.family: "Symbols Nerd Font Mono"; font.pixelSize: 10
                            color: Theme.cWc4
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
                            onPositionChanged: function(m) { if (pressed) seekBarItem._dragNorm = _n(m.x) }
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

                // ── Volume Control ────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: root._volumeMuted ? "󰝟" : "󰕾"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 14
                        color: Theme.cWc5
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleMute()
                        }
                    }
                    Item {
                        id: volBarItem
                        Layout.fillWidth: true
                        height: 14
                        readonly property real _norm: root._volumePct / 100.0

                        Rectangle {
                            anchors.fill: parent; radius: 7
                            color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
                            border.width: 1
                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                        }

                        Item {
                            x: 3; y: 3
                            width: Math.max(0, (volBarItem.width - 6) * volBarItem._norm)
                            height: 8; clip: true
                            Rectangle {
                                width: volBarItem.width - 6; height: 8; radius: 4
                                gradient: Gradient {
                                    orientation: Gradient.Horizontal
                                    GradientStop { position: 0.0; color: Theme.cInversePrimary }
                                    GradientStop { position: 1.0; color: Theme.cOnSecondary }
                                }
                            }
                        }

                        Text {
                            text: "󰟃"
                            font.family: "Symbols Nerd Font Mono"; font.pixelSize: 10
                            color: Theme.cWc4
                            style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.25)
                            x: {
                                const tw = volBarItem.width - 6
                                const cx = 3 + tw * volBarItem._norm - implicitWidth / 2
                                return Math.max(1, Math.min(volBarItem.width - implicitWidth - 1, cx))
                            }
                            y: (volBarItem.height - implicitHeight) / 2
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            preventStealing: true
                            function _n(mx) {
                                return Math.max(0, Math.min(100, (mx / volBarItem.width) * 100))
                            }
                            onClicked:         function(m) { root.setVolume(_n(m.x)) }
                            onPositionChanged: function(m) { if (pressed) root.setVolume(_n(m.x)) }
                            onWheel: function(e) {
                                const step = e.angleDelta.y > 0 ? 5 : -5
                                root.setVolume(root._volumePct + step)
                                e.accepted = true
                            }
                        }
                    }
                }

                // ── Playback Controls ─────────────────────────────────
                RowLayout {
                    spacing: 6

                    Repeater {
                        model: [
                            { i: "󰒞", c: "shuffle",
                              a: root.mediaShuffleStatus === "on" },
                            { i: "󰒮", c: "previous",   a: false },
                            { i: root.mediaStatus === "Playing" ? "󰏤" : "󰐊",
                              c: "play-pause",  a: false },
                            { i: "󰒭", c: "next",        a: false },
                            { i: root.mediaLoopStatus === "track"    ? "󰑘"
                                 : (root.mediaLoopStatus === "playlist" ? "󰑖" : "󰑗"),
                              c: "loop",
                              a: root.mediaLoopStatus !== "none" }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: 30; height: 30; radius: 6
                            readonly property bool isCenter: index === 2
                            readonly property bool isActive: modelData.a
                            color: bma.containsMouse
                                ? (isActive
                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
                                    : (isCenter
                                        ? Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.22)
                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)))
                                : (isActive
                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                                    : "transparent")
                            border.width: isActive ? 2 : 1
                            border.color: isActive
                                ? Theme.cPrimary
                                : (isCenter
                                    ? Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.65)
                                    : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.50))
                            Behavior on color { ColorAnimation { duration: 100 } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.i
                                font.pixelSize: 14; font.family: "Symbols Nerd Font Mono"
                                color: bma.containsMouse || parent.isActive
                                    ? (parent.isCenter ? Theme.cOnSurf : Theme.cPrimary)
                                    : Theme.cOnSurfVar
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                            MouseArea {
                                id: bma; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playerAction(modelData.c)
                            }
                        }
                    }
                }
            }

            // ── Right Column: Radial Cava + Spinning Album Disc ─────
            Item {
                width: 170; height: 170
                Layout.alignment: Qt.AlignVCenter

                Canvas {
                    id: radialCava
                    anchors.fill: parent
                    visible: root._anyPlaying
                    property var _bars:     []
                    property int _barCount: 64

                    Connections {
                        target: scope
                        function on_CavaRawChanged() {
                            if (!root._cavaRaw || !radialCava.visible) return
                            const vals = root._cavaRaw.split(";")
                            radialCava._bars = []
                            for (let i = 0; i < radialCava._barCount; i++) {
                                const v = parseInt(vals[i % vals.length])
                                radialCava._bars.push(isNaN(v) ? 0 : v / 7.0)
                            }
                            radialCava.requestPaint()
                        }
                    }

                    onPaint: {
                        const ctx    = getContext("2d")
                        ctx.reset()
                        const cx = width / 2, cy = height / 2
                        const innerR  = 52
                        const maxBarH = 28

                        for (let i = 0; i < _barCount; i++) {
                            const amp = _bars[i] || 0
                            if (amp < 0.01) continue
                            const angle = (i / _barCount) * Math.PI * 2 - Math.PI / 2
                            const barH  = 2 + amp * (maxBarH - 2)
                            ctx.beginPath()
                            ctx.strokeStyle = Qt.rgba(
                                Theme.cWc6.r, Theme.cWc6.g, Theme.cWc6.b,
                                0.40 + amp * 1.00).toString()
                            ctx.lineWidth = 1.5
                            ctx.lineCap   = "round"
                            ctx.moveTo(cx + Math.cos(angle) * innerR,
                                       cy + Math.sin(angle) * innerR)
                            ctx.lineTo(cx + Math.cos(angle) * (innerR + barH),
                                       cy + Math.sin(angle) * (innerR + barH))
                            ctx.stroke()
                        }
                    }
                }

                Rectangle {
                    id: artDisc
                    anchors.centerIn: parent
                    width: 92; height: 92; radius: 46
                    color: Theme.cSurfHi
                    antialiasing: true
                    layer.enabled: true
                    layer.smooth:  true

                    Image {
                        id: artImg
                        anchors.fill: parent
                        source: root._circularArtPath !== ""
                            ? ("file://" + root._circularArtPath.split("?")[0] +
                               "?v="     + root._circularArtPath.split("?")[1])
                            : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true; cache: false
                        visible: root._circularArtPath !== "" && status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent; visible: !artImg.visible
                        text: "󰽲"; font.pixelSize: 32; font.family: "Symbols Nerd Font Mono"
                        color: Theme.cOnSurfVar; opacity: 0.35
                    }
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 16000
                        loops: Animation.Infinite
                        running: root.mediaStatus === "Playing"
                    }
                }
            }
        }
    }

    // ── Top-Layer Popup Surface ─────────────────────────────────────────
    //  Anchored to the left, tracking the same left margin as the bar/
    //  left-island's leftmost module (mirrors WorkspacesPopup's left-margin
    //  logic) and the same top/bottom gap logic as ClockPopup/other bar
    //  popups (mirrors Config.barPosition — "top" or "bottom").
    PanelWindow {
        id: mpPopup
        readonly property bool _barAtBottom: Config.barPosition === "bottom"
        readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop) : Config.outerMarginTop) + Config.barHeight + 4
        readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom) : Config.outerMarginBottom) + Config.barHeight + 4
        readonly property real _leftMargin: Config.barMode === "shell" ? Config.shellModuleSideMargin : Config.outerMarginSide

        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true }
        margins {
            top:    _barAtBottom ? 0 : _barGap
            bottom: _barAtBottom ? _barGapBot : 0
            left:   _leftMargin
        }

        implicitWidth:  mpPanel.implicitWidth + 8
        implicitHeight: mpPanel.implicitHeight + 8
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        visible: MediaPlayerPopupState.visible

        Connections {
            target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
            ignoreUnknownSignals: true
            function onAddressChanged() {
                if (HyprlandFocusedClient.address !== "")
                    MediaPlayerPopupState.close()
            }
        }

        MouseArea { anchors.fill: parent; z: -1; onClicked: MediaPlayerPopupState.close() }

        MediaPlayerCard {
            id: mpPanel
            root: scope
            anchors.left: parent.left
        }
    }

    // ── Overlay-Layer Draggable Widget Surface ─────────────────────────────
    PinnedWidgetWindow {
        id: mediaWidget
        active: MediaPlayerPopupState.widgetVisible
        widgetNamespace: "quickshell"
        
        WlrLayershell.layer: WlrLayer.Overlay

        onActiveChanged: {
            if (active) {
                mediaWidget.posX = MediaPlayerPopupState.widgetX
                mediaWidget.posY = MediaPlayerPopupState.widgetY
            }
            // process lifecycle handled centrally by the on_ActiveChanged Connections above
        }
        onPositionCommitted: function(x, y) {
            MediaPlayerPopupState.widgetX = Math.round(x)
            MediaPlayerPopupState.widgetY = Math.round(y)
        }

        // Widget Card Body
        MediaPlayerCard { root: scope }
    }
}
