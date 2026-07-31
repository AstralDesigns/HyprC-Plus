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

                if (status === "Stopped" && !title && !artist) {
                    if (idx >= 0 && list.length > 1) {
                        list.splice(idx, 1)
                        root.mediaPlayers = list
                        if (root.activePlayerIndex >= root.mediaPlayers.length) {
                            root.activePlayerIndex = Math.max(0, root.mediaPlayers.length - 1)
                        }
                    }
                    return
                }

                let item = idx >= 0 ? Object.assign({}, list[idx]) : {
                    name: name, status: "Stopped", artUrl: "", title: "", artist: "", artPath: ""
                }

                const titleChanged = item.title !== title
                const urlChanged   = item.artUrl !== url

                item.status = status
                item.artUrl = url
                item.title  = title
                item.artist = artist

                if (titleChanged || urlChanged) {
                    item.artPath = ""
                    if (url) artProc.launchForPlayer(name, url)
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
        onExited: pctlRestart.restart()
    }
    Timer { id: pctlRestart; interval: 3000; repeat: false
        onTriggered: if (root._watchMedia && !playerctlProc.running) playerctlProc.running = true }

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
