pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  MediaPlayerState — single playerctl -F process shared by all MediaPlayer
//  instances across all screens. Multi-source tab support per media player.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    visible: false

    property var  mediaPlayers:       []
    property int  activePlayerIndex:  0
    readonly property var activePlayer: (mediaPlayers.length > 0 && activePlayerIndex < mediaPlayers.length)
        ? mediaPlayers[activePlayerIndex]
        : null

    property string status:      activePlayer ? activePlayer.status : "Stopped"
    property string title:       activePlayer ? (activePlayer.title || "") : ""
    property string artist:      activePlayer ? activePlayer.artist : ""
    property string artUrl:      activePlayer ? activePlayer.artUrl : ""
    property string artPath:     activePlayer ? (activePlayer.artPath || "") : ""
    property string mediaSource: activePlayer ? activePlayer.name : ""

    readonly property bool active: status === "Playing" || status === "Paused" || mediaPlayers.some(p => p.status === "Playing" || p.status === "Paused")
    readonly property bool playing: status === "Playing"
    readonly property bool anyPlaying: playing || mediaPlayers.some(p => p.status === "Playing")
    readonly property int  thumbSize: Config.mediaThumbSize

    // Run playerctl only when a bar module actually needs MPRIS state.
    readonly property bool _watchMedia: Config.showMediaPlayer || Config.showCava

    readonly property string label: {
        const full = artist ? (title + " \u2013 " + artist) : title
        return full.length > 20 ? full.substring(0, 19) + "\u2026" : full
    }

    // ── Stopped debounce ──────────────────────────────────────────────────
    //  Some MPRIS sources (browser bridges especially) report a transient
    //  "Stopped" between tracks/on pause/during ad breaks instead of going
    //  straight to "Paused" the way Spotify does. Applying that immediately
    //  causes the module to flicker/collapse for a still-active source. Hold
    //  a Stopped line for a short grace window; a real status for the same
    //  player arriving in that window cancels it outright.
    readonly property int _stopDebounceMs: 1200
    property var _pendingStops: ({})   // name -> timestamp first seen Stopped

    Timer {
        id: stopSweep
        interval: 250
        repeat: true
        running: Object.keys(root._pendingStops).length > 0
        onTriggered: root._sweepPendingStops()
    }

    function _sweepPendingStops() {
        const now = Date.now()
        let ps = Object.assign({}, root._pendingStops)
        let list = root.mediaPlayers.slice()
        let changed = false
        for (const name in ps) {
            if (now - ps[name] < root._stopDebounceMs) continue
            delete ps[name]
            const idx = list.findIndex(item => item.name === name)
            if (idx >= 0 && list[idx].status !== "Stopped") {
                let item = Object.assign({}, list[idx])
                item.status = "Stopped"
                list[idx] = item
                changed = true
            }
        }
        root._pendingStops = ps
        if (changed) {
            root.mediaPlayers = list
            if (root.activePlayerIndex >= root.mediaPlayers.length) {
                root.activePlayerIndex = Math.max(0, root.mediaPlayers.length - 1)
            }
        }
    }

    // ── Single playerctl -F watcher ──────────────────────────────────────
    Process {
        id: playerctlProc
        command: ["playerctl", "-F", "-a", "metadata",
            "--format", "{{playerName}}\t{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}"]
        running: root._watchMedia
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const p = l.split("\t")
                if (p.length < 1) return
                const name   = p[0].trim()
                if (!name) return
                const status = (p.length > 1 ? p[1].trim() : "") || "Stopped"
                const url    = p.length > 2 ? p[2].trim() : ""
                const title  = p.length > 3 ? p[3].trim() : ""
                const artist = p.length > 4 ? p[4].trim() : ""

                let list = root.mediaPlayers.slice()
                let idx  = list.findIndex(item => item.name === name)

                // A "Stopped" line does NOT necessarily mean the player is gone —
                // see the _pendingStops debounce above. Queue it instead of applying
                // it immediately, and bail out without touching mediaPlayers; the
                // sweep (or a real status line arriving below) resolves it.
                if (status === "Stopped") {
                    if (idx < 0) return
                    let ps = Object.assign({}, root._pendingStops)
                    if (ps[name] === undefined) ps[name] = Date.now()
                    root._pendingStops = ps
                    return
                }

                // Any real status cancels a pending stop for this player.
                if (root._pendingStops[name] !== undefined) {
                    let ps = Object.assign({}, root._pendingStops)
                    delete ps[name]
                    root._pendingStops = ps
                }

                let item = idx >= 0 ? Object.assign({}, list[idx]) : {
                    name: name, status: "Stopped", artUrl: "", title: "", artist: "", artPath: ""
                }

                item.status = status

                if (status !== "Stopped") {
                    const titleChanged = item.title !== title
                    const urlChanged   = item.artUrl !== url

                    item.artUrl = url
                    item.title  = title
                    item.artist = artist

                    if (titleChanged || urlChanged) {
                        item.artPath = ""
                        if (url) artProc.launchForPlayer(name, url)
                    }
                }

                if (idx >= 0) {
                    list[idx] = item
                } else {
                    list.push(item)
                }

                root.mediaPlayers = list
                if (root.activePlayerIndex >= root.mediaPlayers.length) {
                    root.activePlayerIndex = Math.max(0, root.mediaPlayers.length - 1)
                }
            }
        }
        onExited: {
            root.mediaPlayers = []
            root.activePlayerIndex = 0
            pctlRestart.restart()
        }
    }
    Timer { id: pctlRestart; interval: 3000; repeat: false
        onTriggered: if (root._watchMedia && !playerctlProc.running) playerctlProc.running = true }

    // ── Liveness check for the source playerctl -F stops reporting on ────
    //  Closing one of several sources reliably yields a "Stopped" line for
    //  it. Closing the only (or last remaining) source does not — playerctl
    //  -F has nothing left to fall back to watching and simply goes quiet
    //  instead of emitting a final event, so that entry never hits the
    //  Stopped branch above. Poll `playerctl -l` to catch that case and
    //  drop anything it no longer lists.
    property var _liveNames: []
    Process {
        id: playerListProc
        command: ["playerctl", "-l"]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const n = l.trim()
                if (n) root._liveNames.push(n)
            }
        }
        onRunningChanged: if (running) root._liveNames = []
        onExited: function(code) { if (code === 0) root._prunePlayers() }
    }
    Timer {
        id: playerPruneTimer
        interval: 2000
        repeat: true
        running: root._watchMedia && root.mediaPlayers.length > 0
        onTriggered: if (!playerListProc.running) playerListProc.running = true
    }
    function _isLive(name, live) {
        for (let i = 0; i < live.length; i++) {
            const n = live[i]
            if (n === name || n.indexOf(name + ".") === 0) return true
        }
        return false
    }
    function _prunePlayers() {
        if (root.mediaPlayers.length === 0) return
        const live = root._liveNames
        const filtered = root.mediaPlayers.filter(p => root._isLive(p.name, live))
        if (filtered.length !== root.mediaPlayers.length) {
            root.mediaPlayers = filtered
            if (root.activePlayerIndex >= root.mediaPlayers.length) {
                root.activePlayerIndex = Math.max(0, root.mediaPlayers.length - 1)
            }
            let ps = Object.assign({}, root._pendingStops)
            let psChanged = false
            for (const name in ps) {
                if (!root._isLive(name, live)) { delete ps[name]; psChanged = true }
            }
            if (psChanged) root._pendingStops = ps
        }
    }

    Connections {
        target: Config
        function onShowMediaPlayerChanged() { root._syncPlayerctl() }
        function onShowCavaChanged() { root._syncPlayerctl() }
    }
    function _syncPlayerctl() {
        if (root._watchMedia) {
            if (!playerctlProc.running) playerctlProc.running = true
        } else if (playerctlProc.running) {
            playerctlProc.running = false
            root.status = "Stopped"
            root.title = ""
            root.artist = ""
            root.artUrl = ""
            root.artPath = ""
            root.mediaPlayers = []
            root.activePlayerIndex = 0
        }
    }

    // ── Art URL → circle PNG (ImageMagick) ───────────────────────────────
    Process {
        id: artProc
        property string _dst: "/tmp/qs_bar_art.png"
        property string _cmd: "true"
        property string _targetPlayer: ""
        command: ["bash", "-c", artProc._cmd]
        function launchForPlayer(playerName, url) {
            const s   = root.thumbSize
            const r   = Math.round(s / 2)
            const src = url.startsWith("file://") ? url.substring(7) : url
            const esc = src.replace(/'/g, "'\\''")
            const hash = Math.abs((playerName + url).split('').reduce((a,b)=>{a=((a<<5)-a)+b.charCodeAt(0);return a&a},0)).toString(16)
            _targetPlayer = playerName
            _dst = "/tmp/qs_bar_art_" + hash + ".png"
            
            _cmd = "SRC='" + esc + "'; DST='" + _dst + "'; S=" + s + "; R=" + r + "; " +
                "[ -f \"$SRC\" ] || { curl -sf --max-time 8 \"$SRC\" -o /tmp/qs_art_raw.png 2>/dev/null && SRC=/tmp/qs_art_raw.png; }; " +
                "magick \"$SRC\" -resize ${S}x${S}^ -gravity center -extent ${S}x${S} " +
                "  \\( +clone -alpha extract -fill black -colorize 100 " +
                "     -fill white -draw \"roundrectangle 0,0 $((S-1)),$((S-1)) $R,$R\" \\) " +
                "-alpha off -compose CopyOpacity -composite -strip \"$DST\""
            if (running) running = false
            running = true
        }
        onExited: function(code) {
            if (code === 0 && artProc._targetPlayer !== "") {
                let list = root.mediaPlayers.slice()
                let idx = list.findIndex(p => p.name === artProc._targetPlayer)
                if (idx >= 0) {
                    let item = Object.assign({}, list[idx])
                    item.artPath = artProc._dst
                    list[idx] = item
                    root.mediaPlayers = list
                }
            }
        }
    }

    // ── Playerctl control (shared) ────────────────────────────────────────
    Process { id: ctlProc; property string _c: ""; command: ["bash", "-c", ctlProc._c] }
    function ctl(cmd) {
        const target = root.mediaSource ? ("-p '" + root.mediaSource.replace(/'/g, "'\\''") + "' ") : ""
        if (cmd === "play-pause" && root.activePlayer) {
            let list = root.mediaPlayers.slice()
            let idx = root.activePlayerIndex
            if (idx >= 0 && idx < list.length) {
                let item = Object.assign({}, list[idx])
                item.status = item.status === "Playing" ? "Paused" : "Playing"
                list[idx] = item
                root.mediaPlayers = list
            }
        }
        ctlProc._c = "playerctl " + target + cmd
        if (ctlProc.running) ctlProc.running = false
        ctlProc.running = true
    }

    function nextSource() {
        const count = Math.max(1, root.mediaPlayers.length)
        if (count <= 1) return
        root.activePlayerIndex = (root.activePlayerIndex + 1) % count
    }

    function prevSource() {
        const count = Math.max(1, root.mediaPlayers.length)
        if (count <= 1) return
        root.activePlayerIndex = (root.activePlayerIndex - 1 + count) % count
    }
}
