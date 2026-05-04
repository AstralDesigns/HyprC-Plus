#!/usr/bin/env gjs

/**
 * Candy Daemon
 * - Media player applet
 * - Creates desktop entry and icons on first run
 * - CSS hot reload support
 */

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';
imports.gi.versions.GLib = '2.0';
imports.gi.versions.Gio = '2.0';
const { Gtk, Gdk, GLib, Gio } = imports.gi;

const SCRIPT_DIR = GLib.path_get_dirname(imports.system.programInvocationName);
const HOME = GLib.get_home_dir();

// Paths
const ICON_SOURCE  = GLib.build_filenamev([SCRIPT_DIR, 'HyprCandy.png']);
const ICON_DIR     = GLib.build_filenamev([HOME, '.local', 'share', 'icons', 'hicolor']);
const APP_DIR      = GLib.build_filenamev([HOME, '.local', 'share', 'applications']);
const DESKTOP_FILE = GLib.build_filenamev([APP_DIR, 'Candy.desktop']);
const DAEMON_NAME  = 'candy-daemon';
const TOGGLE_DIR   = GLib.build_filenamev([HOME, '.cache', 'hyprcandy', 'toggle']);

// Applet module
imports.searchPath.unshift(SCRIPT_DIR);
imports.searchPath.unshift(GLib.build_filenamev([SCRIPT_DIR, 'src']));

const Media      = imports['media'];
const CssWatcher = imports['css-watcher'];
const PidUtils   = imports['pid-utils'];

// State
let mediaApplet = null;
let cssWatcher  = null;

// ── GPU environment detection ────────────────────────────────────────────────
// Reads /sys/class/drm — instant, no process spawn, cached permanently.
// Returns env vars for dGPU routing, or null for iGPU/CPU-only systems.
let _gpuEnvDetected = undefined;
function _detectDgpuEnv() {
    if (_gpuEnvDetected !== undefined) return _gpuEnvDetected;
    let hasNvidia = false, hasAmd = false;
    try {
        const drm = Gio.File.new_for_path('/sys/class/drm');
        let en = null;
        try {
            en = drm.enumerate_children('standard::name', Gio.FileQueryInfoFlags.NONE, null);
            let fi;
            while ((fi = en.next_file(null)) !== null) {
                const name = fi.get_name();
                if (!name.match(/^card\d+$/)) continue;
                try {
                    const [, bytes] = Gio.File.new_for_path(
                        `/sys/class/drm/${name}/device/vendor`).load_contents(null);
                    const vendor = new TextDecoder().decode(bytes).trim();
                    if      (vendor === '0x10de') hasNvidia = true;
                    else if (vendor === '0x1002') hasAmd    = true;
                } catch (_) {}
            }
        } finally {
            if (en) try { en.close(null); } catch (_) {}
        }
    } catch (_) {}
    _gpuEnvDetected = hasNvidia ? { CUDA_VISIBLE_DEVICES: '0' }
                    : hasAmd    ? { DRI_PRIME: '1' }
                    : null;
    print('🎮 GPU env: ' + (_gpuEnvDetected ? JSON.stringify(_gpuEnvDetected) : '(iGPU/CPU default)'));
    return _gpuEnvDetected;
}

/**
 * Setup Candy desktop entry and icons (only if missing)
 */
