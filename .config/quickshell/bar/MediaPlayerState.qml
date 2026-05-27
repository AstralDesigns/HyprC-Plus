pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  MediaPlayerState — single playerctl -F process shared by all MediaPlayer
//  instances across all screens. Eliminates N×2 playerctl processes.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: root
    visible: false

    property string status:  "Stopped"
    property string title:   ""
    property string artist:  ""
    property string artUrl:  ""
    property string artPath: ""

    readonly property bool active:  status === "Playing" || status === "Paused"
    readonly property bool playing: status === "Playing"
    readonly property int  thumbSize: Config.mediaThumbSize

    readonly property string label: {
        const full = artist ? (title + " \u2013 " + artist) : title
        return full.length > 20 ? full.substring(0, 19) + "\u2026" : full
    }

    // ── Single playerctl -F watcher ──────────────────────────────────────
    Process {
        id: playerctlProc
        command: ["playerctl", "-F", "metadata",
            "--format", "{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const p = l.split("\t")
                if (p.length < 1) return
                root.status = p[0].trim() || "Stopped"
                const url  = p.length > 1 ? p[1].trim() : ""
                if (url !== root.artUrl) {
                    root.artUrl  = url
                    // Don't clear artPath immediately to avoid flickering; 
                    // only clear if we have no URL at all.
                    if (!url) root.artPath = ""
                    else artProc.launch(url)
                }
                root.title  = p.length > 2 ? (p[2].trim() || "") : ""
                root.artist = p.length > 3 ? (p[3].trim() || "") : ""
            }
        }
        onExited: pctlRestart.restart()
    }
    Timer { id: pctlRestart; interval: 3000; repeat: false
        onTriggered: if (!playerctlProc.running) playerctlProc.running = true }

    // ── Art URL → circle PNG (ImageMagick) ───────────────────────────────
    Process {
        id: artProc
        property string _dst: "/tmp/qs_bar_art.png"
        property string _cmd: "true"
        command: ["bash", "-c", artProc._cmd]
        function launch(url) {
            const s   = root.thumbSize
            const r   = Math.round(s / 2)
            const src = url.startsWith("file://") ? url.substring(7) : url
            const esc = src.replace(/'/g, "'\\''")
            // Use a unique destination per URL to avoid race conditions and 
            // ensure Qt sees a fresh file path.
            const hash = Math.abs(url.split('').reduce((a,b)=>{a=((a<<5)-a)+b.charCodeAt(0);return a&a},0)).toString(16)
            _dst = "/tmp/qs_bar_art_" + hash + ".png"
            
            _cmd = "SRC='" + esc + "'; DST='" + _dst + "'; S=" + s + "; R=" + r + "; " +
                "[ -f \"$SRC\" ] || { curl -sf --max-time 8 \"$SRC\" -o /tmp/qs_art_raw.png 2>/dev/null && SRC=/tmp/qs_art_raw.png; }; " +
                "magick \"$SRC\" -resize ${S}x${S}^ -gravity center -extent ${S}x${S} " +
                "  \\( +clone -alpha extract -fill black -colorize 100 " +
                "     -fill white -draw \"roundrectangle 0,0 $((S-1)),$((S-1)) $R,$R\" \\) " +
                "-alpha off -compose CopyOpacity -composite -strip \"$DST\""
            if (!running) running = true
        }
        onExited: function(code) {
            if (code === 0) root.artPath = artProc._dst
        }
    }

    // ── Playerctl control (shared) ────────────────────────────────────────
    Process { id: ctlProc; property string _c: ""; command: ["bash", "-c", ctlProc._c] }
    function ctl(cmd) {
        ctlProc._c = "playerctl " + cmd
        if (!ctlProc.running) ctlProc.running = true
    }
}
