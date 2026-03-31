import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// Cava visualizer — drives the cava binary directly via a temp config file.
// No Python wrapper, no socket, no manager process. Cava outputs raw ASCII
// integers on stdout; we map them to braille bar characters and display them.
//
// Requires: cava installed (pacman -S cava  /  apt install cava)
Item {
    id: root
    property string side: "left"   // "left" or "right"

    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  _text !== "" ? (_textMetrics.width + Config.modPadH * 2) : 0
    implicitHeight: Config.moduleHeight

    property string _text:   ""
    property bool   _active: false

    // ── Bar character lookup ──────────────────────────────────────────────
    // Maps a 0–15 value to one braille bar character.
    // Config.cavaBars = "⣀⣄⣤⣦⣶⣷⣿" (7 chars, index 0 = silence glyph)
    readonly property var _barChars: {
        const s = Config.cavaBars
        return s.length > 0 ? s.split("") : ["⣀","⣄","⣤","⣦","⣶","⣷","⣿"]
    }
    readonly property int _maxVal: 15   // ascii_max_range in cava config

    function _valToChar(v) {
        const idx = Math.round((Math.max(0, Math.min(v, _maxVal)) / _maxVal)
                               * (_barChars.length - 1))
        return _barChars[idx] || " "
    }

    // ── Cava config written to /tmp ───────────────────────────────────────
    readonly property string _cfgPath: "/tmp/qs-cava-" + root.side + ".cfg"
    readonly property int    _bars:    Config.cavaWidth
    readonly property string _channels: root.side === "right" ? "mono" : "mono"
    readonly property int    _reverse:  root.side === "right" ? 1 : 0

    // Write config once on creation, rewrite if width changes
    Process {
        id: cfgProc
        property string _cmd: ""
        command: ["bash", "-c", cfgProc._cmd]
        running: false
        function write() {
            _cmd = "cat > '" + root._cfgPath + "' << 'CAVAEOF'\n" +
                "[general]\nbars = " + root._bars + "\nsleep_timer = 1\n\n" +
                "[input]\nmethod = pulse\nsource = auto\n\n" +
                "[output]\nmethod = raw\nraw_target = /dev/stdout\ndata_format = ascii\n" +
                "ascii_max_range = " + root._maxVal + "\n" +
                "channels = mono\nreverse = " + root._reverse + "\n" +
                "CAVAEOF"
            running = true
        }
        onExited: if (!cavaProc.running) cavaProc.running = true
    }

    // ── Cava process ──────────────────────────────────────────────────────
    Process {
        id: cavaProc
        command: ["cava", "-p", root._cfgPath]
        running: false

        stdout: SplitParser {
            splitMarker: ";"    // cava raw output: "val0;val1;val2;...;"
            onRead: function(chunk) {
                if (!chunk.trim()) return
                // Each read is a full frame: "12;8;3;15;0;..." ending with ";"
                // SplitParser splits on ";" so we get individual values.
                // Accumulate into frames using a buffer approach:
                root._processChunk(chunk.trim())
            }
        }
        onExited: restartTimer.restart()
        onRunningChanged: if (!running) root._text = ""
    }

    // Frame accumulation — cava sends "v0;v1;v2;...;\n" per frame
    // SplitParser on ";" gives individual tokens; we rebuild full frames
    // by watching for the newline-terminated sequence.
    property var   _frameBuf: []
    property int   _frameSize: root._bars

    function _processChunk(token) {
        const n = parseInt(token)
        if (isNaN(n)) return
        _frameBuf.push(n)
        if (_frameBuf.length >= _frameSize) {
            _renderFrame(_frameBuf.splice(0, _frameSize))
        }
    }

    function _renderFrame(vals) {
        const ordered = root._reverse ? vals.slice().reverse() : vals
        let out = ""
        for (let i = 0; i < ordered.length; i++)
            out += _valToChar(ordered[i])
        root._text   = out
        root._active = vals.some(v => v > 0)
    }

    Timer { id: restartTimer; interval: 3000; repeat: false
        onTriggered: if (!cavaProc.running) cavaProc.running = true }

    // ── Startup ───────────────────────────────────────────────────────────
    Component.onCompleted: cfgProc.write()

    // Transparent when inactive
    property real _opacity: {
        if (!Config.cavaTransparentWhenInactive) return _active ? Config.cavaActiveOpacity : 0.0
        return _active ? Config.cavaActiveOpacity : Config.cavaInactiveOpacity
    }

    // ── Text metrics for implicitWidth ────────────────────────────────────
    TextMetrics {
        id: _textMetrics
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
        text: root._text
    }

    Text {
        id: cavaLabel
        anchors.centerIn: parent
        text: root._text
        color: Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g,
                       Config.cavaGlyphColor.b, root._opacity)
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
        Behavior on color { ColorAnimation { duration: 300 } }
    }
}