function setupCandyDesktop() {
    if (GLib.file_test(DESKTOP_FILE, GLib.FileTest.EXISTS)) return;

    print('🔧 Setting up desktop entry and icons...');

    try {
        GLib.mkdir_with_parents(ICON_DIR, 0o755);
        GLib.mkdir_with_parents(APP_DIR,  0o755);
    } catch (e) {
        print('❌ Directory error: ' + e.message);
        return;
    }

    if (!GLib.file_test(ICON_SOURCE, GLib.FileTest.EXISTS)) {
        print('⚠️ HyprCandy.png not found, running icon setup...');
        try {
            const setupScript = GLib.build_filenamev([SCRIPT_DIR, 'setup-custom-icon.sh']);
            GLib.spawn_command_line_sync(`bash "${setupScript}"`);
        } catch(e) {
            print('⚠️ Icon setup failed: ' + e.message);
        }
        if (!GLib.file_test(ICON_SOURCE, GLib.FileTest.EXISTS)) {
            print('⚠️ Icon still not found, skipping icon generation');
            return;
        }
    }

    // Generate icons in hicolor structure under the HyprCandy name so the
    // theme lookup resolves Icon=HyprCandy without needing a flat file or path.
    const sizes = [16, 24, 32, 48, 64, 128, 256, 512];
    for (let size of sizes) {
        try {
            const sizeDir = GLib.build_filenamev([ICON_DIR, `${size}x${size}`, 'apps']);
            GLib.mkdir_with_parents(sizeDir, 0o755);
            GLib.spawn_command_line_sync(`magick "${ICON_SOURCE}" -resize ${size}x${size} "${sizeDir}/HyprCandy.png"`);
        } catch (e) {}
    }

    // Scalable icon — PNG copy is sufficient; dock themes accept .png in scalable
    try {
        const scalableDir = GLib.build_filenamev([ICON_DIR, 'scalable', 'apps']);
        GLib.mkdir_with_parents(scalableDir, 0o755);
        GLib.spawn_command_line_sync(`cp "${ICON_SOURCE}" "${scalableDir}/HyprCandy.png"`);
    } catch (e) {}

    // Update icon cache
    try {
        GLib.spawn_command_line_sync('gtk-update-icon-cache -f ~/.local/share/icons/hicolor 2>/dev/null || true');
        print('✅ Icon cache updated');
    } catch (e) {}

    // Desktop entry
    const launcherScript = GLib.build_filenamev([SCRIPT_DIR, 'candy-launcher.sh']);
    const content = `[Desktop Entry]
Version=1.0
Name=Candy Applet
Comment=Candy Media Player Applet
Exec=${launcherScript}
Icon=HyprCandy
Terminal=false
Type=Application
Categories=Utility;AudioVideo;
StartupNotify=false
StartupWMClass=candy-launcher
NoDisplay=true
`;
    GLib.file_set_contents(DESKTOP_FILE, content);
    GLib.spawn_command_line_async('update-desktop-database ~/.local/share/applications 2>/dev/null || true');
    print('✅ Setup complete');
}

/**
 * Toggle the media applet
 */
function toggleMedia() {
    if (!mediaApplet) {
        mediaApplet = new Gtk.ApplicationWindow({
            application: app,
            default_width: 520, default_height: 140,
            resizable: false, decorated: false,
            title: 'candy.media',
        });
        const surface = mediaApplet.get_surface();
        if (surface) surface.set_property('name', 'Candy');

        const box = Media.createMediaBox();
        mediaApplet.set_child ? mediaApplet.set_child(box) : mediaApplet.set_content(box);

        const kc = new Gtk.EventControllerKey();
        kc.connect('key-pressed', (c, k) => { if (k === Gdk.KEY_Escape) mediaApplet.hide(); return false; });
        mediaApplet.add_controller(kc);

        CssWatcher.registerWindow(mediaApplet);
        print('🎵 Media applet created');
    }
    mediaApplet.get_visible()
        ? mediaApplet.hide()
        : (mediaApplet.show(), mediaApplet.present());
}

// Sentinel file toggle scripts wait for before firing.
// Written AFTER the poll timer is registered, not at PID-write time.
const READY_FILE = GLib.build_filenamev([HOME, '.cache', 'hyprcandy', 'toggle', 'daemon-ready']);

/**
 * Setup file interface with polling
 */
