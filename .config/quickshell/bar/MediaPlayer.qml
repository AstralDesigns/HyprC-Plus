import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ── Media island ─────────────────────────────────────────────────────────────
//  Left:  GJS media-player toggle button (󰝚) — matches waybar custom/media-player
//  Right: [spinning disc] play/pause  title – artist  (max 20 chars)
//
//  Disc behaviour (like candylock lockscreen):
//    Playing → rotates continuously (8 s per revolution)
//    Paused  → freezes at current angle
//    Stopped → track info hidden
// ─────────────────────────────────────────────────────────────────────────────

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: mediaRow.implicitWidth + Config.modulePadH
    implicitHeight: Config.moduleHeight

    // ── State ────────────────────────────────────────────────────────────────
    property string _status:  "Stopped"
    property string _title:   ""
    property string _artist:  ""
    property string _artUrl:  ""
    property string _artPath: ""

    readonly property bool   _active:  _status === "Playing" || _status === "Paused"
    readonly property bool   _playing: _status === "Playing"
    readonly property int    _ts:      Config.mediaThumbSize

    readonly property string _label: {
        const full = _artist ? (_title + " \u2013 " + _artist) : _title
        return full.length > 20 ? full.substring(0, 19) + "\u2026" : full
    }

    // ── playerctl metadata watcher ───────────────────────────────────────────
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
                root._status = p[0].trim() || "Stopped"
                const url    = p.length > 1 ? p[1].trim() : ""
                if (url !== root._artUrl) {
                    root._artUrl  = url
                    root._artPath = ""
                    if (url) artProc.launch(url)
                }
                root._title  = p.length > 2 ? (p[2].trim() || "") : ""
                root._artist = p.length > 3 ? (p[3].trim() || "") : ""
            }
        }
        onExited: pctlRestart.restart()
    }
    Timer { id: pctlRestart; interval: 3000; repeat: false
        onTriggered: if (!playerctlProc.running) playerctlProc.running = true }

    // ── ImageMagick: art URL → circle PNG ────────────────────────────────────
    Process {
        id: artProc
        property string _dst: "/tmp/qs_bar_art.png"
        property string _cmd: "true"
        command: ["bash", "-c", artProc._cmd]
        function launch(url) {
            const r   = Math.round(root._ts / 2)
            const src = url.startsWith("file://") ? url.substring(7) : url
            const esc = src.replace(/'/g, "'\\''")
            _cmd = "SRC='" + esc + "'; DST='" + _dst + "'; S=" + root._ts + "; R=" + r + "; " +
                "[ -f \"$SRC\" ] || { curl -sf --max-time 8 \"$SRC\" -o /tmp/qs_art_raw.png 2>/dev/null && SRC=/tmp/qs_art_raw.png; }; " +
                "magick \"$SRC\" -resize ${S}x${S}^ -gravity center -extent ${S}x${S} " +
                "  \\( +clone -alpha extract -fill black -colorize 100 " +
                "     -fill white -draw \"circle $R,$R $R,0\" \\) " +
                "-alpha off -compose CopyOpacity -composite -strip \"$DST\""
            if (!running) running = true
        }
        onExited: function(code) {
            if (code === 0) root._artPath = _dst + "?" + Date.now()
        }
    }

    // ── Playerctl control ────────────────────────────────────────────────────
    Process { id: ctlProc; property string _c: ""; command: ["bash", "-c", ctlProc._c] }
    function ctl(cmd) { ctlProc._c = "playerctl " + cmd; if (!ctlProc.running) ctlProc.running = true }

    // ── GJS media-player toggle (matches waybar custom/media-player on-click) ─
    Process { id: gjsMediaProc; command: [Config.candyDir + "/GJS/toggle-media-player.sh"]; running: false }

    // ── Layout ───────────────────────────────────────────────────────────────
    Row {
        id: mediaRow
        anchors.centerIn: parent
        spacing: 0

        // ── GJS toggle button ─────────────────────────────────────────────
        Item {
            implicitWidth: gjsIcon.implicitWidth + Config.modulePadH
            implicitHeight: Config.moduleHeight
            Text {
                id: gjsIcon; anchors.centerIn: parent
                text: "󰽲"
                color: Config.glyphColor
                font.family: Config.fontFamily; font.pixelSize: Config.fontSize
                font.weight: Config.fontWeight
            }
            opacity: gjsMa.containsMouse ? 0.7 : 1.0
            Behavior on opacity { NumberAnimation { duration: 80 } }
            MouseArea {
                id: gjsMa; anchors.fill: parent; hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: if (!gjsMediaProc.running) gjsMediaProc.running = true
            }
        }

        // ── Track info (hidden when stopped) ─────────────────────────
        // Shrinkable: full width = disc + play/pause + text label.
        // Set Config.mediaShowText: false to collapse to disc + controls only.
        Item {
            id: trackItem
            visible: root._active
            clip: true

            readonly property int _minWidth: root._ts + 5 + playPauseIcon.implicitWidth + Config.moduleHPad
            readonly property int _fullWidth: trackRow.implicitWidth + Config.moduleHPad

            implicitWidth:  visible ? (Config.mediaShowText ? _fullWidth : _minWidth) : 0
            implicitHeight: Config.moduleHeight

            Behavior on implicitWidth { NumberAnimation { duration: 220; easing.type: Easing.InOutQuad } }

            Row {
                id: trackRow; anchors.centerIn: parent; spacing: 5

                Item {
                    id: discContainer
                    width: root._ts; height: root._ts
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        visible: root._artPath === ""
                        anchors.centerIn: parent
                        text: "󰽲"
                        color: Config.glyphColor
                        font.family: Config.fontFamily
                        font.pixelSize: root._ts - 2
                    }

                    Image {
                        visible: root._artPath !== ""
                        anchors.fill: parent
                        source: root._artPath !== "" ? ("file://" + root._artPath.split("?")[0]) : ""
                        fillMode: Image.PreserveAspectCrop
                        smooth: true; cache: false; asynchronous: true
                    }

                    RotationAnimator on rotation {
                        from: discContainer.rotation; to: discContainer.rotation + 360
                        duration: 8000; loops: Animation.Infinite
                        running: root._playing
                    }
                }

                Text {
                    id: playPauseIcon
                    text: root._playing ? "󰐊" : "󰏤"
                    color: Config.glyphColor
                    font.family: Config.fontFamily; font.pixelSize: Config.labelFontSize
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    visible: Config.mediaShowText
                    text: root._label
                    color: Config.textColor
                    font.family: Config.labelFont; font.pixelSize: Config.labelFontSize
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            opacity: trackMa.containsMouse ? 0.7 : 1.0
            Behavior on opacity { NumberAnimation { duration: 80 } }

            MouseArea {
                id: trackMa; anchors.fill: parent; hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function(ev) {
                    if (ev.button === Qt.RightButton) root.ctl("next")
                    else root.ctl("play-pause")
                }
                onWheel: function(ev) {
                    root.ctl(ev.angleDelta.y > 0 ? "previous" : "next")
                }
            }
        }
    }
}
