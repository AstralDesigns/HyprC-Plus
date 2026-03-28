imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gio = '2.0';
imports.gi.versions.GLib = '2.0';
imports.gi.versions.Gdk = '4.0';
imports.gi.versions.Soup = '3.0';
imports.gi.versions.GdkPixbuf = '2.0';
const { Gtk, Gio, GLib, Gdk, Soup, GdkPixbuf } = imports.gi;

const scriptDir = GLib.path_get_dirname(imports.system.programInvocationName);
imports.searchPath.unshift(scriptDir);

// NOTE: gtk-video-player and media-detector no longer imported —
// video logic removed to eliminate memory leak from Gtk.Video + GStreamer.
// Art is handled entirely in-process with GdkPixbuf + Cairo.
// For video files, a single first-frame thumbnail is extracted via ffmpeg
// at startup — no periodic refresh, no GStreamer involved.

const BUS_NAME_PREFIX = 'org.mpris.MediaPlayer2.';
const MPRIS_PATH = '/org/mpris/MediaPlayer2';

// ── Placeholder glyph for audio with no art (Nerd Font:  = double-note) ─
const PLACEHOLDER_GLYPH = '󰽲';

// ── Source dot glyphs (Nerd Font mdi icons) ──────────────────────────────
// mdi:play-circle  󰐊  mdi:pause-circle  󰏤  mdi:stop-circle  󰓛
const SRC_PLAYING  = '󰐊';
const SRC_PAUSED   = '󰏤';
const SRC_STOPPED  = '󰓛';
const SRC_NO_MEDIA = '󰎊';   // mdi:music-note-off — shown when no source detected

function getMprisPlayersAsync(callback) {
    Gio.DBus.session.call(
        'org.freedesktop.DBus', '/org/freedesktop/DBus',
        'org.freedesktop.DBus', 'ListNames',
        null, null, Gio.DBusCallFlags.NONE, -1, null,
        (source, res) => {
            try {
                const result = source.call_finish(res);
                const names = result.deep_unpack()[0];
                // Exclude playerctld — it's a proxy daemon that mirrors whichever
                // player is currently active, so it always appears as a duplicate.
                callback(names.filter(n =>
                    n.startsWith(BUS_NAME_PREFIX) &&
                    !n.toLowerCase().includes('playerctld')
                ));
            } catch (e) { callback([]); }
        }
    );
}

function createMprisProxy(busName) {
    return Gio.DBusProxy.new_sync(
        Gio.DBus.session, Gio.DBusProxyFlags.NONE, null,
        busName, MPRIS_PATH, 'org.mpris.MediaPlayer2.Player', null
    );
}

// Cached PipeWire/PulseAudio sink-input result.
// Uses `pactl list short sink-inputs` — tiny output vs pw-cli list-objects.
let _pwCache = { result: null, ts: 0 };
const PW_CACHE_TTL_MS = 5000;  // cache for 5 seconds

function getActivePipeWireSinkInfo(callback) {
    const now = GLib.get_monotonic_time() / 1000;  // µs → ms
    if (now - _pwCache.ts < PW_CACHE_TTL_MS) { callback(_pwCache.result); return; }
    try {
        // `pactl list short sink-inputs` output format (one line per stream):
        //   <index>\t<sink>\t<client>\t<format>\t<state>
        // Much smaller than pw-cli list-objects which dumps all Node objects.
        const proc = Gio.Subprocess.new(
            ['pactl', 'list', 'short', 'sink-inputs'],
            Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
        );
        proc.communicate_utf8_async(null, null, (p, res) => {
            const ts = GLib.get_monotonic_time() / 1000;
            let output = '';
            try {
                const [, stdout] = p.communicate_utf8_finish(res);
                output = stdout || '';
            } catch (e) {
                _pwCache = { result: null, ts };
                callback(null);
                return;
            }
            // Any line present = at least one sink-input is running
            const lines = output.trim().split('\n').filter(l => l.trim());
            if (lines.length > 0) {
                // We don't get app name from `short` output — use client index
                // as a proxy for "something is playing". App name display is
                // cosmetic; showing "Audio playing" is sufficient.
                const res2 = { appName: null };
                _pwCache = { result: res2, ts };
                callback(res2);
            } else {
                _pwCache = { result: null, ts };
                callback(null);
            }
        });
    } catch (e) {
        _pwCache = { result: null, ts: GLib.get_monotonic_time() / 1000 };
        callback(null);
    }
}

// ── Extract first-frame thumbnail from a local video file via ffmpeg ─────
// Always seeks to 3s in (avoids black frames at start on most content).
// Writes to a fixed temp path — never accumulates files.
const THUMB_TMP = GLib.build_filenamev([GLib.get_tmp_dir(), 'candy-media-thumb.jpg']);

function extractVideoThumbnail(fileUri) {
    try {
        const path = fileUri.replace('file://', '');
        const cmd = `ffmpeg -y -loglevel error -ss 3 -i "${path}" -vframes 1 -vf "scale=220:-1" "${THUMB_TMP}"`;
        const [ok, , , status] = GLib.spawn_command_line_sync(cmd);
        if (!ok || status !== 0) return null;
        return GdkPixbuf.Pixbuf.new_from_file(THUMB_TMP);
    } catch (e) { return null; }
}