function setupFileInterface() {
    try {
        GLib.mkdir_with_parents(TOGGLE_DIR, 0o755);
        print(`✅ File interface: ${TOGGLE_DIR}`);

        // Poll for toggle files every 200ms.
        // IMPORTANT: enumerator must be closed in a finally block — if next_file()
        // throws (race between shell writing and us reading), the open dir fd would
        // leak and eventually exhaust EMFILE.
        GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
            const dir = Gio.File.new_for_path(TOGGLE_DIR);
            let enumerator = null;
            try {
                enumerator = dir.enumerate_children(
                    'standard::name', Gio.FileQueryInfoFlags.NONE, null
                );
                // Snapshot all names first so we don't mutate while iterating
                const names = [];
                let info;
                while (true) {
                    try {
                        info = enumerator.next_file(null);
                    } catch(e) {
                        // next_file can throw if a file disappears between
                        // enumerate_children and next_file (zsh exits fast)
                        break;
                    }
                    if (info === null) break;
                    names.push(info.get_name());
                }

                for (const name of names) {
                    // Skip the ready sentinel — never process it as a command
                    if (name === 'daemon-ready') continue;

                    const gfile = Gio.File.new_for_path(
                        GLib.build_filenamev([TOGGLE_DIR, name])
                    );
                    // Delete first — prevents duplicate triggers if handler
                    // is slow and the next poll fires before it finishes
                    try { gfile.delete(null); } catch(e) {}

                    if (name === 'toggle-media') {
                        print('📁 Toggle media applet');
                        toggleMedia();
                    } else if (name === 'quit') {
                        app.quit();
                        return false;
                    }
                }
            } catch (e) {
                print('⚠️ Poll error: ' + e.message);
            } finally {
                // Always close the enumerator to release the dir fd
                if (enumerator) {
                    try { enumerator.close(null); } catch(e) {}
                }
            }
            return true;
        });

        // Write the ready sentinel AFTER the timer is registered.
        // Toggle scripts wait for this file instead of the PID file, which
        // exists before the event loop and file interface are live.
        try { GLib.file_set_contents(READY_FILE, 'ready'); } catch(e) {}
        print('✅ Daemon ready sentinel written');

    } catch (e) {
        print('⚠️ File interface: ' + e.message);
    }
}

/**
 * Main application
 */
let app;

function onActivate() {
    print('🍬 Candy Daemon ready');
    app.hold();

    cssWatcher = CssWatcher.createCSSWatcher();
    cssWatcher.start();

    setupFileInterface();

    // Auto-exit after 60 seconds with the applet hidden.
    // Timer resets on every toggle so the daemon stays alive while in use.
    let _autoExitId = null;
    function _resetAutoExit() {
        if (_autoExitId !== null) GLib.source_remove(_autoExitId);
        _autoExitId = GLib.timeout_add_seconds(GLib.PRIORITY_DEFAULT, 60, () => {
            if (!mediaApplet || !mediaApplet.get_visible()) {
                print('⏱ Auto-exit: 60 s idle with applet hidden — quitting');
                app.quit();
            } else {
                _resetAutoExit(); // still visible — check again in another 60 s
            }
            return false;
        });
    }

    const _origToggleMedia = toggleMedia;
    toggleMedia = function() { _resetAutoExit(); _origToggleMedia(); };

    _resetAutoExit();
}

function onShutdown() {
    print('🧹 Cleaning up...');
    try { Gio.File.new_for_path(READY_FILE).delete(null); } catch(e) {}
    if (mediaApplet) mediaApplet.hide();
    if (cssWatcher) cssWatcher.stop();
    PidUtils.cleanupPid(DAEMON_NAME);
    print('✅ Stopped');
}

function main() {
    print('🍬 Candy Daemon starting...');

    const gpuEnv = _detectDgpuEnv();
    if (gpuEnv)
        for (const [k, v] of Object.entries(gpuEnv))
            GLib.setenv(k, v, false);

    setupCandyDesktop();
    PidUtils.writePid(DAEMON_NAME);

    app = new Gtk.Application({
        application_id: 'com.candy.media-applet',
        flags: Gio.ApplicationFlags.FLAGS_NONE
    });

    app.connect('activate', onActivate);
    app.connect('shutdown', onShutdown);
    app.run([]);
}

main();
