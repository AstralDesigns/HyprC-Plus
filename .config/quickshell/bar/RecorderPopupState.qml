pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// ─────────────────────────────────────────────────────────────────────────────
//  RecorderPopupState  —  singleton driving the screen recorder popup
//
//  Usage:
//      RecorderPopupState.toggle()
//
//  Flow:
//    1. Choose audio   : With Microphone | System Audio | No Audio
//    2. Choose region  : Entire Display  | Select Region
//
//  Launches wf-recorder with enhanced quality (libx264, crf=20, yuv420p).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Visibility ────────────────────────────────────────────────────────────
    property bool visible: false

    function toggle() { root.visible = !root.visible }
    function show()   { root.visible = true  }
    function hide()   { root.visible = false }

    // ── Step state  ("audio" → "region") ──────────────────────────────────────
    property string step: "audio"

    // ── Selections ────────────────────────────────────────────────────────────
    property string audioMode:  "mic"     // "mic" | "system" | "none"
    property string regionMode: "output"  // "output" | "region"

    // ── Recording State ───────────────────────────────────────────────────────
    property bool   isRecording: false
    property string currentFile: ""

    // ── Derived paths ─────────────────────────────────────────────────────────
    readonly property string recordingsDir: {
        return Quickshell.env("HOME") + "/Videos/Recordings"
    }

    // ── Reset to first step ───────────────────────────────────────────────────
    function reset() {
        root.step       = "audio"
        root.audioMode  = "mic"
        root.regionMode = "output"
    }

    // ── Step transitions ──────────────────────────────────────────────────────
    function pickAudio(mode) {
        root.audioMode = mode
        root.step = "region"
    }

    function pickRegion(mode) {
        root.regionMode = mode
        root.hide()
        // Allow compositor to finish unmapping popup overlay before running slurp/wf-recorder
        launchTimer.restart()
    }

    Timer {
        id: launchTimer
        interval: 250
        repeat: false
        onTriggered: _doStartRecording()
    }

    // ── Process monitoring ────────────────────────────────────────────────────
    Process {
        id: recCheckProc
        command: ["bash", "-c", "pgrep -x wf-recorder > /dev/null && echo 1 || echo 0"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                root.isRecording = (line.trim() === "1")
            }
        }
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: if (!recCheckProc.running) recCheckProc.running = true
    }

    Timer {
        id: checkTimer
        interval: 500
        repeat: false
        onTriggered: if (!recCheckProc.running) recCheckProc.running = true
    }

    function _doStartRecording() {
        const folder = root.recordingsDir
        const ts     = Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss")
        const dest   = folder + "/recording-" + ts + ".mp4"
        root.currentFile = dest

        const selectedAudio  = root.audioMode
        const selectedRegion = root.regionMode

        let audioCmd = ""
        if (selectedAudio === "mic") {
            audioCmd = 'AUDIO_DEV=$(pactl get-default-source 2>/dev/null); ' +
                       '[ -z "$AUDIO_DEV" ] && AUDIO_DEV=$(pactl info 2>/dev/null | awk -F": " "/Default Source:/ {print \\$2}" | xargs); ' +
                       '[ -z "$AUDIO_DEV" ] && AUDIO_DEV=$(pactl list short sources 2>/dev/null | awk "\\$2 !~ /\\.monitor$/ {print \\$2; exit}"); ' +
                       'if [ -n "$AUDIO_DEV" ]; then AUDIO_FLAG="-a --audio=$AUDIO_DEV"; else AUDIO_FLAG=""; fi; '
        } else if (selectedAudio === "system") {
            audioCmd = 'SINK=$(pactl get-default-sink 2>/dev/null); ' +
                       '[ -z "$SINK" ] && SINK=$(pactl info 2>/dev/null | awk -F": " "/Default Sink:/ {print \\$2}" | xargs); ' +
                       '[ -n "$SINK" ] && AUDIO_DEV="${SINK}.monitor"; ' +
                       '[ -z "$AUDIO_DEV" ] && AUDIO_DEV=$(pactl list short sources 2>/dev/null | awk "\\$2 ~ /\\.monitor$/ {print \\$2; exit}"); ' +
                       'if [ -n "$AUDIO_DEV" ]; then AUDIO_FLAG="-a --audio=$AUDIO_DEV"; else AUDIO_FLAG=""; fi; '
        } else {
            audioCmd = 'AUDIO_FLAG=""; '
        }

        const encParams = "-c libx264 -x yuv420p -p crf=20 -p preset=veryfast"

        let runCmd = ""
        if (selectedRegion === "region") {
            runCmd = "mkdir -p '" + folder + "'; " +
                     audioCmd +
                     "GEOM=$(slurp 2>/dev/null); " +
                     "if [ -z \"$GEOM\" ]; then exit 0; fi; " +
                     "wf-recorder $AUDIO_FLAG " + encParams + " -g \"$GEOM\" -f '" + dest + "' &>/dev/null & " +
                     "sleep 0.3; " +
                     "if pgrep -x wf-recorder > /dev/null; then " +
                     "  notify-send -a Recorder -i media-record '󰑋 Recording Started' 'Selected Region'; " +
                     "fi"
        } else {
            runCmd = "mkdir -p '" + folder + "'; " +
                     audioCmd +
                     "wf-recorder $AUDIO_FLAG " + encParams + " -f '" + dest + "' &>/dev/null & " +
                     "sleep 0.3; " +
                     "if pgrep -x wf-recorder > /dev/null; then " +
                     "  notify-send -a Recorder -i media-record '󰑋 Recording Started' 'Entire Display'; " +
                     "fi"
        }

        Quickshell.execDetached(["bash", "-c", runCmd])
        checkTimer.restart()
        root.reset()
    }

    // ── Stop Recording ────────────────────────────────────────────────────────
    function stopRecording() {
        const savedFile = root.currentFile
        root.currentFile = ""
        root.isRecording = false

        const sf = savedFile.replace(/'/g, "'\\''")
        const cmd =
            "pkill -SIGINT wf-recorder; " +
            "sleep 1.2; " +
            "FILE='" + sf + "'; " +
            "[ -f \"$FILE\" ] || FILE=$(ls -t ~/Videos/Recordings/*.mp4 2>/dev/null | head -1); " +
            "[ -f \"$FILE\" ] || exit 0; " +
            "THUMB=/tmp/qs_rec_thumb.jpg; " +
            "ffmpeg -y -loglevel quiet -ss 00:00:01 -i \"$FILE\" -vframes 1 -q:v 3 \"$THUMB\" 2>/dev/null || " +
            "magick \"${FILE}[24]\" -resize '640x360>' \"$THUMB\" 2>/dev/null || " +
            "magick \"${FILE}[0]\"  -resize '640x360>' \"$THUMB\" 2>/dev/null || true; " +
            "BASE=$(basename \"$FILE\"); " +
            "if [ -f \"$THUMB\" ]; then " +
            "  notify-send -a Recorder -i \"$THUMB\" '󰻂 Recording Saved' \"$BASE\"; " +
            "else " +
            "  notify-send -a Recorder -i media-record '󰻂 Recording Saved' \"$BASE\"; " +
            "fi"

        Quickshell.execDetached(["bash", "-c", cmd])
        checkTimer.restart()
    }
}