function createMediaBox() {

    // ── Load user color theme + file monitor for fast reload ──────────────
    // Module-level singleton: when both candy-utils and media are open they
    // share the same display, so we must not both add providers at USER+1 —
    // that causes two cascade recalculations on every theme change and a
    // brief flash where the intermediate state is visible.
    // We keep a single provider reference at module scope and reuse it.
    const _gtk4ColorsPath = GLib.build_filenamev([GLib.get_home_dir(), '.config', 'gtk-4.0', 'colors.css']);
    const _gtk3ColorsPath = GLib.build_filenamev([GLib.get_home_dir(), '.config', 'gtk-3.0', 'colors.css']);
    let _colorDebounce = 0;
    let _colorMonitor = null;

    // Lazily initialised once across all createMediaBox() calls in this process.
    // (In practice the daemon calls createMediaBox once and keeps the widget alive.)
    if (!createMediaBox._sharedColorProvider) {
        createMediaBox._sharedColorProvider = new Gtk.CssProvider();
    }
    const _userColorProvider = createMediaBox._sharedColorProvider;

    function _reloadColorCSS() {
        const display = Gdk.Display.get_default();
        if (!display) return;
        // Only remove + re-add if we actually need to swap the file contents.
        // Using load_from_path on an already-loaded provider replaces its rules
        // in-place without toggling the display registration — no double recalc.
        const path = GLib.file_test(_gtk4ColorsPath, GLib.FileTest.EXISTS) ? _gtk4ColorsPath : _gtk3ColorsPath;
        try {
            _userColorProvider.load_from_path(path);
            // add_provider_for_display is idempotent for the same object —
            // GTK ignores duplicate insertions, so this is safe to call every reload.
            Gtk.StyleContext.add_provider_for_display(display, _userColorProvider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
        } catch (e) {}
    }
    _reloadColorCSS();

    const _watchPath = GLib.file_test(_gtk4ColorsPath, GLib.FileTest.EXISTS) ? _gtk4ColorsPath : _gtk3ColorsPath;
    try {
        const colFile = Gio.File.new_for_path(_watchPath);
        _colorMonitor = colFile.monitor_file(Gio.FileMonitorFlags.NONE, null);
        _colorMonitor.connect('changed', () => {
            if (_colorDebounce) GLib.source_remove(_colorDebounce);
            _colorDebounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
                _colorDebounce = 0;
                _reloadColorCSS();
                _resolveBgColors(bgDrawingArea);
                bgDrawingArea.queue_draw();
                cavaRingDa.queue_draw();
                // Reconnect cava ring if manager restarted during theme change
                _startCava();
                // Toggle CSS class to force sub-node re-resolve on volume slider
                volumeScale.remove_css_class('media-volume-bar');
                volumeScale.add_css_class('media-volume-bar');
                return GLib.SOURCE_REMOVE;
            });
        });
    } catch (e) {}

    // ── Static CSS ─────────────────────────────────────────────────────────
    const staticCss = new Gtk.CssProvider();
    staticCss.load_from_data(`
        .media-player-frame {
            border-radius: 22px;
            min-width: 244px;
            min-height: 118px;
            padding: 0px;
            box-shadow: 0 4px 32px 0 rgba(0,0,0,0.22);
        }
        .media-player-bg-overlay {
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
            filter: blur(12px) brightness(0.7);
            opacity: 0.7;
            border-radius: 22px;
        }
        .media-player-blurred-bg {
            background-color: rgba(0, 0, 0, 0.12);
            opacity: 0.95;
            border-radius: 22px;
        }
        .media-artist-label {
            font-size: 0.9em;
            font-weight: 700;
            color: @primary;
            margin-top: 4px;
            text-shadow: 0 0 8px rgba(224,224,224,0.6);
        }
        .media-title-label {
            font-size: 1.1em;
            font-weight: 600;
            color: @primary;
            text-shadow: 0 0 8px rgba(255,255,255,0.7);
        }
        .media-progress-bar {
            margin-top: 4px;
            margin-bottom: 4px;
            color: @primary;
            text-shadow: 0 0 8px @primary;
        }
        .media-progress-bar progressbar trough {
            background-color: rgba(255,255,255,0.2);
            border-radius: 4px;
        }
        .media-progress-bar progressbar fill {
            background-color: @primary;
            border-radius: 4px;
            box-shadow: 0 0 8px rgba(0,255,255,0.6);
        }
        .media-progress-bar.seeking progressbar fill {
            background-color: #ff6b6b;
            box-shadow: 0 0 12px rgba(255,107,107,0.8);
        }
        .media-progress-bar.paused progressbar fill {
            background-color: #666666;
            box-shadow: none;
        }
        .media-info-center    { margin: 0; padding: 0; }
        .media-info-container { margin-bottom: 4px; }
        .media-controls-center {
            padding-right: 16px;
            margin-top: 8px;
            margin-bottom: 4px;
        }
        .media-controls-center button {
            background-color: @blur_background;
            border: 1.5px solid @primary;
            border-radius: 4px;
            color: @primary;
            text-shadow: 0 0 6px rgba(255,255,255,0.7);
            transition: all 0.2s ease;
            min-width: 24px;
            min-height: 24px;
            padding: 4px;
        }
        .media-controls-center button:hover {
            background-color: @inverse_primary;
            border-color: @inverse_primary;
            box-shadow: 0 0 1px 2px @primary, 0 0 0 2px @primary inset;
            color: @primary;
        }
        .media-controls-center button:active {
            background-color: @inverse_primary;
            transform: scale(0.95);
            color: @primary;
        }
        .media-controls-center button.shuffle-active {
            background-color: @inverse_primary;
            border-color: @inverse_primary;
            box-shadow: 0 0 8px 2px @background, 0 0 0 2px @background inset;
            color: @background;
        }
        .media-controls-center button.loop-track {
            background-color: @inverse_primary;
            border-color: @inverse_primary;
            box-shadow: 0 0 8px 2px @background, 0 0 0 2px @background inset;
            color: @background;
        }
        .media-controls-center button.loop-playlist {
            background-color: @inverse_primary;
            border-color: @inverse_primary;
            box-shadow: 0 0 10px 2px @background, 0 0 0 2px @background inset;
            color: @background;
        }
        .rotating-thumbnail { border-radius: 9999px; margin: 6px; }

        /* ── Source selector sidebar (left strip) ─────────────────── */
        .media-sources-bar {
            padding: 2px 2px;
            border-radius: 16px;
            background-color: rgba(0,0,0,0.18);
            margin-right: 2px;
            margin-left: 1px;
        }
        .media-source-btn {
            min-width: 22px;
            min-height: 22px;
            padding: 3px 2px;
            border-radius: 999px;
            background: transparent;
            border: none;
            box-shadow: none;
            color: @primary;
            opacity: 0.45;
            font-size: 10px;
            transition: all 0.15s ease;
        }
        .media-source-btn:hover {
            opacity: 0.8;
            background-color: rgba(255,255,255,0.08);
        }
        .media-source-btn.source-active {
            opacity: 1.0;
            color: @primary;
            text-shadow: 0 0 8px @primary;
        }
        .media-source-btn.source-playing {
            opacity: 0.85;
        }
        .media-source-btn.source-no-media {
            opacity: 0.85;
            cursor: default;
        }
        .media-source-btn.source-no-media:hover {
            background-color: transparent;
            opacity: 0.25;
        }

        /* ── Volume slider (right strip) ──────────────────────────── */
        .media-volume-bar {
            margin-right: 6px;
            margin-left: 6px;
            padding: 6px 2px;
        }
        .media-volume-bar trough {
            min-width: 4px;
            border: none;
            border-radius: 4px;
            background-color: background-color: rgba(0,0,0,0.18);
        }
        .media-volume-bar highlight {
            min-width: 4px;
            border-radius: 4px;
            background-color: @primary;
            box-shadow: 0 0 6px rgba(0,255,255,0.5);
        }
        .media-volume-bar slider {
            min-width: 14px;
            min-height: 14px;
            border: 1px solid @primary;
            border-radius: 4px;
            background-color: @inverse_primary;
            box-shadow: none;
        }
        .media-volume-bar slider:hover {
            box-shadow: 0 0 2px @primary, 0 0 0 2px rgba(255,255,255,0.2);
        }
    `, -1);
    Gtk.StyleContext.add_provider_for_display(
        Gdk.Display.get_default(), staticCss,
        Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
    );

    // ── JS-driven liquid-metal background (Cairo) ───────────────────────────
    let phase = 0;
    // PHASE_STEP sized so a full cycle takes ~50 s (visually slow, meditative)
    const PHASE_STEP = (2 * Math.PI) / (8 * 50);  // 8fps * 50s

    function lx(p, f, o) { return (Math.sin(p * f + o) * 0.5 + 0.5); }
    function ly(p, f, o) { return (Math.cos(p * f + o) * 0.5 + 0.5); }
    function bs(p, f, o, lo, hi) { return lo + (Math.sin(p * f + o) * 0.5 + 0.5) * (hi - lo); }

    let _bgColors = null;
    function _resolveBgColors(widget) {
        try {
            const sc = widget.get_style_context();
            const [ok1, c1] = sc.lookup_color('inverse_primary');
            const [ok2, c2] = sc.lookup_color('background');
            const [ok3, c3] = sc.lookup_color('blur_background');
            const [ok4, c4] = sc.lookup_color('primary');
            if (ok1 && ok2) {
                _bgColors = {
                    inv: { r: c1.red, g: c1.green, b: c1.blue, a: c1.alpha },
                    bg:  { r: c2.red, g: c2.green, b: c2.blue, a: c2.alpha },
                    blur: ok3 ? { r: c3.red, g: c3.green, b: c3.blue, a: c3.alpha }
                               : { r: c2.red, g: c2.green, b: c2.blue, a: 0.5 },
                    // @primary — used for placeholder glyph colour
                    pri: ok4 ? { r: c4.red, g: c4.green, b: c4.blue }
                              : { r: 1, g: 1, b: 1 },  // fallback: white
                };
            }
        } catch (e) { }
    }

    const bgDrawingArea = new Gtk.DrawingArea();
    bgDrawingArea.set_hexpand(true);
    bgDrawingArea.set_vexpand(true);
    bgDrawingArea.set_can_target(false);
    const CairoModule = imports.gi.cairo;

    bgDrawingArea.set_draw_func((_da, cr, w, h) => {
        if (!_bgColors) return;
        const p = phase;
        const φ = 1.6180339887, r2 = 1.4142135623, r3 = 1.7320508075;
        const inv = _bgColors.inv, bg = _bgColors.bg, blur = _bgColors.blur;
        const rad = 22;
        cr.newSubPath();
        cr.arc(w - rad, rad, rad, -Math.PI / 2, 0);
        cr.arc(w - rad, h - rad, rad, 0, Math.PI / 2);
        cr.arc(rad, h - rad, rad, Math.PI / 2, Math.PI);
        cr.arc(rad, rad, rad, Math.PI, 3 * Math.PI / 2);
        cr.closePath();
        cr.clip();
        cr.setSourceRGBA(bg.r, bg.g, bg.b, 1);
        cr.rectangle(0, 0, w, h);
        cr.fill();
        const blobs = [
            [lx(p,φ*0.7,0),    ly(p,φ*0.5,0.5),  bs(p,0.41,0,0.55,0.75), bs(p,0.53,1.1,0.4,0.65), inv,  bs(p,0.67,0.3,0.55,0.8)],
            [lx(p,r2*0.6,1.2),  ly(p,r2*0.8,2.1), bs(p,0.37,2.3,0.45,0.7), bs(p,0.61,0.7,0.5,0.72), bg,   bs(p,0.53,1.7,0.5,0.75)],
            [lx(p,r3*0.45,2.5), ly(p,r3*0.55,0.8),bs(p,0.29,1.5,0.6,0.8),  bs(p,0.47,3.2,0.35,0.6), inv,  bs(p,0.71,2.9,0.45,0.7)],
            [lx(p,0.53,3.7),    ly(p,0.71,1.4),   bs(p,0.55,3,0.4,0.65),   bs(p,0.33,1.8,0.55,0.75),bg,   bs(p,0.43,0.6,0.55,0.78)],
            [lx(p,φ*0.38,4.2),  ly(p,r2*0.42,3),  bs(p,0.43,0.9,0.5,0.68), bs(p,0.59,2.5,0.42,0.66),inv,  bs(p,0.59,3.5,0.48,0.72)],
            [lx(p,0.29,1.8),    ly(p,0.37,5.1),   bs(p,0.31,4.1,0.65,0.85),bs(p,0.49,0.3,0.38,0.58),blur, bs(p,0.37,1.2,0.52,0.76)],
        ];
        for (const [cxF,cyF,wF,hF,color,fade] of blobs) {
            const cx0 = cxF * w, cy0 = cyF * h;
            const radius = Math.max(wF * w, hF * h) / 2;
            if (radius < 1) continue;
            const g = new CairoModule.RadialGradient(cx0, cy0, 0, cx0, cy0, radius);
            g.addColorStopRGBA(0, color.r, color.g, color.b, 0.85);
            g.addColorStopRGBA(fade, color.r, color.g, color.b, 0.3);
            g.addColorStopRGBA(1, color.r, color.g, color.b, 0);
            cr.setSource(g);
            cr.rectangle(0, 0, w, h);
            cr.fill();
        }
    });

    // ── Loop state ─────────────────────────────────────────────────────────
    let loopMode = 0;
    let lastRenderedLoopMode = -1;
    const loopModes = ['None', 'Track', 'Playlist'];
    const loopLabels = ['No Loop', 'Looping Track', 'Looping Playlist'];

    // ── Source sidebar ─────────────────────────────────────────────────────
    // Vertical strip on the far left — one dot button per detected MPRIS source.
    // Clicking a dot manually selects that source.
    // Scroll on the sidebar cycles sources.
    const sourcesBar = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL,
        spacing: 4,
        valign: Gtk.Align.CENTER,
        halign: Gtk.Align.CENTER,
    });
    sourcesBar.add_css_class('media-sources-bar');

    // ── Volume slider ──────────────────────────────────────────────────────
    // Smooth vertical GtkScale on the far right. Reads/writes MPRIS Volume.
    const _volAdj = new Gtk.Adjustment({
        value: 1.0, lower: 0.0, upper: 1.0,
        step_increment: 0.05, page_increment: 0.1, page_size: 0,
    });
    const volumeScale = new Gtk.Scale({
        orientation: Gtk.Orientation.VERTICAL,
        adjustment: _volAdj,
        inverted: true,      // top of slider = max volume
        draw_value: false,
    });
    volumeScale.set_size_request(28, 100);
    volumeScale.set_valign(Gtk.Align.CENTER);
    volumeScale.add_css_class('media-volume-bar');
    volumeScale.set_tooltip_text('Volume');

    // ── Widget tree ────────────────────────────────────────────────────────
    const mediaPlayerBox = new Gtk.Box({
        orientation: Gtk.Orientation.HORIZONTAL, spacing: 0,
        halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
        hexpand: true, vexpand: true,
    });
    // Slightly wider than original to accommodate sidebar + volume strip
    mediaPlayerBox.set_size_request(560, 118);
    mediaPlayerBox.set_margin_top(12);
    mediaPlayerBox.set_margin_bottom(12);
    mediaPlayerBox.set_margin_start(12);
    mediaPlayerBox.set_margin_end(12);
    mediaPlayerBox.get_style_context().add_class('media-player-frame');

    const artistLabel = new Gtk.Label({
        label: '', halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
        xalign: 0, ellipsize: 3, max_width_chars: 24, wrap: false,
    });
    artistLabel.add_css_class('media-artist-label');

    const titleLabel = new Gtk.Label({
        label: 'No Media', halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
        xalign: 0, ellipsize: 3, max_width_chars: 24, wrap: false,
    });
    titleLabel.add_css_class('media-title-label');

    // ── Rotating thumbnail (Cairo DrawingArea) ─────────────────────────────
    const THUMB_SIZE = 110;
    const thumbDa = new Gtk.DrawingArea();
    thumbDa.set_size_request(THUMB_SIZE, THUMB_SIZE);
    thumbDa.set_content_width(THUMB_SIZE);
    thumbDa.set_content_height(THUMB_SIZE);
    thumbDa.set_valign(Gtk.Align.CENTER);
    thumbDa.set_halign(Gtk.Align.CENTER);
    thumbDa.set_margin_top(4);
    thumbDa.set_margin_bottom(4);
    thumbDa.set_margin_start(0);
    thumbDa.set_margin_end(0);

    const thumb = {
        pixbuf: null,
        angle: 0,
        speed: 0.10,
        timerId: 0,
        playing: false,
        isPlaceholder: true,
    };

    // ── Cava ring (slim radial bars outside the disc) ──────────────────────
    const CAVA_SCRIPT    = GLib.build_filenamev([GLib.get_home_dir(), '.config', 'waybar', 'scripts', 'cava.py']);
    const CAVA_SOCK      = GLib.build_filenamev([GLib.get_user_runtime_dir(), 'hyprcandy', 'cava.sock']);
    const CAVA_RANGE     = 15;    // must match manager --range
    const CAVA_N_MAX     = 64;    // buffer ceiling; actual count comes from socket
    const CAVA_GAP       = 4;     // px between disc edge and bar base
    const CAVA_BAR_MAX   = 27;    // max bar length outward at full amplitude (×1.5)
    const CAVA_BAR_W     = 1.5;   // stroke width — slim
    // Ring canvas sized to fully contain bars within its own allocation.
    // No clip_children override needed — bars never exceed this boundary.
    const CAVA_RING_SIZE = THUMB_SIZE + 2 * (CAVA_GAP + CAVA_BAR_MAX + 2);

    const _cavaBars  = new Float32Array(CAVA_N_MAX);
    let   _cavaN     = 32;
    let   _cavaOn    = false;
    let   _cavaConn  = null;
    let   _cavaStream= null;

    const cavaRingDa = new Gtk.DrawingArea();
    cavaRingDa.set_size_request(CAVA_RING_SIZE, CAVA_RING_SIZE);
    cavaRingDa.set_content_width(CAVA_RING_SIZE);
    cavaRingDa.set_content_height(CAVA_RING_SIZE);
    cavaRingDa.set_valign(Gtk.Align.CENTER);
    cavaRingDa.set_halign(Gtk.Align.CENTER);
    cavaRingDa.set_can_target(false);

    cavaRingDa.set_draw_func((_w, cr, w, h) => {
        if (!_cavaOn) return;
        const cx = w / 2, cy = h / 2;
        const rInner = THUMB_SIZE / 2 + CAVA_GAP;
        const _cp = _bgColors ? _bgColors.pri : { r: 0.6, g: 0.85, b: 1.0 };
        const N  = _cavaN;
        const dA = (2 * Math.PI) / N;
        const s0 = -Math.PI / 2;
        cr.setLineWidth(CAVA_BAR_W);
        cr.setLineCap(1);
        for (let i = 0; i < N; i++) {
            const amp = _cavaBars[i];
            if (amp < 0.01) continue;
            const a = s0 + (i + 0.5) * dA;
            const len = amp * CAVA_BAR_MAX;
            const cos = Math.cos(a), sin = Math.sin(a);
            cr.setSourceRGBA(_cp.r, _cp.g, _cp.b, 0.20 + amp * 0.80);
            cr.moveTo(cx + rInner * cos,         cy + rInner * sin);
            cr.lineTo(cx + (rInner + len) * cos, cy + (rInner + len) * sin);
            cr.stroke();
        }
    });

    function _cavaReadLine() {
        if (!_cavaOn || !_cavaStream) return;
        // PRIORITY_DEFAULT: cava data must be processed before animation ticks
        // (which are PRIORITY_LOW). Without this, frames pile up in the socket
        // buffer while the main loop is busy and the ring looks jagged.
        _cavaStream.read_line_async(GLib.PRIORITY_DEFAULT, null, (s, res) => {
            if (!_cavaOn) return;
            try {
                const [line] = s.read_line_finish_utf8(res);
                if (line === null) {
                    // EOF — manager shut down (e.g. waybar hidden, cava.py auto-exited).
                    // Use the backoff-retry path: fast first attempt, slow down if needed.
                    _cavaOn = false; _cavaConn = null; _cavaStream = null;
                    _scheduleRetry();
                    return;
                }
                const parts = line.trim().split(';').filter(v => /^\d+$/.test(v));
                if (parts.length > 1) {
                    _cavaN = Math.min(parts.length, CAVA_N_MAX);
                    for (let i = 0; i < _cavaN; i++) {
                        const raw = Math.min(parseInt(parts[i]), CAVA_RANGE) / CAVA_RANGE;
                        _cavaBars[i] = raw > _cavaBars[i]
                            ? _cavaBars[i] * 0.25 + raw * 0.75
                            : _cavaBars[i] * 0.55 + raw * 0.45;
                    }
                    cavaRingDa.queue_draw();
                }
                _cavaReadLine();
            } catch (e) {
                // Connection error — same backoff-retry path as EOF.
                _cavaOn = false; _cavaConn = null; _cavaStream = null;
                _scheduleRetry();
            }
        });
    }

    // ── Cava reconnect state ───────────────────────────────────────────────
    // _cavaRetryCount tracks how many consecutive failed connect attempts have
    // been made since the last successful connection.  The backoff schedule is:
    //   attempts 1-3  → 1 s   (fast retry: manager may just be starting up)
    //   attempts 4-6  → 3 s   (medium: give waybar cava modules time to relaunch it)
    //   attempts 7+   → 10 s  (slow: something is genuinely wrong, don't hammer)
    let _cavaRetryCount = 0;
    let _cavaRetryTimer = 0;  // GLib source id for pending retry

    function _cavaClearRetry() {
        if (_cavaRetryTimer) { GLib.source_remove(_cavaRetryTimer); _cavaRetryTimer = 0; }
    }

    function _cavaRetryDelay() {
        if (_cavaRetryCount <= 3)  return 1000;
        if (_cavaRetryCount <= 6)  return 3000;
        return 10000;
    }

    function _cavaConnect() {
        if (_cavaOn) return;
        if (!GLib.file_test(CAVA_SOCK, GLib.FileTest.EXISTS)) return;
        try {
            const client = new Gio.SocketClient();
            client.connect_async(Gio.UnixSocketAddress.new(CAVA_SOCK), null, (sc, res) => {
                try {
                    _cavaConn   = sc.connect_finish(res);
                    _cavaStream = new Gio.DataInputStream({ base_stream: _cavaConn.get_input_stream() });
                    _cavaOn     = true;
                    _cavaRetryCount = 0;  // reset on success
                    _cavaClearRetry();
                    _cavaReadLine();
                } catch (e) {
                    _cavaConn = null; _cavaStream = null;
                    _scheduleRetry();
                }
            });
        } catch (e) { _scheduleRetry(); }
    }

    function _scheduleRetry() {
        if (_cavaOn || _cavaRetryTimer) return;
        _cavaRetryCount++;
        const delay = _cavaRetryDelay();
        _cavaRetryTimer = GLib.timeout_add(GLib.PRIORITY_LOW, delay, () => {
            _cavaRetryTimer = 0;
            _startCava();
            return GLib.SOURCE_REMOVE;
        });
    }

    function _startCava() {
        if (_cavaOn) return;
        if (GLib.file_test(CAVA_SOCK, GLib.FileTest.EXISTS)) {
            // Socket already up (waybar cava module may have restarted the manager) — connect now
            _cavaConnect();
        } else {
            // Socket gone: waybar was hidden and the cava manager auto-shut down.
            // Re-launch the manager ourselves, then schedule a connect once it is ready.
            if (GLib.file_test(CAVA_SCRIPT, GLib.FileTest.EXISTS) && GLib.find_program_in_path('python3')) {
                try {
                    Gio.Subprocess.new(
                        ['python3', CAVA_SCRIPT, 'manager'],
                        Gio.SubprocessFlags.STDOUT_SILENCE | Gio.SubprocessFlags.STDERR_SILENCE
                    );
                } catch (e) {}
            }
            // Give the manager ~2.5 s to create the socket, then attempt to connect.
            // If that connect also fails, _scheduleRetry() will keep trying with backoff.
            if (!_cavaRetryTimer) {
                _cavaRetryTimer = GLib.timeout_add(GLib.PRIORITY_LOW, 2500, () => {
                    _cavaRetryTimer = 0;
                    _cavaConnect();
                    return GLib.SOURCE_REMOVE;
                });
            }
        }
    }

    function _stopCava() {
        _cavaOn = false;
        _cavaClearRetry();
        _cavaRetryCount = 0;
        if (_cavaConn) { try { _cavaConn.close(null); } catch (e) {} _cavaConn = null; }
        _cavaStream = null;
        _cavaBars.fill(0);
        cavaRingDa.queue_draw();
    }

    let _cachedPangoLayout = null;
    let _cachedPangoFd = null;
    let _cachedGlossGradient = null;
    let _cachedGlossR = -1;
    let _cachedGlossCx = -1;
    let _cachedGlossCy = -1;

    thumbDa.set_draw_func((_w, cr, w, h) => {
        const cx = w / 2, cy = h / 2;
        const r = Math.min(w, h) / 2 - 1;
        cr.save();
        cr.arc(cx, cy, r, 0, 2 * Math.PI);
        cr.clip();
        if (thumb.pixbuf && !thumb.isPlaceholder) {
            cr.translate(cx, cy);
            cr.rotate(thumb.angle * Math.PI / 180);
            cr.translate(-cx, -cy);
            const pw = thumb.pixbuf.get_width(), ph = thumb.pixbuf.get_height();
            const sc = (2 * r) / Math.min(pw, ph);
            cr.scale(sc, sc);
            Gdk.cairo_set_source_pixbuf(cr, thumb.pixbuf, (w / sc - pw) / 2, (h / sc - ph) / 2);
            cr.paint();
        } else {
            cr.setSourceRGBA(0, 0, 0, 0);
            cr.paint();
        }
        cr.restore();
        // Gloss + spindle are visual chrome for album-art rotation —
        // skip entirely when showing the placeholder glyph so no
        // semi-transparent circles appear behind it.
        if (thumb.pixbuf && !thumb.isPlaceholder) {
            cr.save();
            cr.arc(cx, cy, r, 0, 2 * Math.PI);
            cr.clip();
            try {
                const Cairo = imports.gi.cairo;
                if (_cachedGlossR !== r || _cachedGlossCx !== cx || _cachedGlossCy !== cy) {
                    _cachedGlossGradient = new Cairo.RadialGradient(cx, cy - r * 0.25, r * 0.05, cx, cy, r);
                    _cachedGlossGradient.addColorStopRGBA(0, 1, 1, 1, 0.15);
                    _cachedGlossGradient.addColorStopRGBA(0.4, 1, 1, 1, 0.0);
                    _cachedGlossGradient.addColorStopRGBA(1, 0, 0, 0, 0.22);
                    _cachedGlossR = r; _cachedGlossCx = cx; _cachedGlossCy = cy;
                }
                cr.setSource(_cachedGlossGradient);
                cr.arc(cx, cy, r, 0, 2 * Math.PI);
                cr.fill();
            } catch (e) { }
            cr.restore();
        }
        if (thumb.pixbuf && !thumb.isPlaceholder) {
            cr.save();
            const _bg = _bgColors ? _bgColors.bg : { r: 1, g: 1, b: 1 };
            const _pri = _bgColors ? _bgColors.pri : { r: 1, g: 1, b: 1 };
            cr.arc(cx, cy, 5, 0, 2 * Math.PI);
            cr.setSourceRGBA(_bg.r, _bg.g, _bg.b, 0.85);
            cr.fill();
            cr.arc(cx, cy, 2.5, 0, 2 * Math.PI);
            cr.setSourceRGBA(_pri.r, _pri.g, _pri.b, 0.85);
            cr.fill();
            cr.restore();
        }
        if (thumb.isPlaceholder) {
            try {
                const Pango = imports.gi.Pango;
                const PangoCairo = imports.gi.PangoCairo;
                if (!_cachedPangoFd) {
                    _cachedPangoFd = new Pango.FontDescription();
                    _cachedPangoFd.set_family('monospace');
                    _cachedPangoFd.set_absolute_size(128 * Pango.SCALE);
                }
                // Create layout once; re-bind to current cr context each frame
                // PangoCairo.update_layout() is far cheaper than create_layout()
                if (!_cachedPangoLayout) {
                    _cachedPangoLayout = PangoCairo.create_layout(cr);
                    _cachedPangoLayout.set_text(PLACEHOLDER_GLYPH, -1);
                    _cachedPangoLayout.set_font_description(_cachedPangoFd);
                } else {
                    PangoCairo.update_layout(cr, _cachedPangoLayout);
                }
                // Get actual glyph dimensions for proper centering
        	const [pw2, ph2] = _cachedPangoLayout.get_pixel_size();
        	cr.save();
        	const _pri = _bgColors ? _bgColors.pri : { r: 1, g: 1, b: 1 };
        	cr.setSourceRGBA(_pri.r, _pri.g, _pri.b, 0.75);
        	// Center based on actual glyph size, not container size
        	cr.moveTo(cx - pw2 / 2, cy - ph2 / 2);
        	PangoCairo.show_layout(cr, _cachedPangoLayout);
        	cr.restore();
            } catch (e) { }
        }
    });

    function thumbStartRotation() {
        if (thumb.timerId) return;
        thumb.playing = true;
        // PRIORITY_LOW + 50ms (20fps): rotation is cosmetically smooth at this
        // speed (0.10 deg/frame ≈ 2°/s) and no longer starves cava at DEFAULT.
        thumb.timerId = GLib.timeout_add(GLib.PRIORITY_LOW, 50, () => {
            if (!thumb.playing) { thumb.timerId = 0; return GLib.SOURCE_REMOVE; }
            thumb.angle = (thumb.angle + thumb.speed) % 360;
            thumbDa.queue_draw();
            return GLib.SOURCE_CONTINUE;
        });
    }
    function thumbStopRotation() { thumb.playing = false; }
    function thumbSetPixbuf(pixbuf, isPlaceholder) {
        thumb.pixbuf = pixbuf;
        thumb.isPlaceholder = isPlaceholder;
        thumbDa.queue_draw();
    }

    // ── Progress bar ───────────────────────────────────────────────────────
    const progress = new Gtk.ProgressBar({ show_text: true });
    progress.set_fraction(0.0);
    progress.set_text('--:-- / --:--');
    progress.set_hexpand(true);
    progress.add_css_class('media-progress-bar');

    // ── Buttons ────────────────────────────────────────────────────────────
    function makeGlyphLabel(glyph) {
        const lbl = new Gtk.Label({ halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER, use_markup: true });
        lbl.set_markup(`<span size="15872">${glyph}</span>`);
        return lbl;
    }

    const loopBtn = new Gtk.Button();
    loopBtn.set_child(makeGlyphLabel('󰑗'));
    loopBtn.set_tooltip_text(loopLabels[0]);

    const shuffleBtn = new Gtk.Button();
    shuffleBtn.set_child(makeGlyphLabel('󰒞'));
    shuffleBtn.set_tooltip_text('Shuffle Off');
    shuffleBtn._shuffleOn = false;
    shuffleBtn._setShuffleState = function (on) {
        if (on === this._shuffleOn) return;
        this._shuffleOn = on;
        this.set_child(makeGlyphLabel(on ? '󰒝' : '󰒞'));
        this.set_tooltip_text(on ? 'Shuffling' : 'Shuffle Off');
        if (on) this.add_css_class('shuffle-active');
        else this.remove_css_class('shuffle-active');
    };

    const prevBtn = Gtk.Button.new_from_icon_name('media-skip-backward-symbolic');
    prevBtn.set_tooltip_text('Previous');
    const playBtn = Gtk.Button.new_from_icon_name('media-playback-start-symbolic');
    playBtn.set_tooltip_text('Play/Pause');
    const nextBtn = Gtk.Button.new_from_icon_name('media-skip-forward-symbolic');
    nextBtn.set_tooltip_text('Next');

    const controls = new Gtk.Box({
        orientation: Gtk.Orientation.HORIZONTAL, spacing: 8,
        halign: Gtk.Align.CENTER, margin_start: 16,
    });
    controls.add_css_class('media-controls-center');
    [shuffleBtn, prevBtn, playBtn, nextBtn, loopBtn].forEach(b => controls.append(b));

    const leftColumn = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, spacing: 8,
        hexpand: true, vexpand: true,
        halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
    });
    leftColumn.append(artistLabel);
    leftColumn.append(titleLabel);
    leftColumn.append(progress);
    leftColumn.append(controls);

    const mediaInfoContainer = new Gtk.Box({
        orientation: Gtk.Orientation.HORIZONTAL, spacing: 8,
        hexpand: true, vexpand: true,
        halign: Gtk.Align.FILL, valign: Gtk.Align.CENTER,
    });
    mediaInfoContainer.add_css_class('media-info-container');
    mediaInfoContainer.append(leftColumn);
    // cavaRingDa is the base child (sets the container footprint to CAVA_RING_SIZE).
    // thumbDa is centered on top as an overlay. No set_clip_children needed —
    // bars are drawn within cavaRingDa's own allocation.
    const thumbOverlay = new Gtk.Overlay();
    thumbOverlay.set_valign(Gtk.Align.CENTER);
    thumbOverlay.set_halign(Gtk.Align.CENTER);
    thumbOverlay.set_child(cavaRingDa);
    thumbOverlay.add_overlay(thumbDa);
    mediaInfoContainer.append(thumbOverlay);

    const infoBox = new Gtk.Box({
        orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        hexpand: true, vexpand: true,
        halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
        margin_top: 8, margin_bottom: 8,
    });
    infoBox.add_css_class('media-info-center');
    infoBox.append(mediaInfoContainer);

    const playerFrame = new Gtk.Overlay({
        halign: Gtk.Align.CENTER, valign: Gtk.Align.CENTER,
        hexpand: false, vexpand: false,
    });
    playerFrame.set_size_request(500, 140);
    playerFrame.add_css_class('media-player-frame');
    playerFrame.set_child(bgDrawingArea);
    playerFrame.add_overlay(infoBox);
    playerFrame.set_measure_overlay(infoBox, true);

    // ── Assemble: [sourcesBar] [playerFrame] [volumeScale] ────────────────
    mediaPlayerBox.append(sourcesBar);
    mediaPlayerBox.append(playerFrame);
    mediaPlayerBox.append(volumeScale);

    // ── Runtime state ──────────────────────────────────────────────────────
    let player = null;
    let busName = null;
    let lastArtUrl = null;
    let isSeeking = false;
    let seekTarget = 0;
    // Position freeze: used by seek logic to hold display position after a seek
    // until the player confirms the new position.
    let frozenPosition = 0;
    let isPositionFrozen = false;

    // ── Multi-source tracking ──────────────────────────────────────────────
    // allPlayers: [{bus, shortName, proxy, status}] for all detected MPRIS sources.
    // userSelectedBus: bus the user manually picked — null = auto-select.
    // proxyCache: reuse existing proxies to avoid recreating on every poll.
    let allPlayers = [];
    let userSelectedBus = null;
    let lastPlayerListKey = '__unset__';  // sentinel — forces _buildSourceDots on first poll
    const proxyCache = {};   // busName → proxy

    const session = new Soup.Session();
    session.set_timeout(8);

    // ── Art loading ────────────────────────────────────────────────────────
    // Rules:
    //  1. artUrl unchanged → skip (no re-decode, no re-draw)
    //  2. artUrl empty/missing AND mediaUrl is a video → extract first frame via ffmpeg
    //  3. artUrl empty/missing, not a video (or ffmpeg unavailable) → placeholder glyph
    //  4. artUrl = local file:// image → GdkPixbuf from file
    //  5. artUrl = local file:// video → extract first frame via ffmpeg, else glyph
    //  6. artUrl = http(s):// → Soup async download → GdkPixbuf
    // No periodic video refresh — one static first-frame thumbnail per track.
    const VIDEO_EXTS = ['.mkv', '.mp4', '.avi', '.webm', '.mov', '.flv', '.wmv', '.m4v', '.ts'];

    function applyArt(artUrl, playbackState, mediaUrl = '') {
        const isPlaying = playbackState === 'Playing';

        // Guard: skip if nothing changed (rotation state may still need updating)
        if (artUrl === lastArtUrl) {
            if (isPlaying) thumbStartRotation(); else thumbStopRotation();
            return;
        }
        lastArtUrl = artUrl;

        // ── No art ───────────────────────────────────────────────────────
        if (!artUrl || artUrl.length === 0) {
            // Check if the real media file (xesam:url) is a video — if so try ffmpeg
            const lMedia = (mediaUrl || '').toLowerCase().replace('file://', '');
            const mediaIsVideo = VIDEO_EXTS.some(ext => lMedia.endsWith(ext));
            if (mediaIsVideo && mediaUrl) {
                const normUri = mediaUrl.startsWith('file://') ? mediaUrl : `file://${mediaUrl}`;
                const pb = extractVideoThumbnail(normUri);
                thumbSetPixbuf(pb || null, !pb);
            } else {
                thumbSetPixbuf(null, true);
            }
            if (isPlaying) thumbStartRotation(); else thumbStopRotation();
            return;
        }

        // ── Local file ───────────────────────────────────────────────────
        if (artUrl.startsWith('file://') || artUrl.startsWith('/')) {
            const path = artUrl.replace('file://', '');
            const lp = path.toLowerCase();
            const normUri = artUrl.startsWith('/') ? `file://${artUrl}` : artUrl;

            if (VIDEO_EXTS.some(ext => lp.endsWith(ext))) {
                // artUrl is the video file itself — extract first frame
                const pb = extractVideoThumbnail(normUri);
                thumbSetPixbuf(pb || null, !pb);
            } else {
                // Static image (album art, embedded thumbnail, etc.)
                try {
                    const pb = GdkPixbuf.Pixbuf.new_from_file(path);
                    thumbSetPixbuf(pb, false);
                } catch (e) { thumbSetPixbuf(null, true); }
            }
            if (isPlaying) thumbStartRotation(); else thumbStopRotation();
            return;
        }

        // ── Remote URL ───────────────────────────────────────────────────
        if (artUrl.startsWith('http://') || artUrl.startsWith('https://')) {
            thumbSetPixbuf(null, true);
            if (isPlaying) thumbStartRotation(); else thumbStopRotation();
            const msg = Soup.Message.new('GET', artUrl);
            session.send_and_read_async(msg, GLib.PRIORITY_LOW, null, (sess, sres) => {
                if (artUrl !== lastArtUrl) return;
                try {
                    const bytes = sess.send_and_read_finish(sres);
                    const stream = Gio.MemoryInputStream.new_from_bytes(bytes);
                    const pb = GdkPixbuf.Pixbuf.new_from_stream(stream, null);
                    stream.close(null);
                    if (artUrl === lastArtUrl) thumbSetPixbuf(pb, false);
                } catch (e) { }
            });
            return;
        }

        // Fallback for unrecognised schemes
        thumbSetPixbuf(null, true);
        if (isPlaying) thumbStartRotation(); else thumbStopRotation();
    }

    // ── Source sidebar helpers ─────────────────────────────────────────────
    // Short display name from bus string: strip prefix and common suffixes.
    function _sourceName(bus) {
        let name = bus.replace(BUS_NAME_PREFIX, '');
        // Strip instance suffixes like .instance12345 or trailing dots
        name = name.replace(/\.\d+$/, '').replace(/\.$/, '');
        // Capitalise first char
        return name.charAt(0).toUpperCase() + name.slice(1);
    }

    // Rebuild sidebar buttons from scratch when the player list changes.
    function _buildSourceDots() {
        let child;
        while ((child = sourcesBar.get_first_child())) sourcesBar.remove(child);

        if (allPlayers.length === 0) {
            // No sources detected — show a static no-media indicator so the
            // sidebar keeps its width and doesn't collapse/shift the layout.
            const lbl = new Gtk.Label({ label: SRC_NO_MEDIA, halign: Gtk.Align.CENTER });
            const btn = new Gtk.Button();
            btn.set_child(lbl);
            btn.set_tooltip_text('No media');
            btn.add_css_class('media-source-btn');
            btn.add_css_class('source-no-media');
            btn.set_sensitive(false);
            sourcesBar.append(btn);
            return;
        }

        for (const p of allPlayers) {
            const isActive = p.bus === busName;
            const isPlaying = p.status === 'Playing';
            const glyph = isPlaying ? SRC_PLAYING : (p.status === 'Paused' ? SRC_PAUSED : SRC_STOPPED);

            const btn = new Gtk.Button();
            // Tiny label — just the glyph
            const lbl = new Gtk.Label({ label: glyph, halign: Gtk.Align.CENTER });
            btn.set_child(lbl);
            btn.set_tooltip_text(`${p.shortName}${isPlaying ? ' 󰐊' : p.status === 'Paused' ? ' 󰏤' : ''}`);
            btn.add_css_class('media-source-btn');
            if (isActive)  btn.add_css_class('source-active');
            if (isPlaying) btn.add_css_class('source-playing');

            btn._srcBus = p.bus;
            btn.connect('clicked', () => {
                userSelectedBus = btn._srcBus;
                _switchToSource(btn._srcBus);
            });
            sourcesBar.append(btn);
        }
    }

    // Only update glyph + classes on existing buttons (no teardown/rebuild).
    function _updateSourceDotStyles() {
        let btn = sourcesBar.get_first_child();
        for (const p of allPlayers) {
            if (!btn) break;
            const isActive  = p.bus === busName;
            const isPlaying = p.status === 'Playing';
            const glyph = isPlaying ? SRC_PLAYING : (p.status === 'Paused' ? SRC_PAUSED : SRC_STOPPED);
            const lbl = btn.get_child();
            if (lbl) lbl.set_label(glyph);
            btn.set_tooltip_text(`${p.shortName}${isPlaying ? ' 󰐊' : p.status === 'Paused' ? ' 󰏤' : ''}`);
            if (isActive)  btn.add_css_class('source-active');
            else           btn.remove_css_class('source-active');
            if (isPlaying) btn.add_css_class('source-playing');
            else           btn.remove_css_class('source-playing');
            btn = btn.get_next_sibling();
        }
    }

    // Switch the active player to a specific bus.
    function _switchToSource(targetBus) {
        const found = allPlayers.find(p => p.bus === targetBus);
        if (!found) return;
        if (targetBus === busName) return;
        busName = targetBus;
        player = found.proxy;
        lastArtUrl = null;  // force art reload for new source
        _updateSourceDotStyles();
        updateTrackInfoAsync();
    }

    // Scroll on the sources bar or main widget cycles through sources.
    const _srcScrollCtrl = new Gtk.EventControllerScroll();
    _srcScrollCtrl.set_flags(Gtk.EventControllerScrollFlags.VERTICAL);
    _srcScrollCtrl.connect('scroll', (_ctrl, _dx, dy) => {
        if (allPlayers.length < 2) return Gdk.EVENT_PROPAGATE;
        const idx = allPlayers.findIndex(p => p.bus === busName);
        const next = dy > 0
            ? (idx + 1) % allPlayers.length
            : (idx - 1 + allPlayers.length) % allPlayers.length;
        userSelectedBus = allPlayers[next].bus;
        _switchToSource(userSelectedBus);
        return Gdk.EVENT_STOP;
    });
    sourcesBar.add_controller(_srcScrollCtrl);

    // ── MPRIS player enumeration + auto-select ─────────────────────────────
    function updatePlayerAsync(callback) {
        getMprisPlayersAsync(buses => {
            // Track list change to know when to rebuild dots vs just re-style them
            const listKey = buses.slice().sort().join(',');
            const listChanged = listKey !== lastPlayerListKey;
            lastPlayerListKey = listKey;

            // Build allPlayers — reuse cached proxies
            const newPlayers = [];
            for (const bus of buses) {
                if (!proxyCache[bus]) {
                    try { proxyCache[bus] = createMprisProxy(bus); }
                    catch (e) { proxyCache[bus] = null; }
                }
                const proxy = proxyCache[bus];
                let status = 'Stopped';
                if (proxy) {
                    try {
                        const sv = proxy.get_cached_property('PlaybackStatus');
                        status = sv ? sv.deep_unpack() : 'Stopped';
                    } catch (e) { }
                }
                newPlayers.push({ bus, shortName: _sourceName(bus), proxy, status });
            }
            // Clean up proxies for buses that have gone away
            for (const b of Object.keys(proxyCache)) {
                if (!buses.includes(b)) delete proxyCache[b];
            }
            allPlayers = newPlayers;

            // ── Auto-select logic ──────────────────────────────────────────
            // Clear userSelectedBus only if that source has completely disappeared
            if (userSelectedBus && !allPlayers.find(p => p.bus === userSelectedBus)) userSelectedBus = null;

            const currentEntry = allPlayers.find(p => p.bus === busName);
            const userEntry    = userSelectedBus ? allPlayers.find(p => p.bus === userSelectedBus) : null;

            let targetBus = null;

            if (userEntry) {
                // User explicitly chose a source → always respect it, regardless of
                // whether another source is playing. Auto-select only runs when no
                // explicit selection has been made (userSelectedBus === null).
                targetBus = userSelectedBus;
            } else {
                // Auto-select: prefer currently-playing, then any playing, then first
                const anyPlaying = allPlayers.find(p => p.status === 'Playing');
                if (currentEntry && currentEntry.status === 'Playing') {
                    targetBus = busName;        // keep current — it's playing
                } else if (anyPlaying) {
                    targetBus = anyPlaying.bus; // something else started playing
                } else if (allPlayers.length > 0) {
                    targetBus = allPlayers[0].bus;
                }
            }

            if (targetBus && targetBus !== busName) {
                const entry = allPlayers.find(p => p.bus === targetBus);
                busName = targetBus;
                player = entry ? entry.proxy : null;
                lastArtUrl = null;   // force art reload on source change
            } else if (!targetBus) {
                busName = null;
                player = null;
            }

            // Rebuild dots only when the list actually changed; otherwise just restyle
            if (listChanged) _buildSourceDots();
            else             _updateSourceDotStyles();

            if (callback) callback();
        });
    }

    // ── Volume read/write helpers ──────────────────────────────────────────
    // _readVolumeAsync: non-blocking. Serves from cache when fresh; otherwise
    // spawns wpctl asynchronously so the main loop is never stalled.
    // _writeVolumeWpctl: already async via spawn_command_line_async, unchanged.
    let _volumeChanging = false;
    let _volCache = { value: 1.0, ts: 0 };
    const VOL_CACHE_TTL_MS = 2000;

    function _readVolumeAsync(done) {
        const now = GLib.get_monotonic_time() / 1000;   // µs → ms
        if (now - _volCache.ts < VOL_CACHE_TTL_MS) {
            // Cache still fresh — apply immediately without spawning a process.
            _volumeChanging = true;
            _volAdj.set_value(_volCache.value);
            _volumeChanging = false;
            if (done) done();
            return;
        }
        try {
            const proc = Gio.Subprocess.new(
                ['wpctl', 'get-volume', '@DEFAULT_AUDIO_SINK@'],
                Gio.SubprocessFlags.STDOUT_PIPE | Gio.SubprocessFlags.STDERR_SILENCE
            );
            proc.communicate_utf8_async(null, null, (p, res) => {
                const ts = GLib.get_monotonic_time() / 1000;
                try {
                    const [, stdout] = p.communicate_utf8_finish(res);
                    // Output: "Volume: 0.75" or "Volume: 0.75 [MUTED]"
                    const m = (stdout || '').match(/Volume:\s*([\d.]+)/);
                    const vol = m ? Math.max(0, Math.min(1, parseFloat(m[1]))) : _volCache.value;
                    _volCache = { value: vol, ts };
                    _volumeChanging = true;
                    _volAdj.set_value(vol);
                    _volumeChanging = false;
                } catch (e) {
                    // Keep stale value; bump ts to avoid a tight retry loop
                    _volCache = { value: _volCache.value, ts };
                }
                if (done) done();
            });
        } catch (e) {
            if (done) done();
        }
    }

    function _writeVolumeWpctl(val) {
        // Optimistic cache update so the slider doesn't snap back on next read
        _volCache = { value: val, ts: GLib.get_monotonic_time() / 1000 };
        try {
            GLib.spawn_command_line_async(`wpctl set-volume @DEFAULT_AUDIO_SINK@ ${val.toFixed(3)}`);
        } catch (e) { }
    }

    _volAdj.connect('value-changed', () => {
        if (_volumeChanging) return;  // programmatic update — don't write back
        _writeVolumeWpctl(_volAdj.get_value());
    });

    // ── Track info update (metadata only — position handled by _doPositionPoll) ──
    function updateTrackInfoAsync() {
        if (!player) {
            _isPlaying = false;
            _trackLength = 0;
            _restartBgTimer(BG_MS_IDLE);
            getActivePipeWireSinkInfo(sinkInfo => {
                titleLabel.set_label(sinkInfo
                    ? ('Audio playing' + (sinkInfo.appName ? ` — ${sinkInfo.appName}` : ''))
                    : 'No Media');
            });
            artistLabel.set_label('');
            if (!isSeeking) { progress.set_fraction(0.0); progress.set_text('--:-- / --:--'); }
            [shuffleBtn, prevBtn, playBtn, nextBtn, loopBtn].forEach(b => b.set_sensitive(false));
            thumbStopRotation();
            if (lastArtUrl !== '') { lastArtUrl = ''; thumbSetPixbuf(null, true); }
            return;
        }
        [shuffleBtn, prevBtn, playBtn, nextBtn, loopBtn].forEach(b => b.set_sensitive(true));

        Gio.DBus.session.call(
            busName, '/org/mpris/MediaPlayer2',
            'org.freedesktop.DBus.Properties', 'Get',
            GLib.Variant.new_tuple([
                GLib.Variant.new_string('org.mpris.MediaPlayer2.Player'),
                GLib.Variant.new_string('Metadata'),
            ]),
            null, Gio.DBusCallFlags.NONE, -1, null,
            (source, res) => {
                try {
                    const metaResult = source.call_finish(res);
                    const metadata = metaResult.deep_unpack()[0].deep_unpack();
                    const title = metadata['xesam:title'] ? metadata['xesam:title'].deep_unpack() : 'Unknown Title';
                    const artistArr = metadata['xesam:artist'] ? metadata['xesam:artist'].deep_unpack() : [];
                    const artist = artistArr.length > 0 ? artistArr[0] : '';
                    const artUrl = metadata['mpris:artUrl'] ? metadata['mpris:artUrl'].deep_unpack() : '';
                    const mediaUrl = metadata['xesam:url'] ? metadata['xesam:url'].deep_unpack() : '';
                    const length = metadata['mpris:length'] ? metadata['mpris:length'].deep_unpack() : 0;

                    // Store track length for position interpolation
                    _trackLength = length;

                    // PlaybackStatus from cache (no extra D-Bus call)
                    let playbackState = 'Stopped';
                    try {
                        const sv = player.get_cached_property('PlaybackStatus');
                        playbackState = sv ? sv.deep_unpack() : 'Stopped';
                    } catch (e) { }
                    _isPlaying = playbackState === 'Playing';

                    titleLabel.set_label(title);
                    artistLabel.set_label(artist);

                    if (_isPlaying) {
                        playBtn.set_icon_name('media-playback-pause-symbolic');
                        progress.remove_css_class('paused');
                    } else {
                        playBtn.set_icon_name('media-playback-start-symbolic');
                        progress.add_css_class('paused');
                    }

                    applyArt(artUrl, playbackState, mediaUrl);
                    _readVolumeAsync();

                    // Shuffle
                    try {
                        const sv = player.get_cached_property('Shuffle');
                        shuffleBtn._setShuffleState(sv ? sv.deep_unpack() : false);
                    } catch (e) { }

                    // Loop (only re-render when mode changed)
                    try {
                        const lv = player.get_cached_property('LoopStatus');
                        loopMode = Math.max(0, loopModes.indexOf(lv ? lv.deep_unpack() : 'None'));
                    } catch (e) { }
                    if (loopMode !== lastRenderedLoopMode) {
                        lastRenderedLoopMode = loopMode;
                        loopBtn.remove_css_class('loop-none');
                        loopBtn.remove_css_class('loop-track');
                        loopBtn.remove_css_class('loop-playlist');
                        loopBtn.add_css_class(`loop-${loopModes[loopMode].toLowerCase()}`);
                        loopBtn.set_tooltip_text(loopLabels[loopMode]);
                        loopBtn.set_child(makeGlyphLabel(
                            loopMode === 1 ? '󰑘' : loopMode === 2 ? '󰑖' : '󰑗'
                        ));
                    }
                } catch (e) {
                    titleLabel.set_label('No Media');
                    artistLabel.set_label('');
                    if (!isSeeking) { progress.set_fraction(0.0); progress.set_text('--:-- / --:--'); }
                }
            }
        );
    }

    // ── Button handlers ────────────────────────────────────────────────────
    function dbusSend(method, params) {
        if (!player || !busName) return;
        Gio.DBus.session.call(busName, '/org/mpris/MediaPlayer2',
            'org.mpris.MediaPlayer2.Player', method,
            params, null, Gio.DBusCallFlags.NONE, -1, null, null);
    }
    function dbusSet(prop, variant) {
        if (!busName) return;
        Gio.DBus.session.call(busName, '/org/mpris/MediaPlayer2',
            'org.freedesktop.DBus.Properties', 'Set',
            GLib.Variant.new_tuple([
                GLib.Variant.new_string('org.mpris.MediaPlayer2.Player'),
                GLib.Variant.new_string(prop),
                GLib.Variant.new_variant(variant),
            ]),
            null, Gio.DBusCallFlags.NONE, -1, null, null);
    }

    playBtn.connect('clicked', () => {
        if (!player || !busName) return;
        let state = 'Stopped';
        try { const sv = player.get_cached_property('PlaybackStatus'); state = sv ? sv.deep_unpack() : 'Stopped'; } catch (e) { }
        dbusSend(state === 'Playing' ? 'Pause' : 'Play', null);
    });
    nextBtn.connect('clicked', () => dbusSend('Next', null));
    prevBtn.connect('clicked', () => dbusSend('Previous', null));

    loopBtn.connect('clicked', () => {
        if (!player || !busName) return;
        try { const lv = player.get_cached_property('LoopStatus'); loopMode = Math.max(0, loopModes.indexOf(lv ? lv.deep_unpack() : 'None')); } catch (e) { }
        const newMode = (loopMode + 1) % 3;
        Gio.DBus.session.call(busName, '/org/mpris/MediaPlayer2',
            'org.mpris.MediaPlayer2.Player', 'SetLoopStatus',
            GLib.Variant.new_tuple([GLib.Variant.new_string(loopModes[newMode])]),
            null, Gio.DBusCallFlags.NONE, -1, null,
            (src, res) => {
                try { src.call_finish(res); loopMode = newMode; }
                catch (e) { dbusSet('LoopStatus', GLib.Variant.new_string(loopModes[newMode])); loopMode = newMode; }
            });
    });

    shuffleBtn.connect('clicked', () => {
        if (!player || !busName) return;
        let son = false;
        try { const sv = player.get_cached_property('Shuffle'); son = sv ? sv.deep_unpack() : false; } catch (e) { }
        son = !son;
        Gio.DBus.session.call(busName, '/org/mpris/MediaPlayer2',
            'org.mpris.MediaPlayer2.Player', 'SetShuffle',
            GLib.Variant.new_tuple([GLib.Variant.new_boolean(son)]),
            null, Gio.DBusCallFlags.NONE, -1, null,
            (src, res) => {
                try { src.call_finish(res); }
                catch (e) { dbusSet('Shuffle', GLib.Variant.new_boolean(son)); }
            });
    });

    // ── Seek gestures (smooth) ─────────────────────────────────────────────
    // Bug fix: GestureDrag.drag-update gives (offset_x, offset_y) from the
    // drag START point, not an absolute coordinate. The original code passed
    // offset_x directly to getPointerFraction() as if it were absolute, which
    // caused the progress bar to jump to the wrong position on drag.
    // Fix: track the absolute x at press time (_seekPressX) and add the
    // running offset to it on every drag-update tick.
    function getPointerFraction(widget, x) {
        return Math.max(0, Math.min(1, x / widget.get_allocation().width));
    }

    let _seekPressX = 0;
    const gesture = new Gtk.GestureClick();
    const dragGesture = new Gtk.GestureDrag();

    gesture.connect('pressed', (_g, _n, x) => {
        if (!player) return;
        _seekPressX = x;
        isSeeking = true;
        progress.set_fraction(getPointerFraction(progress, x));
        progress.add_css_class('seeking');
    });

    // drag-update: x here is offset from start — add _seekPressX for absolute pos
    dragGesture.connect('drag-update', (_g, dx) => {
        if (!player || !isSeeking) return;
        progress.set_fraction(getPointerFraction(progress, _seekPressX + dx));
    });

    gesture.connect('released', (_g, _n, x) => {
        if (!player || !isSeeking) return;
        isSeeking = false;
        seekTarget = getPointerFraction(progress, x);
        const mv = player.get_cached_property('Metadata');
        const md = mv ? mv.deep_unpack() : {};
        const len = md['mpris:length'] ? md['mpris:length'].deep_unpack() : 0;
        if (len <= 0) { progress.remove_css_class('seeking'); return; }
        const newPos = Math.floor(len * seekTarget);

        const afterSeek = () => GLib.timeout_add(GLib.PRIORITY_DEFAULT, 100, () => {
            isSeeking = false;
            progress.remove_css_class('seeking');
            try {
                const sv = player.get_cached_property('PlaybackStatus');
                if ((sv ? sv.deep_unpack() : 'Stopped') !== 'Playing') frozenPosition = newPos;
            } catch (e) { frozenPosition = newPos; }
            return GLib.SOURCE_REMOVE;
        });

        Gio.DBus.session.call(busName, '/org/mpris/MediaPlayer2',
            'org.mpris.MediaPlayer2.Player', 'SetPosition',
            GLib.Variant.new_tuple([
                GLib.Variant.new_object_path('/org/mpris/MediaPlayer2/TrackList/0'),
                GLib.Variant.new_int64(newPos),
            ]),
            null, Gio.DBusCallFlags.NONE, -1, null,
            (src, res) => {
                try { src.call_finish(res); afterSeek(); } catch (e) {
                    const pv = player.get_cached_property('Position');
                    const cur = pv ? pv.deep_unpack() : 0;
                    Gio.DBus.session.call(busName, '/org/mpris/MediaPlayer2',
                        'org.mpris.MediaPlayer2.Player', 'Seek',
                        GLib.Variant.new_tuple([GLib.Variant.new_int64(newPos - cur)]),
                        null, Gio.DBusCallFlags.NONE, -1, null,
                        (s2, r2) => {
                            try { s2.call_finish(r2); afterSeek(); }
                            catch (e2) { isSeeking = false; progress.remove_css_class('seeking'); }
                        });
                }
            });
    });

    progress.add_controller(gesture);
    progress.add_controller(dragGesture);

    // ── Timer lifecycle ────────────────────────────────────────────────────
    // Three-tier polling to minimise D-Bus traffic:
    //   _bgTimerId    — Cairo animation, adaptive fps (playing→8fps, paused→2fps)
    //   _posPollTimer — Position + PlaybackStatus only, every 1 s
    //   _metaPollTimer— Full metadata + player list, every 4 s
    //
    // Local position interpolation: between position polls we advance the
    // display position using wall-clock time so the progress bar stays smooth
    // at zero additional D-Bus cost.
    let _bgTimerId    = 0;
    let _posPollTimer = 0;
    let _metaPollTimer = 0;

    // Interpolation state — updated by _doPositionPoll()
    let _posBase      = 0;   // last known position in µs
    let _posBaseTime  = 0;   // GLib.get_monotonic_time() when _posBase was set
    let _trackLength  = 0;   // track length in µs (updated on metadata fetch)
    let _isPlaying    = false;

    // Adaptive bg fps — full speed when playing, slow when paused/stopped
    const BG_FPS_PLAY  = 8;
    const BG_FPS_IDLE  = 2;
    const BG_MS_PLAY   = Math.round(1000 / BG_FPS_PLAY);   // 125ms
    const BG_MS_IDLE   = Math.round(1000 / BG_FPS_IDLE);   // 500ms
    let   _bgInterval  = BG_MS_PLAY;   // current interval, checked on each restart

    function _restartBgTimer(wantMs) {
        if (_bgTimerId && _bgInterval === wantMs) return;  // already correct, no-op
        if (_bgTimerId) { GLib.source_remove(_bgTimerId); _bgTimerId = 0; }
        _bgInterval = wantMs;
        _bgTimerId = GLib.timeout_add(GLib.PRIORITY_LOW, wantMs, () => {
            phase += PHASE_STEP;
            bgDrawingArea.queue_draw();
            return GLib.SOURCE_CONTINUE;
        });
    }

    // Dedicated GC + color-refresh timer — fixed 2s regardless of animation fps.
    // Decoupled from bg fps so it fires reliably even when bg is at 2fps idle.
    let _gcTimerId = 0;
    function _startGcTimer() {
        if (_gcTimerId) return;
        _gcTimerId = GLib.timeout_add(GLib.PRIORITY_LOW, 2000, () => {
            _resolveBgColors(mediaPlayerBox);
            imports.system.gc();
            return GLib.SOURCE_CONTINUE;
        });
    }
    function _stopGcTimer() {
        if (_gcTimerId) { GLib.source_remove(_gcTimerId); _gcTimerId = 0; }
    }

    // Compute interpolated display position without a D-Bus call
    function _interpolatedPosition() {
        if (!_isPlaying || _posBaseTime === 0) return _posBase;
        const elapsed = GLib.get_monotonic_time() - _posBaseTime;   // µs
        return Math.min(_posBase + elapsed, _trackLength > 0 ? _trackLength : _posBase + elapsed);
    }

    // Fast poll: fetch Position + PlaybackStatus, update progress bar
    function _doPositionPoll() {
        if (!player || !busName) return;
        Gio.DBus.session.call(
            busName, '/org/mpris/MediaPlayer2',
            'org.freedesktop.DBus.Properties', 'Get',
            GLib.Variant.new_tuple([
                GLib.Variant.new_string('org.mpris.MediaPlayer2.Player'),
                GLib.Variant.new_string('Position'),
            ]),
            null, Gio.DBusCallFlags.NONE, -1, null,
            (src, res) => {
                let position = 0;
                try { position = src.call_finish(res).deep_unpack()[0].deep_unpack(); } catch (e) { return; }

                let state = 'Stopped';
                try {
                    const sv = player.get_cached_property('PlaybackStatus');
                    state = sv ? sv.deep_unpack() : 'Stopped';
                } catch (e) { }

                const wasPlaying = _isPlaying;
                _isPlaying = state === 'Playing';
                _posBase = position;
                _posBaseTime = GLib.get_monotonic_time();

                // Adapt bg animation speed
                _restartBgTimer(_isPlaying ? BG_MS_PLAY : BG_MS_IDLE);

                // Update play button icon if state changed
                if (_isPlaying !== wasPlaying) {
                    if (_isPlaying) {
                        playBtn.set_icon_name('media-playback-pause-symbolic');
                        progress.remove_css_class('paused');
                        thumbStartRotation();
                    } else {
                        playBtn.set_icon_name('media-playback-start-symbolic');
                        progress.add_css_class('paused');
                        thumbStopRotation();
                    }
                }

                // Progress bar (skip if user is seeking)
                if (!isSeeking && _trackLength > 0) {
                    const dp = isPositionFrozen && !_isPlaying ? frozenPosition : position;
                    progress.set_fraction(dp / _trackLength);
                    const ps = Math.floor(dp / 1e6), ls = Math.floor(_trackLength / 1e6);
                    progress.set_text(
                        `${Math.floor(ps / 60)}:${('0' + (ps % 60)).slice(-2)} / ${Math.floor(ls / 60)}:${('0' + (ls % 60)).slice(-2)}`
                    );
                }
            }
        );
    }

    function _startTimers() {
        _resolveBgColors(mediaPlayerBox);
        _startCava();

        // Bg animation — starts at idle speed, _doPositionPoll will switch it
        if (_bgTimerId === 0) _restartBgTimer(BG_MS_IDLE);

        // GC + color refresh — fixed 2s, independent of animation fps
        _startGcTimer();

        // Position poll: 1 s
        if (_posPollTimer === 0) {
            _doPositionPoll();
            _posPollTimer = GLib.timeout_add(GLib.PRIORITY_LOW, 1000, () => {
                _doPositionPoll();
                return GLib.SOURCE_CONTINUE;
            });
        }

        // Metadata + player list: 4 s (also fires immediately for first load)
        if (_metaPollTimer === 0) {
            updatePlayerAsync(() => updateTrackInfoAsync());
            _metaPollTimer = GLib.timeout_add(GLib.PRIORITY_LOW, 4000, () => {
                updatePlayerAsync(() => updateTrackInfoAsync());
                return GLib.SOURCE_CONTINUE;
            });
        }
    }

    function _stopTimers() {
        if (_bgTimerId)    { GLib.source_remove(_bgTimerId);    _bgTimerId    = 0; }
        if (_posPollTimer) { GLib.source_remove(_posPollTimer); _posPollTimer = 0; }
        if (_metaPollTimer){ GLib.source_remove(_metaPollTimer);_metaPollTimer= 0; }
        _stopGcTimer();
        _stopCava();
        thumbStopRotation();
    }

    function _destroyTimers() {
        _stopTimers();
        _cavaClearRetry();
        if (thumb.timerId) { GLib.source_remove(thumb.timerId); thumb.timerId = 0; }
        if (_colorMonitor) { _colorMonitor.cancel(); _colorMonitor = null; }
        if (_colorDebounce) { GLib.source_remove(_colorDebounce); _colorDebounce = 0; }
        _cachedGlossGradient = null;
        _cachedPangoFd = null;
        _cachedPangoLayout = null;
        thumb.pixbuf = null;
        _stopCava();
    }

    mediaPlayerBox.connect('map',     () => _startTimers());
    mediaPlayerBox.connect('unmap',   () => _stopTimers());
    mediaPlayerBox.connect('destroy', () => _destroyTimers());

    updatePlayerAsync(() => updateTrackInfoAsync());

    return mediaPlayerBox;
}

var exports = { createMediaBox };
