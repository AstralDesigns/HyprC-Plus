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
//    0. Choose mode    : Record | Stream
//    1. Choose audio   : System + Mic | System Audio | No Audio
//    2. Choose region  : Entire Display  | Select Region
//
//  Backed by gpu-screen-recorder (migrated from wf-recorder). Deep settings
//  (quality, codec, fps, color range, cursor, save directory, container) are
//  read LIVE from the gpu-screen-recorder-gui config at
//  ~/.config/gpu-screen-recorder/config, so whatever the user picks in the
//  GUI's Advanced view is honored here — nothing is hardcoded.
//
//  Notifications: sent via notify-send -a Recorder so the existing
//  NotificationsState.qml icon/redirect logic picks them up automatically
//  (ap.includes("record") → 󰑋 glyph + click-to-open-save-folder).
// ─────────────────────────────────────────────────────────────────────────────
Singleton {
    id: root

    // ── Visibility ────────────────────────────────────────────────────────────
    property bool visible: false

    function toggle() {
        if (!root.visible) root.reset()
        root.visible = !root.visible
    }
    function show()   { root.visible = true  }
    function hide()   { root.visible = false }

    // ── Step state  ("mode" → "audio" → "region") ────────────────────────────
    property string step: "mode"

    // ── Selections ────────────────────────────────────────────────────────────
    property string mode:       "record"  // "record" | "stream"
    // "mic"    → system output + default input  (label: "With Microphone")
    // "system" → system output only
    // "none"   → no audio
    property string audioMode:  "mic"
    property string regionMode: "output"  // "output" | "region"

    // ── Active-session state (survives reset()) ───────────────────────────────
    property bool   isRecording: false
    property string recordingAudioMode: "mic"
    property string recordingMode: "record"  // "record" | "stream"

    // Where _doStartRecording writes the actual output path so stopRecording
    // can find the file for the saved-notification.
    readonly property string _lastFileMarker: "/tmp/qs_gsr_last_file"

    // ── Reset to first step ───────────────────────────────────────────────────
    function reset() {
        root.step       = "mode"
        root.mode       = "record"
        root.audioMode  = "mic"
        root.regionMode = "output"
    }

    // ── Step transitions ──────────────────────────────────────────────────────
    function pickMode(m) {
        root.mode = m
        root.step = "audio"
    }

    function pickAudio(mode) {
        root.audioMode = mode
        root.step = "region"
    }

    function pickRegion(mode) {
        root.regionMode = mode
        root.hide()
        // Allow compositor to finish unmapping popup overlay before running slurp/gsr
        launchTimer.restart()
    }

    Timer {
        id: launchTimer
        interval: 250
        repeat: false
        onTriggered: _doStart()
    }

    // ── Process monitoring ────────────────────────────────────────────────────
    // Detects *any* gpu-screen-recorder process (started from our popup, the
    // GUI, or a hotkey) so the StartMenu toggle + CaptureMenu label pulse in
    // lockstep with the actual recording/streaming state.
    //
    // NOTE: Linux's /proc/PID/comm is limited to 15 chars, so the kernel sees
    // "gpu-screen-reco" (not the full 19-char name). `pgrep -x` matches against
    // comm, so we use the truncated form.
    Process {
        id: recCheckProc
        command: ["bash", "-c", "pgrep -x gpu-screen-reco > /dev/null && echo 1 || echo 0"]
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

    // ── Launch ────────────────────────────────────────────────────────────────
    function _doStart() {
        root.recordingAudioMode = root.audioMode
        root.recordingMode = root.mode
        Quickshell.execDetached(["bash", "-c",
            _launchScript(root.mode, root.audioMode, root.regionMode, root._lastFileMarker)])
        checkTimer.restart()
        root.reset()
    }

    // Config-driven script; eval used so $TARGET and $AUDIO word-split correctly.
    function _launchScript(mode, audio, region, marker) {
        const audioPart = audio === "mic"
            ? 'AUDIO=\'-a "default_output|default_input"\''
            : audio === "system"
                ? 'AUDIO=\'-a default_output\''
                : 'AUDIO=""'
        const regionPart = region === "region"
            ? 'GEOM=$(slurp -f "%wx%h+%x+%y" 2>/dev/null); [ -z "$GEOM" ] && exit 0; TARGET="-w region -region $GEOM";'
            : 'TARGET="-w $MON";'

        // Mode-specific output: record → file; stream → rtmp URL
        const outputPart = mode === "stream"
            ? [
                'SVC=$(g streaming.service)',
                'YKEY=$(g streaming.youtube.key)',
                'TKEY=$(g streaming.twitch.key)',
                'CURL=$(awk -v k=streaming.custom.url \'$1==k {sub(/^[^ ]+ +/,""); print}\' "$CFG" 2>/dev/null)',
                'case "$SVC" in',
                '  youtube) DEST="rtmp://a.rtmp.youtube.com/live2/$YKEY";; ',
                '  twitch)  DEST="rtmp://live.twitch.tv/app/$TKEY";;',
                '  *)       DEST="$CURL";;',
                'esac',
                '[ -z "$DEST" ] && { notify-send -a Recorder "Stream Error" "No stream key configured"; exit 1; }',
                'SFLAGS="-c flv -bm cbr"',
                'BITRATE=$(g main.video_bitrate); BITRATE=${BITRATE:-8000}',
                'QUALITY="$BITRATE"',
                'DESC="Stream Started"'
              ].join('\n')
            : [
                'mkdir -p "$SAVE_DIR"',
                'DEST="$SAVE_DIR/recording-$(date +%Y%m%d-%H%M%S).$CONT"',
                'SFLAGS=""',
                'DESC="Recording Started"'
              ].join('\n')

        const descLine = region === "region"
            ? 'DESC="$DESC (Region)"'
            : 'DESC="$DESC"'

        return [
            'CFG="$HOME/.config/gpu-screen-recorder/config"',
            'g() { awk -v k="$1" \'$1==k {print $2; exit}\' "$CFG" 2>/dev/null; }',
            'SAVE_DIR=$(awk -v k=record.save_directory \'$1==k {sub(/^[^ ]+ +/,""); print}\' "$CFG" 2>/dev/null)',
            'SAVE_DIR=${SAVE_DIR:-$HOME/Videos}',
            'QUALITY=$(g main.quality);      QUALITY=${QUALITY:-very_high}',
            'FPS=$(g main.fps);              FPS=${FPS:-60}',
            'ACODEC=$(g main.audio_codec);   ACODEC=${ACODEC:-opus}',
            'CRANGE=$(g main.color_range);   CRANGE=${CRANGE:-full}',
            'CODEC=$(g main.codec)',
            'case "$CODEC" in h264|hevc|av1|vp8|vp9|hevc_hdr|av1_hdr|hevc_10bit|av1_10bit) KFLAG="-k $CODEC";; *) KFLAG="";; esac',
            'FMODE=$(g main.framerate_mode)',
            'case "$FMODE" in cfr|vfr|content) FM="-fm $FMODE";; *) FM="";; esac',
            '[ "$(g main.record_cursor)" = true ] && CURSOR=yes || CURSOR=no',
            'CONT=$(g record.container); [ "$CONT" = matroska ] && CONT=mkv; CONT=${CONT:-mkv}',
            'MON=$(g main.record_area_option)',
            'case "$MON" in ""|region|portal|window|focused|screen) MON=screen;; esac',
            audioPart,
            outputPart,
            regionPart,
            descLine,
            'eval gpu-screen-recorder $TARGET $AUDIO $KFLAG $FM $SFLAGS -o "$DEST" -q "$QUALITY" -f "$FPS" -ac "$ACODEC" -cr "$CRANGE" -cursor "$CURSOR" -v no &>/dev/null &',
            'sleep 0.5',
            'if pgrep -x gpu-screen-reco > /dev/null; then',
            '  echo "$DEST" > "' + marker + '"',
            '  notify-send -a Recorder -i "" "$DESC" "$DEST"',
            'fi'
        ].join('\n')
    }

    // ── Stop Recording / Stream ───────────────────────────────────────────────
    function stopRecording() {
        root.isRecording = false
        const isStream = root.recordingMode === "stream"

        const cmd = isStream
            ? "pkill -SIGINT -x gpu-screen-reco; " +
              "sleep 1; " +
              "notify-send -a Recorder -i \"\" \"󰁯 Stream Ended\" \"Streaming stopped.\""
            : "pkill -SIGINT -x gpu-screen-reco; " +
              "sleep 1.5; " +
              "FILE=$(cat '" + root._lastFileMarker + "' 2>/dev/null); " +
              "[ -f \"$FILE\" ] || exit 0; " +
              "THUMB=/tmp/qs_rec_thumb.jpg; " +
              "ffmpeg -y -loglevel quiet -ss 00:00:01 -i \"$FILE\" -vframes 1 -q:v 3 \"$THUMB\" 2>/dev/null || true; " +
              "if [ -f \"$THUMB\" ]; then " +
              "  notify-send -a Recorder -i \"$THUMB\" '󰻂 Recording Saved' \"$FILE\"; " +
              "else " +
              "  notify-send -a Recorder -i '' '󰻂 Recording Saved' \"$FILE\"; " +
              "fi"

        Quickshell.execDetached(["bash", "-c", cmd])
        checkTimer.restart()
    }
}
