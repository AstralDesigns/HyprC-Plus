pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
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
        // Same transport path the bar module (MediaPlayerState.ctl) uses — it
        // drives QtWebEngine/Chromium fine: {{playerName}} reports the short
        // "chromium" and CanPlay/CanPause go true once media is loaded.
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

    // ── Equalizer (EasyEffects) ─────────────────────────────────────────────
    // 10-band UI driving the 10-band EasyEffects output preset (full range —
    // EasyEffects only supports 10/12/15/30 bands). Gains + active preset
    // persist through Config; edits are debounced, written to
    // ~/.local/share/easyeffects/output/QS-EQ.json (EE 8 data dir) and
    // reloaded via `easyeffects -l QS-EQ` (service auto-started if needed).
    readonly property var  eqFreqs:   [62, 125, 250, 500, 1000, 2000, 4000, 7000, 11000, 15000]
    readonly property var  eqFreqLbl: ["62", "125", "250", "500", "1k", "2k", "4k", "7k", "11k", "15k"]
    readonly property real eqMin:     -12
    readonly property real eqMax:      12
    readonly property var  eqPresets: ({
        "Flat":   [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "Bass":   [7, 6, 4, 1, 0, 0, 0, 0, -1, -2],
        "Treble": [0, 0, 0, 1, 3, 5, 6, 7, 7, 6],
        "Cinema": [6, 4, 0, -2, 1, 3, 4, 5, 4, 3],
        "Vocal":  [-2, 0, 3, 5, 4, 1, -1, -1, -2, -2],
        "Rock":   [5, 3, -1, -1, 2, 4, 5, 4, 3, 2],
        "Pop":    [-1, 2, 4, 4, 2, 0, -1, -1, -1, -1]
    })

    function _eqGains() {
        let g = Config.eqGains
        if (!Array.isArray(g) || g.length !== 10) g = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
        return g.slice()
    }
    function setEqGain(i, v) {
        let g = _eqGains()
        g[i] = Math.max(scope.eqMin, Math.min(scope.eqMax, Math.round(v * 2) / 2))
        Config.eqGains  = g
        Config.eqPreset = "Custom"
        eqApplyTimer.restart()
    }
    function applyEqPreset(name) {
        if (!scope.eqPresets[name]) return
        Config.eqGains  = scope.eqPresets[name].slice()
        Config.eqPreset = name
        eqApplyTimer.restart()
    }

    function _eqPresetJson() {
        const g     = _eqGains()
        const freqs = scope.eqFreqs
        const gains = g
        const bands = {}
        for (let i = 0; i < 10; i++) {
            bands["band" + i] = {
                frequency: freqs[i], gain: gains[i], mode: "RLC (BT)",
                mute: false, q: 4.36, slope: "x1", solo: false,
                type: "Bell", width: 4.0
            }
        }
        const eq = {
            balance: 0.0, bypass: false, decramp: "x2", "input-gain": 0.0,
            left: bands, right: bands, mode: "Stereo", "num-bands": 10,
            "output-gain": 0.0, "pitch-left": 1.0, "pitch-right": 1.0,
            "split-channels": false
        }
        // EE 8 load_blocklist() does json["output"]["blocklist"] with .at() —
        // the key MUST exist as a string array or loading fails with
        // "Wrong format in excluded apps list".
        return JSON.stringify({ output: { "equalizer#0": eq,
                                          blocklist: [],
                                          plugins_order: ["equalizer#0"] } }, null, 2)
    }
    function applyEq() {
        const json = _eqPresetJson().replace(/'/g, "'\\''")
        eqProc._cmd =
            "mkdir -p \"$HOME/.local/share/easyeffects/output\"; " +
            "printf \'%s\' '" + json + "' > \"$HOME/.local/share/easyeffects/output/QS-EQ.json\"; " +
            "pgrep -x easyeffects >/dev/null 2>&1 || { easyeffects --service-mode >/dev/null 2>&1 & sleep 2; }; " +
            "easyeffects -l QS-EQ >/dev/null 2>&1"
        if (eqProc.running) eqProc.running = false
        eqProc.running = true
    }

    Process {
        id: eqProc
        property string _cmd: "true"
        command: ["bash", "-c", eqProc._cmd]
    }
    Timer { id: eqApplyTimer; interval: 450; repeat: false; onTriggered: scope.applyEq() }

    // ── EQ vertical band slider ─────────────────────────────────────────────
    component EqBandSlider: Item {
        id: band
        required property real gain
        required property string label
        signal gainEdited(real g)
        readonly property real lo: -12
        readonly property real hi:  12
        readonly property real trackH: 120
        width: 34
        height: trackH + 18
        readonly property real norm:  (gain - lo) / (hi - lo)
        readonly property real knobY: trackH * (1 - norm)

        Rectangle {
            x: band.width / 2 - 3; width: 6; height: band.trackH; radius: 3
            color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.5)
            border.width: 1
            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
        }
        Rectangle {
            x: 0; width: band.width; height: 1; y: band.trackH / 2
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.30)
        }
        Rectangle {
            x: band.width / 2 - 3; width: 6; radius: 3
            y: Math.min(band.trackH / 2, band.knobY)
            height: Math.abs(band.trackH / 2 - band.knobY)
            color: Theme.cPrimary
        }
        Rectangle {
            width: 18; height: 10; radius: 5
            x: band.width / 2 - 9; y: band.knobY - 5
            color: Theme.cOnSecondary
            border.width: 1; border.color: Theme.cPrimary
        }
        Text {
            anchors { top: parent.top; topMargin: band.trackH + 2
                      horizontalCenter: parent.horizontalCenter }
            text: band.label
            font.pixelSize: 9; font.family: Config.labelFont
            color: Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.7)
        }
        MouseArea {
            anchors.fill: parent; anchors.margins: -4
            cursorShape: Qt.PointingHandCursor; preventStealing: true
            function toGain(my) {
                const n = 1 - Math.max(0, Math.min(1, my / band.trackH))
                return band.lo + n * (band.hi - band.lo)
            }
            onPressed:         function(m) { band.gainEdited(toGain(m.y)) }
            onPositionChanged: function(m) { if (pressed) band.gainEdited(toGain(m.y)) }
            onWheel: function(e) {
                band.gainEdited(band.gain + (e.angleDelta.y > 0 ? 1 : -1))
                e.accepted = true
            }
        }
    }

    // ── EQ preset pill button ───────────────────────────────────────────────
    component EqPill: Rectangle {
        id: pill
        required property string label
        required property bool active
        signal picked()
        width: pillText.implicitWidth + 20; height: 26; radius: 99
        color: active ? Theme.cSurfaceTint
             : pillMa.containsMouse
               ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
               : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.5)
        border.width: 0
        border.color: "transparent"
        Behavior on color { ColorAnimation { duration: 140 } }
        Text {
            id: pillText
            anchors.centerIn: parent
            text: pill.label
            font.pixelSize: 11; font.bold: pill.active
            color: pill.active ? Theme.cOnSecondary : Theme.cPrimary
        }
        MouseArea {
            id: pillMa
            anchors.fill: parent; hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: pill.picked()
        }
    }

    // ── Media Player Card (shared UI for popup + widget) ─────────────────
    component MediaPlayerCard: Item {
        required property var root
        property bool popupMode: false

        id: mediaCard
        implicitWidth:  450
        implicitHeight: Math.max(mediaCardRow.implicitHeight
                                 + (popupMode ? eqColumn.height + 12 : 28), 198)
        width:  implicitWidth
        height: implicitHeight

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled:      true
            maskSource:       mediaCardMask
            maskThresholdMin: 0.5
            maskSpreadAtMin:  1.0
        }

        Rectangle {
            id: mediaCardMask
            anchors.fill: parent
            radius: 20
            color: "white"
            opacity: 0
            layer.enabled: true
        }

        // Base card background
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: Theme.blurBackground
        }

        // Blurred album art background + 0.15 InversePrimary tint (margins 12, radius 16)
        Item {
            anchors.fill: parent
            anchors.margins: 12
            visible: bgArtImg.status === Image.Ready && root.mediaArtUrl !== ""
            opacity: visible ? 1.0 : 0.0
            Behavior on opacity { NumberAnimation { duration: 300 } }

            layer.enabled: true
            layer.effect: MultiEffect {
                maskEnabled:      true
                maskSource:       innerArtMask
                maskThresholdMin: 0.5
                maskSpreadAtMin:  1.0
            }

            Rectangle {
                id: innerArtMask
                anchors.fill: parent
                radius: 16
                color: "white"
                opacity: 0
                layer.enabled: true
            }

            Item {
                anchors.fill: parent
                layer.enabled: bgArtImg.visible
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 0.35
                    blurMax: 32
                }

                Image {
                    id: bgArtImg
                    anchors.fill: parent
                    source: {
                        const u = root.mediaArtUrl || ""
                        if (!u) return ""
                        if (u.startsWith("/")) return "file://" + u
                        return u
                    }
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    cache: false
                    visible: root.mediaArtUrl !== ""
                }
            }

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.3)
            }
        }

        // Card Border
        Rectangle {
            anchors.fill: parent
            radius: 20
            color: "transparent"
            border.width: Config.barBorderWidth
            border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                                  Config.barBorderColor.b, Config.barBorderAlpha)
        }

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
                    color: Theme.cOnSurf
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
                        color: Theme.cOnSurf; font.pixelSize: 9
                    }
                    Text {
                        anchors.right: parent.right; anchors.top: parent.top
                        text: seekBarItem._fmt(root.mediaDuration)
                        color: Theme.cOnSurf; font.pixelSize: 9
                    }

                    Item {
                        id: trough
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left; anchors.right: parent.right
                        height: 14

                        Rectangle {
                            anchors.fill: parent; radius: 99
                            color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.4)
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
                            font.family: "Symbols Nerd Font Mono"; font.pixelSize: 13
                            color: Theme.cPrimary
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
                            anchors.fill: parent; radius: 99
                            color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.5)
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
                            font.family: "Symbols Nerd Font Mono"; font.pixelSize: 13
                            color: Theme.cPrimary
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
                                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.75)
                                    : (isCenter
                                        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.75)
                                        : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.75)))
                                : (isActive
                                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.75)
                                    : Qt.rgba(Theme.cOnPrimary.r, Theme.cOnPrimary.g, Theme.cOnPrimary.b, 0.75))
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
                                    ? Theme.cOnSecondary : Theme.cPrimary
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
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.cWc11
                    }
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 16000
                        loops: Animation.Infinite
                        running: root.mediaStatus === "Playing"
                    }
                }
            }
        }

        // ── Equalizer section (popup only) ──────────────────────────────
        Column {
            id: eqColumn
            anchors {
                left: parent.left; right: parent.right
                top: mediaCardRow.bottom
                topMargin: -15
                leftMargin: 16; rightMargin: 16
            }
            spacing: 8
            visible: mediaCard.popupMode

            // "Equalizer · <preset>" as a compact segmented-style pill; the whole
            // pill is the expand/collapse toggle (chevron glyph removed). The x:24
            // wrapper keeps it aligned with the control buttons even though the
            // column margin is 16 now (widened for the 10-band slider container).
            Item {
                width: parent.width; height: eqToggle.height
                Rectangle {
                    id: eqToggle
                    x: 24
                    width: eqHeaderRow.implicitWidth + 22
                    height: 24; radius: 99
                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.5)
                    Row {
                        id: eqHeaderRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Equalizer"
                            font.pixelSize: 12; font.weight: Font.DemiBold
                            color: Theme.cOnSurf
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u00b7 " + Config.eqPreset
                            font.pixelSize: 11; color: Theme.cPrimary
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Config.eqExpanded = !Config.eqExpanded
                    }
                }
            }

            Column {
                id: eqBody
                width: parent.width
                spacing: 10
                // Smooth reveal: animate height + opacity (clipped) instead of
                // toggling visibility, mirroring the history panel expansion.
                height: Config.eqExpanded ? implicitHeight : 0
                Behavior on height  { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Behavior on opacity { NumberAnimation { duration: 200 } }
                opacity: Config.eqExpanded ? 1.0 : 0.0
                clip: true

                Item {
                    width: parent.width; height: eqTrack.height + 24
                    Rectangle {
                        anchors.centerIn: eqTrack
                        width:  eqTrack.width + 24
                        height: eqTrack.height + 24
                        radius: 14
                        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.25)
                    }
                    Item {
                        id: eqTrack
                        anchors.centerIn: parent
                        width:  10 * 34 + 9 * 6
                        height: 138
                        Canvas {
                            id: eqCurve
                            anchors { left: parent.left; right: parent.right; top: parent.top }
                            height: 120
                            onPaint: {
                                const ctx = getContext("2d")
                                ctx.reset()
                                function rgba(c, a) {
                                    return "rgba(" + Math.round(c.r * 255) + "," +
                                           Math.round(c.g * 255) + "," +
                                           Math.round(c.b * 255) + "," + a + ")"
                                }
                                const g = root._eqGains(), n = g.length
                                const step = eqTrack.width / n
                                const xs = [], ys = []
                                for (let i = 0; i < n; i++) {
                                    xs.push(step * (i + 0.5))
                                    const norm = (g[i] - root.eqMin) / (root.eqMax - root.eqMin)
                                    ys.push(120 * (1 - norm))
                                }
                                const grad = ctx.createLinearGradient(0, 0, eqTrack.width, 0)
                                grad.addColorStop(0, rgba(Theme.cInversePrimary, 1))
                                grad.addColorStop(1, rgba(Theme.cOnSecondary, 1))
                                ctx.strokeStyle = grad
                                ctx.lineWidth = 2; ctx.lineJoin = "round"; ctx.lineCap = "round"
                                ctx.beginPath(); ctx.moveTo(xs[0], ys[0])
                                for (let i = 1; i < n - 1; i++) {
                                    const xc = (xs[i] + xs[i + 1]) / 2
                                    const yc = (ys[i] + ys[i + 1]) / 2
                                    ctx.quadraticCurveTo(xs[i], ys[i], xc, yc)
                                }
                                ctx.lineTo(xs[n - 1], ys[n - 1])
                                ctx.stroke()
                            }
                            Connections {
                                target: Config
                                function onEqGainsChanged() { if (eqCurve.visible) eqCurve.requestPaint() }
                            }
                        }
                        Row {
                            anchors.fill: parent
                            spacing: 6
                            Repeater {
                                model: 10
                                EqBandSlider {
                                    required property int index
                                    gain:  Config.eqGains[index] || 0
                                    label: root.eqFreqLbl[index]
                                    onGainEdited: function(g) { root.setEqGain(index, g) }
                                }
                            }
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 4
                    Repeater {
                        model: ["Flat", "Bass", "Treble", "Cinema", "Vocal", "Rock", "Pop"]
                        EqPill {
                            required property var modelData
                            label:  modelData
                            active: Config.eqPreset === modelData
                            onPicked: root.applyEqPreset(modelData)
                        }
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
        readonly property real _leftMargin: Config.popupSideMargin

        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true }
        margins {
            top:    _barAtBottom ? 0 : _barGap
            bottom: _barAtBottom ? _barGapBot : 0
            left:   _leftMargin
        }

        implicitWidth:  mpPanel.implicitWidth + 8
        implicitHeight: 480
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
            popupMode: true
            anchors {
                left: parent.left
                top:    !mpPopup._barAtBottom ? parent.top    : undefined
                bottom:  mpPopup._barAtBottom ? parent.bottom : undefined
            }
            // Cascade open: the Loader recreates this window on every open, so
            // animate opacity/scale on creation (same pattern as notif toasts).
            transformOrigin: mpPopup._barAtBottom ? Item.BottomLeft : Item.TopLeft
            NumberAnimation on opacity { from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic; running: true }
            NumberAnimation on scale   { from: 0.92; to: 1; duration: 220; easing.type: Easing.OutCubic; running: true }
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
