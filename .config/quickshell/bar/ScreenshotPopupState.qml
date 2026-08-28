pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────────
//  ScreenshotPopupState  —  singleton driving the screenshot popup
//
//  Usage:
//      ScreenshotPopupState.toggle()
//
//  Flow:
//    1. Choose timing  : Immediate | Delayed (+ delay duration)
//    2. Choose region  : Entire Display | Select Region | Active Window
//    3. Choose action  : Copy | Save | Copy & Save | Edit (satty)
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Visibility ────────────────────────────────────────────────────────────
    property bool visible: false

    function toggle() {
        if (!root.visible) {
            root.reset()
            root.visible = true
        } else {
            root.visible = false
        }
    }
    function show() {
        root.reset()
        root.visible = true
    }
    function hide() {
        root.visible = false
    }

    // ── Step state  ("timing" → "region" → "action" → "countdown") ────────────
    property string step: "timing"
    property bool   busy: false

    // ── Selections ────────────────────────────────────────────────────────────
    property int    delaySeconds: 0   // 0 = immediate
    property string regionMode:  "output"  // "output" | "region" | "active"
    property string actionMode:  "copy"    // "copy"   | "save"   | "copysave" | "edit"

    // ── Derived paths ─────────────────────────────────────────────────────────
    readonly property string screenshotDir: {
        return Quickshell.env("HOME") + "/Pictures/Screenshots"
    }

    // ── Reset to first step ───────────────────────────────────────────────────
    function reset() {
        root.step          = "timing"
        root.busy          = false
        root.countdownVal  = 0
        root.delaySeconds  = 0
        root.regionMode    = "output"
        root.actionMode    = "copy"
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
            root.countdownVal = root.delaySeconds
            root.step = "countdown"
            countdownTimer.restart()
        } else {
            root.visible = false
            captureDelay.restart()
        }
    }

    // ── Countdown shown inside the popup ──────────────────────────────────────
    property int countdownVal: 0

    Timer {
        id: countdownTimer
        interval: 1000
        repeat:   true
        onTriggered: {
            root.countdownVal--
            if (root.countdownVal <= 0) {
                stop()
                root.visible = false
                captureDelay.restart()
            }
        }
    }

    // ── Delay before capture (compositor unmap buffer) ────────────────────────
    Timer {
        id: captureDelay
        interval: root.delaySeconds > 0 ? 1000 : 300
        repeat:   false
        onTriggered: _executeCapture()
    }

    // ── Execute capture pipeline ──────────────────────────────────────────────
    function _executeCapture() {
        const sDir    = root.screenshotDir
        const mode    = root.regionMode
        const action  = root.actionMode

        const cmd =
            'SCREENSHOT_DIR="' + sDir + '"; ' +
            'mkdir -p "$SCREENSHOT_DIR"; ' +
            'ts=$(date +"%Y%m%d-%H%M%S"); ' +
            'temp="/tmp/screenshot-qs-$ts.png"; ' +
            'out="$SCREENSHOT_DIR/screenshot-$ts.png"; ' +
            'MODE="' + mode + '"; ' +
            'ACTION="' + action + '"; ' +
            'if [ "$MODE" = "region" ]; then ' +
            '  GEOM=$(slurp 2>/dev/null); ' +
            '  [ -z "$GEOM" ] && exit 0; ' +
            'elif [ "$MODE" = "active" ]; then ' +
            '  GEOM=$(hyprctl activewindow -j 2>/dev/null | jq -r \'"\\(.at[0]),\\(.at[1]) \\(.size[0])x\\(.size[1])"\' 2>/dev/null); ' +
            '  [ "$GEOM" = "null,null nullxnull" ] && GEOM=""; ' +
            'else ' +
            '  GEOM=$(hyprctl monitors -j 2>/dev/null | jq -r \'.[] | select(.focused == true) | "\\(.x),\\(.y) \\(.width)x\\(.height)"\' 2>/dev/null); ' +
            'fi; ' +
            '[ -n "$GEOM" ] && grim -g "$GEOM" "$temp" || grim "$temp"; ' +
            '[ -f "$temp" ] || exit 0; ' +
            'if [ "$ACTION" = "copy" ]; then ' +
            '  wl-copy < "$temp" && rm -f "$temp"; ' +
            '  notify-send -a Screenshot -i camera-photo-symbolic "Screenshot" "Copied to clipboard"; ' +
            'elif [ "$ACTION" = "save" ]; then ' +
            '  mv "$temp" "$out"; ' +
            '  notify-send -a Screenshot -i "$out" "Screenshot" "$out"; ' +
            'elif [ "$ACTION" = "copysave" ]; then ' +
            '  wl-copy < "$temp" && mv "$temp" "$out"; ' +
            '  notify-send -a Screenshot -i "$out" "Screenshot" "Copied & Saved $out"; ' +
            'elif [ "$ACTION" = "edit" ]; then ' +
            '  mv "$temp" "$out"; ' +
            '  notify-send -a Screenshot -i "$out" "Screenshot" "Opening in Satty: $out"; ' +
            '  satty --filename "$out"; ' +
            'fi'

        Quickshell.execDetached(["bash", "-c", cmd])
        root.reset()
    }
}
