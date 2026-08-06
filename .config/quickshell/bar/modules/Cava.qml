import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// Cava visualizer — one cava child per side.
// Keeps a light cava proc alive whenever the module is visible so level-0 ASCII
// and the Transparent Inactive toggle stay cava-driven (not QS-drawn).
// Framerate drops when audio is idle to limit CPU.
Item {
    id: root
    property string side: "left"   // "left" or "right"

    Layout.alignment: Qt.AlignVCenter

    readonly property bool _autoHideActive: Config.cavaAutoHide && !Config.showMediaPlayer
    readonly property bool _mediaActive: MediaPlayerState.active

    // Run whenever the island is shown — not only while Playing.
    readonly property bool _procShouldRun: Config.showCava && (!root._autoHideActive || root._mediaActive)
    readonly property int  _cavaFramerate: MediaPlayerState.playing ? 30 : 2

    implicitWidth: {
        if (_autoHideActive && !_mediaActive) return 0
        return _sizer.advanceWidth + Config.modPadH * 2
    }
    implicitHeight: Config.moduleHeight

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

    property string _text:   ""
    property bool   _active: false

    function _syncCavaProc() {
        if (root._procShouldRun) {
            if (!cavaProc.running) cavaProc.running = true
        } else if (cavaProc.running) {
            cavaProc.running = false
            root._text = ""
            root._active = false
        }
    }

    function _restartCavaForFramerate() {
        if (!cavaProc.running || !root._procShouldRun) return
        root._intentionalRestart = true
        cavaProc.running = false
    }

    Connections {
        target: MediaPlayerState
        function onPlayingChanged() {
            const wasRunning = cavaProc.running
            root._syncCavaProc()
            if (wasRunning && root._procShouldRun)
                root._restartCavaForFramerate()
        }
        function onStatusChanged() { root._syncCavaProc() }
    }
    Connections {
        target: Config
        function onShowCavaChanged() { root._syncCavaProc() }
    }
    Component.onCompleted: root._syncCavaProc()

    Process {
        id: cavaProc
        command: {
            const bars    = Config.cavaEffectiveBars
            const maxR    = Math.max(0, Math.floor((bars.length - 1) * 1.5))
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
                const maxR    = Math.max(0, Math.floor((barsStr.length - 1) * 1.5))
                let   result  = ""
                let   allZero = true
                for (let i = 0; i < vals.length; i++) {
                    const v = parseInt(vals[i])
                    if (!isNaN(v)) {
                        if (v > 0) allZero = false
                        const scaledV = Math.floor(v * (barsStr.length - 1) / maxR)
                        result += barsStr[Math.min(scaledV, barsStr.length - 1)]
                    }
                }
                root._text   = result
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
    }
}
