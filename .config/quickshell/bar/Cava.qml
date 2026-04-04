import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// Cava visualizer — runs cava directly with a generated per-side config.
// Bypasses the socket manager for reliability.
// Non-collapse: uses a hidden sizer Text so width is always reserved.
// Auto-hide: when Config.cavaAutoHide is true AND Config.showMediaPlayer is false,
//            the module hides itself when no media is detected and shows again
//            when media plays. If the media player module is visible, cava always
//            stays shown (media info is already providing context).
//
//  HOT-RELOAD: A `reload()` function rewrites the config and restarts cava.
//  Config property changes (cavaWidth, cavaStyle, cavaBars) auto-trigger reload
//  via Connections — no full bar restart needed.
Item {
    id: root
    property string side: "left"   // "left" or "right"

    Layout.alignment: Qt.AlignVCenter

    readonly property string _cfgPath: "/tmp/qs-cava-" + root.side + ".ini"

    //  Auto-hide only applies when the toggle is on AND media module is hidden.
    readonly property bool _autoHideActive: Config.cavaAutoHide && !Config.showMediaPlayer

    //  Non-collapse: always reserve full width when transparent-when-inactive.
    //  _sizer uses a placeholder string of cavaWidth first-bar chars so the
    //  island pre-allocates the correct width before cava outputs anything.
    implicitWidth: {
        // Auto-hide: collapse when no media AND auto-hide is active
        if (_autoHideActive && !_mediaActive) return 0
        const w = _sizer.advanceWidth + Config.modPadH * 2
        return w
    }
    implicitHeight: Config.moduleHeight

    Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

    property string _text:   ""
    property bool   _active: false

    // ── Media detection for auto-hide ─────────────────────────────────────────
    //  Watches playerctl status; _mediaActive = true when Playing or Paused.
    //  Only runs when auto-hide is actually in effect.
    property bool _mediaActive: false

    Process {
        id: mediaWatchProc
        command: ["playerctl", "-F", "status"]
        running: root._autoHideActive
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const s = line.trim()
                root._mediaActive = (s === "Playing" || s === "Paused")
            }
        }
        onExited: mediaWatchRestart.restart()
    }
    Timer { id: mediaWatchRestart; interval: 3000; repeat: false
        onTriggered: if (root._autoHideActive && !mediaWatchProc.running) mediaWatchProc.running = true }

    // ── Config writer: generates the cava ini file ──────────────────────────
    //  Called on startup and manually via reload().
    function writeCavaConfig() {
        const bars    = Config.cavaEffectiveBars
        const maxR    = Math.max(0, Math.floor((bars.length - 1) * 1.5))
        const rev     = root.side === "right" ? 1 : 0

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
        const writeCmd = "printf '%s\\n' " + quoted + " > " + root._cfgPath
        writeProc.args = ["-c", writeCmd]
        writeProc.running = true
    }

    Process {
        id: writeProc
        command: ["bash", "-c", ""]
        running: false
        onExited: {
            // Config written — always restart cava
            cavaProc.running = false
            restartAfterWrite.restart()
        }
    }
    Timer {
        id: restartAfterWrite
        interval: 100
        repeat: false
        onTriggered: cavaProc.running = true
    }

    // ── Public API: reload cava with current config ─────────────────────────
    //  Call this from outside (e.g. control center slider) to force a hot-reload.
    function reload() {
        writeCavaConfig()
    }

    // ── Auto-restart when cava config properties change ─────────────────────
    //  Watches the key Config properties; when any change, rewrites config and restarts.
    //  Debounced via reloadTimer to prevent rapid-fire restarts during slider drag.
    Timer {
        id: reloadTimer
        interval: 300
        repeat: false
        onTriggered: reload()
    }

    Connections {
        target: Config
        function onCavaWidthChanged()      { reloadTimer.restart() }
        function onCavaStyleChanged()      { reloadTimer.restart() }
        function onCavaBarsChanged()       { reloadTimer.restart() }
    }

    // ── Direct cava invocation ────────────────────────────────────────────────
    //  Each output line: semicolon-separated integers 0..N-1 where N = len(bars).
    Process {
        id: cavaProc
        // Build command at binding time so it reacts to Config changes on restart.
        command: {
            const cfgPath = root._cfgPath
            return ["bash", "-c", "cava -p " + cfgPath]
        }
        Component.onCompleted: {
            // Write config then start cava
            writeCavaConfig()
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (!t || t.startsWith("[")) return   // skip cava header lines
                const vals    = t.split(";")
                const barsStr = Config.cavaEffectiveBars
                const maxR    = Math.max(0, Math.floor((barsStr.length - 1) * 1.5))
                let   result  = ""
                let   allZero = true
                const expectedWidth = Config.cavaWidth
                const actualBars = vals.length

                if (actualBars === 0) {
                    // No data from cava — fill with spaces
                    result = " ".repeat(expectedWidth)
                } else if (actualBars >= expectedWidth) {
                    // Cava outputs enough (or more) — just take what we need
                    for (let i = 0; i < expectedWidth; i++) {
                        const v = parseInt(vals[i])
                        if (!isNaN(v)) {
                            if (v > 0) allZero = false
                            const scaledV = Math.floor(v * (barsStr.length - 1) / maxR)
                            result += barsStr[Math.min(scaledV, barsStr.length - 1)]
                        } else {
                            result += " "
                        }
                    }
                } else {
                    // Cava outputs fewer bars than desired — interpolate to fill
                    for (let i = 0; i < expectedWidth; i++) {
                        // Map desired position back to cava's output range
                        const srcPos = (i * (actualBars - 1)) / (expectedWidth - 1)
                        const leftIdx = Math.floor(srcPos)
                        const rightIdx = Math.min(leftIdx + 1, actualBars - 1)
                        const frac = srcPos - leftIdx

                        const leftVal = parseInt(vals[leftIdx])
                        const rightVal = parseInt(vals[rightIdx])
                        const v = isNaN(leftVal) ? 0 :
                                  isNaN(rightVal) ? leftVal :
                                  Math.round(leftVal + (rightVal - leftVal) * frac)

                        if (v > 0) allZero = false
                        const scaledV = maxR > 0 ? Math.floor(v * (barsStr.length - 1) / maxR) : 0
                        result += barsStr[Math.min(scaledV, barsStr.length - 1)]
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
    // Uses TextMetrics so the island bg always matches what cavaLabel will render.
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

    // ── Visible label — two halves stacked for vertical gradient ─────────
    // Top 50% → cavaGradientStartColor, bottom 50% → cavaGradientEndColor
    // When gradient is disabled, only the top item is used (full height, solid color).

    // Resolved colors factored out for both active/inactive states
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

        // TOP half — start color, clips to upper split%
        Text {
            id: cavaTop
            anchors.top: parent.top
            width: parent.width
            height: parent.height * Config.cavaGradientSplit
            clip: true
            text: root._text
            // Bars style sits lower - shift up slightly
            topPadding: Config.cavaStyle === "bars" ? -2 : 0
            color: root._colorTop
            font.family:      Config.fontFamily
            font.pixelSize:   Config.glyphSize
            font.letterSpacing: Config.cavaBarSpacing
            Behavior on color { ColorAnimation { duration: 300 } }
        }

        // BOTTOM half — end color (same as top when gradient disabled), clips to lower split%
        Text {
            id: cavaBot
            anchors.bottom: parent.bottom
            width:  parent.width
            height: parent.height * (1.0 - Config.cavaGradientSplit)
            clip:   true
            text:   root._text
            // Shift the text upward so the bottom portion of the glyph aligns correctly.
            // Bars style needs additional upward shift
            topPadding: -(parent.height * Config.cavaGradientSplit) + (Config.cavaStyle === "bars" ? -2 : 0)
            color: Config.cavaGradientEnabled ? root._colorBot : root._colorTop
            font.family:      Config.fontFamily
            font.pixelSize:   Config.glyphSize
            font.letterSpacing: Config.cavaBarSpacing
            Behavior on color { ColorAnimation { duration: 300 } }
        }
    }
}
