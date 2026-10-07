import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import ".."
import "../scripts/cavapaint.js" as CP

// Cava visualizer — one cava child per side.
// Keeps a light cava proc alive whenever the module is visible so level-0 ASCII
// and the Transparent Inactive toggle stay cava-driven (not QS-drawn).
// Framerate drops when audio is idle to limit CPU.
Item {
    id: root
    property string side: "left"   // "left" or "right"

    Layout.alignment: Qt.AlignVCenter

    readonly property bool _autoHideActive: Config.cavaAutoHide && !Config.showMediaPlayer
    readonly property bool _mediaActive: MediaPlayerState.anyPlaying || MediaPlayerState.active

    // Run whenever the island is shown — smooth continuous stream.
    readonly property bool _procShouldRun: Config.showCava && (!root._autoHideActive || root._mediaActive)
    readonly property int  _cavaFramerate: 60

    implicitWidth: {
        if (_autoHideActive && !_mediaActive) return 0
        return _sizer.advanceWidth + Config.modPadH * 2
    }
    implicitHeight: Config.moduleHeight

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

    property string _text:   ""
    property bool   _active: false

    // Per-band amplitude 0..1 — the numeric render source for the Canvas wave
    // (the ascii path keeps using _text). Populated every cava frame in onRead.
    property var    _bands:  []

    // Value range cava emits: paint mode asks for a finer 0..200 ramp; ascii
    // derives it from the glyph-count of the active preset (as before).
    readonly property int _maxRange: Config.cavaIsPaint
        ? 200
        : Math.max(1, Math.floor((Config.cavaEffectiveBars.length - 1) * 1.5))

    // colour -> CSS rgba string for the Canvas 2D context (Canvas can't take a
    // QML color directly). `mul` optionally scales alpha (used for the fill).
    function _rgba(c, mul) {
        const a = Math.max(0, Math.min(1, c.a * (mul === undefined ? 1 : mul)))
        return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) +
               "," + Math.round(c.b * 255) + "," + a + ")"
    }

    function _syncCavaProc() {
        if (root._procShouldRun) {
            if (!cavaProc.running) cavaProc.running = true
        } else if (cavaProc.running) {
            cavaProc.running = false
            root._text = ""
            root._active = false
        }
    }

    Connections {
        target: MediaPlayerState
        function onAnyPlayingChanged() { root._syncCavaProc() }
        function onActiveChanged()     { root._syncCavaProc() }
    }
    Connections {
        target: Config
        function onShowCavaChanged()     { root._syncCavaProc() }
        function onCavaAutoHideChanged() { root._syncCavaProc() }
    }
    Component.onCompleted: root._syncCavaProc()

    Process {
        id: cavaProc
        command: {
            const maxR    = root._maxRange
            const rev     = root.side === "right" ? 1 : 0
            const cfgPath = "/tmp/qs-cava-" + root.side + ".ini"
            const lines = [
                "[general]",
                "bars = "             + Config.cavaWidth,
                "framerate = "        + root._cavaFramerate,
                "sleep_timer = 1",
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
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (!t || t.startsWith("[")) return
                const vals    = t.split(";")
                const barsStr = Config.cavaEffectiveBars
                const maxR    = root._maxRange
                const isPaint = Config.cavaIsPaint
                const bands   = []
                let   result  = ""
                let   allZero = true
                for (let i = 0; i < vals.length; i++) {
                    const v = parseInt(vals[i])
                    if (isNaN(v)) continue
                    if (v > 0) allZero = false
                    bands.push(Math.max(0, Math.min(1, v / maxR)))
                    if (!isPaint) {
                        const scaledV = Math.floor(v * (barsStr.length - 1) / maxR)
                        result += barsStr[Math.min(scaledV, barsStr.length - 1)]
                    }
                }
                root._text   = isPaint ? "" : result
                root._bands  = bands
                root._active = !allZero
            }
        }
        onExited: {
            if (!root._procShouldRun) return
            if (root._intentionalRestart) {
                root._intentionalRestart = false
                quickRestartTimer.restart()
            } else {
                crashRestartTimer.restart()
            }
        }
    }

    property bool _intentionalRestart: false

    Timer { id: quickRestartTimer; interval: 50; repeat: false
        onTriggered: if (root._procShouldRun && !cavaProc.running) cavaProc.running = true }

    Timer { id: crashRestartTimer; interval: 2000; repeat: false
        onTriggered: if (root._procShouldRun && !cavaProc.running) cavaProc.running = true }

    Connections {
        target: Config
        function onCavaWidthChanged() {
            if (!cavaProc.running) return
            root._intentionalRestart = true
            cavaProc.running = false
        }
        function onCavaStyleChanged() {
            if (!cavaProc.running) return
            root._intentionalRestart = true
            cavaProc.running = false
        }
    }

    TextMetrics {
        id: _sizer
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
        font.letterSpacing: Config.cavaBarSpacing
        text: {
            const b  = Config.cavaEffectiveBars
            const ch = b.length > 0 ? b[0] : " "
            return ch.repeat(Config.cavaWidth)
        }
    }

    readonly property color _colorTop: {
        if (root._active) {
            return Config.cavaGradientEnabled
                ? Config.cavaGradientStartColor
                : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g, Config.cavaGlyphColor.b, Config.cavaActiveOpacity)
        }
        if (Config.cavaTransparentWhenInactive) {
            return Config.cavaGradientEnabled
                ? Qt.rgba(Config.cavaGradientStartColor.r, Config.cavaGradientStartColor.g, Config.cavaGradientStartColor.b, Config.cavaInactiveOpacity)
                : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g, Config.cavaGlyphColor.b, Config.cavaInactiveOpacity)
        }
        return Config.cavaGradientEnabled
            ? Config.cavaGradientStartColor
            : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g, Config.cavaGlyphColor.b, Config.cavaActiveOpacity)
    }
    readonly property color _colorBot: {
        if (root._active) {
            return Config.cavaGradientEnabled
                ? Config.cavaGradientEndColor
                : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g, Config.cavaGlyphColor.b, Config.cavaActiveOpacity)
        }
        if (Config.cavaTransparentWhenInactive) {
            return Config.cavaGradientEnabled
                ? Qt.rgba(Config.cavaGradientEndColor.r, Config.cavaGradientEndColor.g, Config.cavaGradientEndColor.b, Config.cavaInactiveOpacity)
                : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g, Config.cavaGlyphColor.b, Config.cavaInactiveOpacity)
        }
        return Config.cavaGradientEnabled
            ? Config.cavaGradientEndColor
            : Qt.rgba(Config.cavaGlyphColor.r, Config.cavaGlyphColor.g, Config.cavaGlyphColor.b, Config.cavaActiveOpacity)
    }

    Item {
        id: cavaLabelRoot
        anchors.centerIn: parent
        width:  _sizer.advanceWidth
        height: Config.glyphSize

        Text {
            id: cavaTop
            visible: !Config.cavaIsPaint
            anchors.top: parent.top
            width: parent.width
            height: parent.height * Config.cavaGradientSplit
            clip: true
            text: root._text
            topPadding: Config.cavaStyle === "bars" ? -2 : 0
            color: root._colorTop
            font.family:      Config.fontFamily
            font.pixelSize:   Config.glyphSize
            font.letterSpacing: Config.cavaBarSpacing
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        Text {
            id: cavaBot
            visible: !Config.cavaIsPaint
            anchors.bottom: parent.bottom
            width:  parent.width
            height: parent.height * (1.0 - Config.cavaGradientSplit)
            clip:   true
            text:   root._text
            topPadding: -(parent.height * Config.cavaGradientSplit) + (Config.cavaStyle === "bars" ? -2 : 0)
            color: Config.cavaGradientEnabled ? root._colorBot : root._colorTop
            font.family:      Config.fontFamily
            font.pixelSize:   Config.glyphSize
            font.letterSpacing: Config.cavaBarSpacing
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        // -- Canvas paint styles (Config.cavaIsPaint) -------------------
        // Draws the selected paint style from root._bands via the shared
        // cavapaint.js painter. A repaint Timer drives the animation (the
        // per-band signal arrives every cava frame; the underscored
        // _bands/_active change signals are not reliably emitted, so we
        // simply repaint on a fixed tick while the canvas is shown).
        //
        // The canvas fills the module to its edges (like ascii) and is masked
        // to the island radius so it never paints outside the pill.
    }

    // Painted canvas — sibling of cavaLabelRoot, fills root, masked to island radius.
    Rectangle {
        id: cavaPaintMask
        anchors.fill: parent
        radius: Config.islandRadius
        color: "white"
        opacity: 0
        layer.enabled: true
    }

    Canvas {
        id: waveCanvas
        anchors.fill: parent
        visible: Config.cavaIsPaint
        renderStrategy: Canvas.Cooperative
        layer.enabled: visible
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: cavaPaintMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        onVisibleChanged: if (visible) requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        Connections {
            target: Config
            function onCavaStyleChanged()           { if (waveCanvas.visible) waveCanvas.requestPaint() }
            function onCavaWaveThicknessChanged()   { if (waveCanvas.visible) waveCanvas.requestPaint() }
            function onCavaWaveSmoothChanged()      { if (waveCanvas.visible) waveCanvas.requestPaint() }
            function onModuleHeightChanged()         { if (waveCanvas.visible) waveCanvas.requestPaint() }
            function onIslandRadiusChanged()        { if (waveCanvas.visible) waveCanvas.requestPaint() }
            function onCavaGradientEnabledChanged() { if (waveCanvas.visible) waveCanvas.requestPaint() }
            function onCavaActiveOpacityChanged()   { if (waveCanvas.visible) waveCanvas.requestPaint() }
            function onCavaInactiveOpacityChanged() { if (waveCanvas.visible) waveCanvas.requestPaint() }
        }

        onPaint: {
            if (!visible) return
            const ctx = getContext("2d")
            ctx.reset()
            // The right module mirrors its band data (cava reverse=1), so the
            // horizontal colour ramp must mirror too: end-colour leads and
            // the start-colour trails, keeping both modules symmetric about
            // the bar centre.
            const mirrored = root.side === "right"
            CP.paint(ctx, Config.cavaPaintMap[Config.cavaStyle], root._bands,
                     width, height,
                     { c0: root._rgba(mirrored ? root._colorBot : root._colorTop),
                       c1: root._rgba(mirrored ? root._colorTop : root._colorBot),
                       thickness: Config.cavaWaveThickness,
                       smooth: Config.cavaWaveSmooth })
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: waveCanvas.visible && root._procShouldRun
        onTriggered: waveCanvas.requestPaint()
    }
}
