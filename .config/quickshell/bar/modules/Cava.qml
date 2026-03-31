import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// Cava visualizer — runs cava directly with a generated per-side config.
// Bypasses the socket manager for reliability.
// Non-collapse: uses a hidden sizer Text so width is always reserved.
Item {
    id: root
    property string side: "left"   // "left" or "right"

    Layout.alignment: Qt.AlignVCenter

    //  Non-collapse: always reserve full width when transparent-when-inactive.
    //  _sizer uses a placeholder string of cavaWidth first-bar chars so the
    //  island pre-allocates the correct width before cava outputs anything.
    implicitWidth:  Config.cavaTransparentWhenInactive
                        ? (_sizer.implicitWidth + Config.modPadH * 2)
                        : (_active ? (cavaLabel.implicitWidth + Config.modPadH * 2) : 0)
    implicitHeight: Config.moduleHeight

    property string _text:   ""
    property bool   _active: false

    // ── Direct cava invocation ────────────────────────────────────────────────
    //  Writes a temp config file then runs cava with ascii output.
    //  Each output line: semicolon-separated integers 0..N-1 where N = len(bars).
    Process {
        id: cavaProc
        // Build command at binding time so it reacts to Config changes on restart.
        command: {
            const bars    = Config.cavaEffectiveBars
            const maxR    = Math.max(0, bars.length - 1)
            const rev     = root.side === "right" ? 1 : 0
            const cfgPath = "/tmp/qs-cava-" + root.side + ".ini"
            // Pass each line as a separate printf arg so actual newlines are
            // written — JSON.stringify would escape \n in a joined string.
            const lines = [
                "[general]",
                "bars = "             + Config.cavaWidth,
                "framerate = 60",
                "",
                "[output]",
                "method = raw",
                "raw_target = /dev/stdout",
                "data_format = ascii",
                "ascii_max_range = "  + maxR,
                "channels = mono",
                "reverse = "          + rev
            ]
            const quoted   = lines.map(l => JSON.stringify(l)).join(" ")
            const writeCmd = "printf '%s\\n' " + quoted + " > " + cfgPath
            return ["bash", "-c", writeCmd + " && cava -p " + cfgPath]
        }
        Component.onCompleted: running = true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (!t || t.startsWith("[")) return   // skip cava header lines
                const vals    = t.split(";")
                const barsStr = Config.cavaEffectiveBars
                let   result  = ""
                let   allZero = true
                for (let i = 0; i < vals.length; i++) {
                    const v = parseInt(vals[i])
                    if (!isNaN(v)) {
                        if (v > 0) allZero = false
                        result += barsStr[Math.min(v, barsStr.length - 1)]
                    }
                }
                root._text   = result
                root._active = !allZero
            }
        }
        onExited: restartTimer.restart()
    }
    Timer { id: restartTimer; interval: 2000; repeat: false
        onTriggered: if (!cavaProc.running) cavaProc.running = true }

    // ── Hidden sizer: reserves correct width before first output ─────────────
    Text {
        id: _sizer
        visible: false
        text: {
            const b = Config.cavaEffectiveBars
            const ch = b.length > 0 ? b[0] : " "
            return ch.repeat(Config.cavaWidth)
        }
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
    }

    // ── Visible label ─────────────────────────────────────────────────────────
    Text {
        id: cavaLabel
        anchors.centerIn: parent
        text: root._text

        readonly property color _activeColor: Config.cavaGradientEnabled
            ? Config.cavaGradientStartColor
            : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g,
                      Config.cavaGlyphColor.b, Config.cavaActiveOpacity)

        readonly property color _inactiveColor: Config.cavaGradientEnabled
            ? Qt.rgba(Config.cavaGradientEndColor.r, Config.cavaGradientEndColor.g,
                      Config.cavaGradientEndColor.b, Config.cavaInactiveOpacity)
            : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g,
                      Config.cavaGlyphColor.b, Config.cavaInactiveOpacity)

        color: root._active ? _activeColor : _inactiveColor
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
        Behavior on color { ColorAnimation { duration: 300 } }
    }
}
