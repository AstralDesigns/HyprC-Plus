pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────────
//  ScreenshotPopupState  —  singleton driving the screenshot popup
//
//  Usage (from keybind or bar button):
//      ScreenshotPopupState.toggle()
//
//  The popup flow mirrors the rofi script:
//    1. Choose timing  : Immediate | Delayed (+ delay duration)
//    2. Choose region  : Everything | Active Display
//    3. Choose action  : Copy | Save | Copy & Save | Edit
//
//  After the user picks all three, the singleton runs grim internally
//  and handles copy/save/satty.
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Visibility ────────────────────────────────────────────────────────────
    property bool visible: false

    function toggle() { root.visible = !root.visible }
    function show()   { root.visible = true  }
    function hide()   { root.visible = false }

    // ── Step state  ("timing" → "region" → "action" → "running" → "idle") ────
    property string step: "timing"   // current menu page
    property bool   busy: false      // capture in progress

    // ── Selections ────────────────────────────────────────────────────────────
    property int    delaySeconds: 0   // 0 = immediate
    property string regionMode:  ""   // "output" | "active"
    property string actionMode:  ""   // "copy"   | "save"  | "copysave" | "edit"

    // ── Status message shown during/after capture ─────────────────────────────
    property string statusMsg: ""

    // ── Derived paths ─────────────────────────────────────────────────────────
    readonly property string screenshotDir: {
        // Respect hyprcandy setting if present; fall back to ~/Pictures/Screenshots
        return Quickshell.env("HOME") + "/Pictures/Screenshots"
    }

    // ── Reset to first step ───────────────────────────────────────────────────
    function reset() {
        root.step          = "timing"
        root.busy          = false
        root.countdownVal  = 0
        root.delaySeconds  = 0
        root.regionMode    = ""
        root.actionMode    = ""
        root.statusMsg     = ""
        countdownTimer.stop()
    }

    // ── Called by popup buttons ───────────────────────────────────────────────
    function pickTiming(delaySec) {
        root.delaySeconds = delaySec
        root.step = "region"
    }

    function pickRegion(mode) {
        root.regionMode = mode
        root.step = "action"
    }

    function pickAction(mode) {
        root.actionMode = mode
        root.busy = true

        if (root.delaySeconds > 0) {
            // Show countdown inside the popup, then hide and capture
            root.countdownVal = root.delaySeconds
            root.step = "countdown"
            countdownTimer.restart()
        } else {
            // Immediate: hide popup, give compositor 200ms, then capture
            root.visible = false
            root.step    = "running"
            captureDelay.restart()
        }
    }

    // ── Countdown shown inside the popup ──────────────────────────────────────
    property int countdownVal: 0   // exposed to popup for display

    Timer {
        id: countdownTimer
        interval: 1000
        repeat:   true
        onTriggered: {
            root.countdownVal--
            if (root.countdownVal <= 0) {
                stop()
                // Hide popup — 0 is never shown, we go dark immediately
                root.visible = false
                root.step    = "running"
                // Wait 1s after hiding so compositor unmaps cleanly before grim fires
                captureDelay.restart()
            }
        }
    }

    // ── Delay before capture (compositor unmap buffer) ────────────────────────
    Timer {
        id: captureDelay
        interval: root.delaySeconds > 0 ? 1000 : 200
        repeat:   false
        onTriggered: _runCapture()
    }

    // ── Internal: build filename ──────────────────────────────────────────────
    function _makeFilename() {
        const now  = new Date()
        const pad  = n => String(n).padStart(2, "0")
        return root.screenshotDir + "/screenshot-"
             + now.getFullYear()
             + pad(now.getMonth() + 1)
             + pad(now.getDate())
             + "-"
             + pad(now.getHours())
             + pad(now.getMinutes())
             + pad(now.getSeconds())
             + ".png"
    }

    // ── Processes ─────────────────────────────────────────────────────────────

    // hyprctl activewindow — geometry for active window
    property string _windowGeometry: ""
    Process {
        id: activeWinProc
        command: ["bash", "-c",
            "hyprctl activewindow -j | jq -r '\"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])\"'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { root._windowGeometry = line.trim() }
        }
        onExited: function(code) {
            if (code !== 0 || root._windowGeometry === "" || root._windowGeometry === "null,null nullxnull") {
                root.statusMsg = "Could not get window geometry"
                root.busy      = false
                root.step      = "timing"
                root.visible   = true
                return
            }
            _fireGrim(root._windowGeometry)
        }
    }

    // hyprctl monitors — geometry for focused monitor
    property string _monitorGeometry: ""
    Process {
        id: monitorProc
        command: ["bash", "-c",
            "hyprctl monitors -j | jq -r '.[] | select(.focused == true) | \"\\(.x),\\(.y) \\(.width)x\\(.height)\"'"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { root._monitorGeometry = line.trim() }
        }
        onExited: function(code) {
            if (code !== 0 || root._monitorGeometry === "") {
                root.statusMsg = "Could not get monitor geometry"
                root.busy      = false
                root.step      = "timing"
                root.visible   = true
                return
            }
            _fireGrim(root._monitorGeometry)
        }
    }

    // mkdir -p screenshots dir
    Process {
        id: mkdirProc
        property string _nextGeometry: ""
        command: ["mkdir", "-p", root.screenshotDir]
        onExited: function() {
            _dispatchGeometry()
        }
    }

    // grim — the actual capture
    property string _tempFile:   ""
    property string _outputFile: ""

    Process {
        id: grimProc
        onExited: function(code) {
            if (code !== 0) {
                root.statusMsg = "grim failed to capture"
                root.busy      = false
                root.step      = "timing"
                root.visible   = true
                return
            }
            _handleAction()
        }
    }

    // wl-copy / mv — reused for copy, save, and copysave; the completion
    // message must branch on which action actually ran, since it previously
    // always assumed a clipboard copy regardless of the real command.
    Process {
        id: copyProc
        onExited: function(code) {
            const name = root._outputFile.split("/").pop()
            if (code !== 0) {
                root.statusMsg = "Copy failed"
            } else if (root.actionMode === "save") {
                root.statusMsg = "Saved " + name + " to " + root.screenshotDir
            } else if (root.actionMode === "copysave") {
                root.statusMsg = "Copied " + name + " to clipboard & Saved to " + root.screenshotDir
            } else {
                root.statusMsg = "Copied to clipboard"
            }
            _notifyAndDone()
        }
    }

    // satty / editor
    Process { id: editorProc }

    // notify-send
    Process { id: notifyProc }

    // cleanup temp file
    Process { id: cleanupProc }

    // ── Capture orchestration ─────────────────────────────────────────────────
    function _runCapture() {
        root._windowGeometry  = ""
        root._monitorGeometry = ""
        // ensure screenshot dir exists, then dispatch
        if (!mkdirProc.running) mkdirProc.running = true
    }

    function _dispatchGeometry() {
        if (root.regionMode === "active") {
            if (!activeWinProc.running) activeWinProc.running = true
        } else {
            // output (full monitor)
            if (!monitorProc.running) monitorProc.running = true
        }
    }

    function _fireGrim(geometry) {
        const ts      = new Date().getTime()
        root._tempFile   = "/tmp/screenshot-qs-" + ts + ".png"
        root._outputFile = root._makeFilename()

        grimProc.command = ["grim", "-g", geometry, root._tempFile]
        if (!grimProc.running) grimProc.running = true
    }

    function _handleAction() {
        const tmp = root._tempFile
        const out = root._outputFile
        const act = root.actionMode

        if (act === "copy") {
            copyProc.command = ["bash", "-c", "wl-copy < " + JSON.stringify(tmp)]
            if (!copyProc.running) copyProc.running = true
            // cleanup after copy
        } else if (act === "save") {
            copyProc.command = ["mv", tmp, out]
            copyProc.running = true
        } else if (act === "copysave") {
            // copy then move
            const cmd = "wl-copy < " + JSON.stringify(tmp) + " && mv " + JSON.stringify(tmp) + " " + JSON.stringify(out)
            copyProc.command = ["bash", "-c", cmd]
            copyProc.running = true
        } else if (act === "edit") {
            // move to output then open satty
            const cmd = "mv " + JSON.stringify(tmp) + " " + JSON.stringify(out)
            editorProc.command = ["bash", "-c", cmd +
                " && satty --filename " + JSON.stringify(out)]
            if (!editorProc.running) editorProc.running = true
            root.statusMsg = "Opening in Satty"
            _notifyAndDone()
        }
    }

    function _notifyAndDone() {
        const msg = root.statusMsg
        notifyProc.command = ["notify-send", "-a", "Screenshot",
                              "-i", "camera-photo-symbolic", "Screenshot", msg]
        if (!notifyProc.running) notifyProc.running = true
        root.busy = false
        root.reset()
    }
}
