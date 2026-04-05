#!/usr/bin/env gjs
// HyprCandy App Launcher — GTK4 Layer Shell
// Replaces rofi -show drun for the hyprcandydock start button.
//
// Features:
//   • Reads dock.pos (0=bottom 1=right 2=top 3=left) and positions itself
//     2–3 px from the dock edge, centered on the perpendicular axis.
//   • Search bar + icon grid (same categories / sort as the GTK app list).
//   • Left-click launches the app; Enter on search launches the first match.
//   • Right-click → context menu:
//       – Focus / switch to running instance (one entry per window)
//       – New Window  (always shown)
//       – ─────────────────────────
//       – Pin to Dock / Unpin from Dock
//   • Styling: uses the same matugen GTK CSS variables as the dock
//     (@blur_background, @primary, @on_secondary, @on_primary_fixed_variant …)
//     so it matches your theme automatically.
//   • ESC or app-launch closes the window.
//
// Toggle:  toggle-app-launcher.sh  (kills if running, spawns if not)
// Signal:  the launcher sends pkill -12 -f "gjs dock-main.js" after any
//          pin-state change so the dock hot-reloads pinned apps immediately.

'use strict';

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const { Gtk, Gdk, Gio, GLib, GObject } = imports.gi;
const Gtk4LayerShell = imports.gi.Gtk4LayerShell;

// ── Paths ──────────────────────────────────────────────────────────────────

const HOME       = GLib.get_home_dir();
// Resolve SCRIPT_DIR to an absolute path so it works regardless of whether
// the launcher was invoked with a relative or absolute path to the script.
// GLib.canonicalize_filename resolves '.' / '..' against cwd correctly.
const _rawDir    = GLib.path_get_dirname(imports.system.programInvocationName);
const SCRIPT_DIR = GLib.canonicalize_filename(_rawDir, GLib.get_current_dir());

// Import the dock's config and launcher's own config
imports.searchPath.unshift(SCRIPT_DIR);
const DockConfig     = imports.config.DockConfig;
const LauncherConfig = imports.launcherConfig.LauncherConfig;

// ── Layout constants (read from LauncherConfig) ────────────────────────────

const APP_ICON_SIZE   = LauncherConfig.iconSize       || 48;
const TEXT_FONT_SIZE  = LauncherConfig.textFontSize   || 11;
const TILE_WIDTH      = LauncherConfig.fixedTileWidth || 90;
const TILE_HEIGHT     = LauncherConfig.fixedTileHeight|| 78;
const GAP_FROM_DOCK   = 3;    // px gap between dock surface edge and launcher

// ── CSS file paths (for hot-reload watcher) ────────────────────────────────
const GTK4_COLORS_PATH = GLib.build_filenamev([HOME, '.config', 'gtk-4.0', 'colors.css']);

// Horizontal dock (top / bottom) — wide landscape launcher
const W_HORIZ    = LauncherConfig.frameWidth      || 500;
const H_HORIZ    = LauncherConfig.frameHeight     || 480;
// Columns = how many tiles fit in the inner content width.
// Inner width = frame width minus 2x12 px side padding; tiles separated by 2 px gaps.
// Math.floor((innerW + gap) / (tileW + gap)) — minimum 2 so the grid never collapses.
const COLS_HORIZ = Math.max(2, Math.floor((W_HORIZ - 24 + 2) / (TILE_WIDTH + 2)));

// Vertical dock (left / right) — narrower portrait launcher
const W_VERT     = LauncherConfig.frameWidthVert  || 380;
const H_VERT     = LauncherConfig.frameHeightVert || 560;
const COLS_VERT  = Math.max(2, Math.floor((W_VERT  - 24 + 2) / (TILE_WIDTH + 2)));

// ── Small helpers ──────────────────────────────────────────────────────────

const _dec = new TextDecoder();
const _enc = new TextEncoder();

/** Read dock.pos → 'bottom' | 'right' | 'top' | 'left' */
function readDockPos() {
    try {
        const [ok, raw] = GLib.file_get_contents(`${SCRIPT_DIR}/dock.pos`);
        if (ok) {
            const idx = parseInt(_dec.decode(raw).trim(), 10);
            return ['bottom', 'right', 'top', 'left'][idx] ?? 'bottom';
        }
    } catch (_) {}
    return 'bottom';
}

/** Read ~/.config/pinned → Set<className> */
function readPinnedApps() {
    const set = new Set();
    try {
        const [ok, raw] = GLib.file_get_contents(`${HOME}/.config/pinned`);
        if (ok)
            _dec.decode(raw).trim().split('\n')
                .forEach(l => { if (l.trim()) set.add(l.trim()); });
    } catch (_) {}
    return set;
}

/** Write updated Set back to ~/.config/pinned */
function savePinnedApps(set) {
    const file = Gio.File.new_for_path(`${HOME}/.config/pinned`);
    try {
        file.replace_contents(
            _enc.encode([...set].join('\n') + '\n'),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) { console.error('[launcher] savePinnedApps:', e.message); }
}

/**
 * Signal the dock to hot-reload (picks up new pinned-apps state).
 * The dock listens for SIGUSR2 (signal 12) to run hotReload().
 */
function signalDockRefresh() {
    try { GLib.spawn_command_line_async('pkill -12 -f "gjs dock-main.js"'); } catch (_) {}
}

/** Spawn an app cleanly (strip LD_PRELOAD, resolve %U %F etc.) */
function spawnApp(exec) {
    if (!exec) return;
    try {
        const clean = exec.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        const [, argv] = GLib.shell_parse_argv(clean);
        let envp = GLib.environ_unsetenv(GLib.get_environ(), 'LD_PRELOAD');
        GLib.spawn_async(HOME, argv, envp,
            GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
            null);
    } catch (e) { console.error('[launcher] spawnApp:', e.message); }
}

/** Spawn an app on a specific GPU (extra env vars from switcheroo) */
function spawnAppOnGPU(exec, envVars) {
    if (!exec) return;
    try {
        const clean = exec.replace(/%[UuFfIiDdNnVvKk]/g, '').trim();
        const [, argv] = GLib.shell_parse_argv(clean);
        let envp = GLib.environ_unsetenv(GLib.get_environ(), 'LD_PRELOAD');
        for (const [k, v] of Object.entries(envVars || {}))
            envp = GLib.environ_setenv(envp, k, String(v), true);
        GLib.spawn_async(HOME, argv, envp,
            GLib.SpawnFlags.SEARCH_PATH | GLib.SpawnFlags.DO_NOT_REAP_CHILD,
            null);
    } catch (e) { console.error('[launcher] spawnAppOnGPU:', e.message); }
}

/** Focus a Hyprland window by address */
function focusWindow(address) {
    try {
        GLib.spawn_command_line_async(
            `hyprctl dispatch focuswindow address:${address}`
        );
    } catch (_) {}
}

/**
 * Query running apps via hyprctl clients -j.
 * Returns Map<lowerCaseClass, [{title, address}]>
 */
function getRunningApps() {
    const running = new Map();
    try {
        const [ok, out] = GLib.spawn_command_line_sync('hyprctl clients -j');
        if (ok) {
            const clients = JSON.parse(_dec.decode(out));
            for (const c of clients) {
                const cls = (c.class || '').toLowerCase();
                if (!running.has(cls)) running.set(cls, []);
                running.get(cls).push({ title: c.title || '(no title)', address: c.address });
            }
        }
    } catch (_) {}
    return running;
}

/**
 * Build the full sorted app list from Gio.AppInfo.
 * Returns [{name, iconName, className, exec, info}]
 */
function getAllApps() {
    const apps = [];
    const seen = new Set();
    for (const info of Gio.AppInfo.get_all()) {
        if (!info.should_show()) continue;
        const id = info.get_id();
        if (seen.has(id)) continue;
        seen.add(id);

        const name  = info.get_display_name() || info.get_name() || id;
        const gicon = info.get_icon();
        let iconName = 'application-x-executable';
        if (gicon) {
            const names = gicon.get_names && gicon.get_names();
            if (names && names.length > 0) {
                iconName = names[0];
            } else {
                const f = gicon.get_file && gicon.get_file();
                iconName = (f && f.get_path && f.get_path()) || gicon.to_string() || iconName;
            }
        }

        // Prefer StartupWMClass for pin matching (same key the dock uses)
        const wm        = info.get_startup_wm_class && info.get_startup_wm_class();
        const className = wm || id.replace('.desktop', '');

        const cmd  = info.get_commandline && info.get_commandline();
        const exec = cmd ? cmd.replace(/%[UuFfIiDdNnVvKk]/g, '').trim() : null;

        apps.push({ name, iconName, className, exec, info });
    }
    apps.sort((a, b) => a.name.localeCompare(b.name));
    return apps;
}

// ── Favorites ──────────────────────────────────────────────────────────────

// nf-md-star_four_points_outline  (U+F06D0 in MDI; mapped in Nerd Fonts 3.x)
// Replace this literal with the glyph from your Nerd Fonts browser if it
// doesn't render as expected — the codepoint varies slightly between NF versions.
const FAV_GLYPH  = '\u{F06D0}';
const CHEV_UP    = '\u{F0140}';  // nf-md-chevron_up_circle  (section expanded)
const CHEV_DOWN  = '\u{F013F}';  // nf-md-chevron_down_circle (section collapsed)

// FlowBox helpers for arrow-key edge detection
function flowSelIdx(fb) {
    const sel = fb.get_selected_children();
    return sel.length ? sel[0].get_index() : -1;
}
function flowCount(fb) {
    let n = 0, c = fb.get_first_child();
    while (c) { n++; c = c.get_next_sibling(); }
    return n;
}

const FAVORITES_FILE = GLib.build_filenamev([HOME, '.config', 'hyprcandy-launcher-favorites']);

function readFavorites() {
    const set = new Set();
    try {
        const [ok, raw] = GLib.file_get_contents(FAVORITES_FILE);
        if (ok)
            _dec.decode(raw).trim().split('\n')
                .forEach(l => { if (l.trim()) set.add(l.trim()); });
    } catch (_) {}
    return set;
}

function writeFavorites(set) {
    const file = Gio.File.new_for_path(FAVORITES_FILE);
    try {
        // GLib.file_replace_contents requires a non-NULL (non-empty) byte array.
        // Always write at least a newline so an empty set produces a valid write.
        const content = set.size ? [...set].join('\n') + '\n' : '\n';
        file.replace_contents(
            _enc.encode(content),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) { console.error('[launcher] writeFavorites:', e.message); }
}

// ── Groups ─────────────────────────────────────────────────────────────────

const GROUPS_FILE = GLib.build_filenamev([HOME, '.config', 'hyprcandy-launcher-groups']);

/** Read groups from file. Returns { groupName: [className, ...], ... } */
function readGroups() {
    try {
        const [ok, raw] = GLib.file_get_contents(GROUPS_FILE);
        if (ok) return JSON.parse(_dec.decode(raw));
    } catch (_) {}
    return {};
}

/** Write groups to file */
function writeGroups(groups) {
    const file = Gio.File.new_for_path(GROUPS_FILE);
    try {
        file.replace_contents(
            _enc.encode(JSON.stringify(groups, null, 2) + '\n'),
            null, false, Gio.FileCreateFlags.REPLACE_DESTINATION, null
        );
    } catch (e) { console.error('[launcher] writeGroups:', e.message); }
}

/** Add an app to a group */
function addAppToGroup(groups, groupName, className) {
    if (!groups[groupName]) groups[groupName] = [];
    if (!groups[groupName].includes(className))
        groups[groupName].push(className);
    writeGroups(groups);
}

/** Remove an app from a group */
function removeAppFromGroup(groups, groupName, className) {
    if (groups[groupName]) {
        groups[groupName] = groups[groupName].filter(c => c !== className);
        if (groups[groupName].length === 0) delete groups[groupName];
        writeGroups(groups);
    }
}

// ── dGPU detection (mirrors daemon.js _querySwitcheroo logic) ─────────────

let _gpuCache = undefined;  // undefined = not yet queried; [] = queried but none

/**
 * Returns [{name, envVars}] for each discrete GPU reported by
 * switcheroo-control, or [] on single-GPU / unavailable systems.
 * Mirrors the double-deep_unpack pattern from daemon.js exactly.
 */
function getAvailableDGPUs() {
    if (_gpuCache !== undefined) return _gpuCache;
    try {
        const result = Gio.DBus.system.call_sync(
            'net.hadess.SwitcherooControl',
            '/net/hadess/SwitcherooControl',
            'org.freedesktop.DBus.Properties',
            'Get',
            new GLib.Variant('(ss)', ['net.hadess.SwitcherooControl', 'GPUs']),
            null, Gio.DBusCallFlags.NONE, -1, null
        );
        // Properties.Get returns (v). First deep_unpack unwraps the tuple;
        // raw[0] is still a GLib.Variant wrapping aa{sv}, so unpack again.
        const raw   = result.deep_unpack();
        const inner = raw[0];
        const unpacked = (inner && typeof inner.deep_unpack === 'function')
            ? inner.deep_unpack() : inner;
        const gpuList = unpacked ? Object.values(unpacked) : [];

        const _u = v => (v && typeof v.deep_unpack === 'function') ? v.deep_unpack() : v;
        _gpuCache = [];
        for (const gpuDict of gpuList) {
            if (!!_u(gpuDict['Default'])) continue;  // skip iGPU / default GPU
            const evArr = _u(gpuDict['Environment']);
            const arr   = Array.isArray(evArr) ? evArr : (evArr ? Object.values(evArr) : []);
            const envVars = {};
            for (let i = 0; i + 1 < arr.length; i += 2)
                envVars[arr[i]] = arr[i + 1];
            _gpuCache.push({
                name: _u(gpuDict['Name']) || 'dGPU',
                envVars,
            });
        }
    } catch (_) {
        _gpuCache = [];
    }
    return _gpuCache;
}

/** Strip verbose vendor prefixes for compact popover labels (mirrors daemon.js) */
function abbreviateGpuName(name) {
    if (!name) return 'dGPU';
    let s = name
        .replace(/^Advanced Micro Devices,\s*Inc\.\s*\[AMD\/ATI\]\s*/i, '')
        .replace(/^NVIDIA\s+Corporation\s*/i, '')
        .replace(/^Intel\s+Corporation\s*/i, '')
        .replace(/^Intel\(R\)\s*/i, 'Intel® ')
        .trim();
    return s.length > 32 ? s.slice(0, 31) + '…' : s;
}

// ── CSS ────────────────────────────────────────────────────────────────────

// These rules use the same matugen GTK colour variables the dock uses.
// They are loaded at APPLICATION priority so they win over the GTK default
// theme but still sit below the inline popover provider used for transparency.
// CSS is built dynamically so border-radius / border-width read from LauncherConfig.
function buildLauncherCSS() {
    const r  = LauncherConfig.borderRadius     || 20;
    const bw = LauncherConfig.borderWidth      || 2;
    const sr = LauncherConfig.searchRadius     ?? LauncherConfig.innerRadius ?? 12;
    const lr = LauncherConfig.listRadius       ?? LauncherConfig.innerRadius ?? 12;
    const ib = LauncherConfig.innerBorderWidth || 1;
    const ip = LauncherConfig.innerPadding     || 10;

    return `

/* ── Window shell ─────────────────────────────────────────────────────── */
window.hyprcandy-launcher {
    background-color: @blur_background;
    border-radius: ${r}px;
    border-style: solid;
    border-width: ${bw}px;
    border-color: @on_primary_fixed_variant;
}

/* ── Inner section frames (rofi inputbar / listbox equivalent) ────────── */
/* .search-frame wraps the search bar; .list-frame wraps the app grid.
   Both have @primary border + @blur_background fill, padded from the
   window edge — matching rofi's inputbar/listbox visual structure.
   NOTE: left/right margin on .search-frame is set in JS (search width).
   No padding here — the border sits flush against the SearchEntry.       */

.search-frame {
    background-color: @blur_background;
    border-radius: ${sr}px;
    border-style: solid;
    border-width: ${ib}px;
    border-color: @primary;
    margin-top: ${ip}px;
    margin-bottom: ${Math.round(ip / 2)}px;
}

.list-frame {
    background-color: @blur_background;
    border-radius: ${lr}px;
    border-style: solid;
    border-width: ${ib}px;
    border-color: @primary;
    margin: ${Math.round(ip / 2)}px ${ip}px ${ip}px ${ip}px;
}

/* ── Search entry — sits inside .search-frame ─────────────────────────── */
.launcher-search {
    background-color: transparent;
    border-radius: ${sr}px;
    border: none;
    color: @primary;
    caret-color: @primary;
    font-size: 14px;
    padding: 0px 10px;
    min-height: 38px;
    /* Suppress the GTK4 theme focus highlight ring — the .search-frame
       border IS the visual focus indicator for the search area. */
    outline: none;
    box-shadow: none;
}

.launcher-search:focus,
.launcher-search:focus-within {
    background-color: alpha(@primary, 0.05);
    outline: none;
    box-shadow: none;
    border: none;
}

.launcher-search > text,
.launcher-search text {
    background: transparent;
    color: @primary;
}

.launcher-search image {
    color: alpha(@primary, 0.65);
}

/* ── Arrow-key navigation — FlowBoxChild focus/selected state ─────────── */
/* flowboxchild is the GTK node wrapping each item appended to FlowBox.
   :selected fires when the child has keyboard focus in SINGLE/BROWSE mode. */
flowboxchild {
    border-radius: 10px;
    padding: 0;
    margin: 0;
    background: transparent;
    outline: none;
    min-width: ${TILE_WIDTH}px;
    min-height: ${TILE_HEIGHT}px;
}

flowboxchild:selected,
flowboxchild:focus {
    background-color: @on_primary_fixed_variant;
    outline: none;
    border-radius: 10px;
}

/* Label turns to @primary when the parent child is selected */
flowboxchild:selected .app-tile-label,
flowboxchild:focus .app-tile-label {
    color: @primary;
}

/* The button inside a selected child should stay transparent so the
   flowboxchild background colour shows through unobstructed. */
flowboxchild:selected > button.app-tile,
flowboxchild:focus > button.app-tile {
    background-color: transparent;
    border-color: transparent;
}

/* ── Scroll area — sits inside .list-frame ────────────────────────────── */
.launcher-scroll {
    background: transparent;
    border-radius: ${lr - 1}px;
}
.launcher-scroll undershoot,
.launcher-scroll overshoot {
    background: transparent;
}
.launcher-scroll scrollbar {
    background: transparent;
    padding: 0px;
}
.launcher-scroll scrollbar slider {
    background-color: alpha(@primary, 0.22);
    border-radius: 4px;
    min-width: 4px;
    min-height: 4px;
}
.launcher-scroll scrollbar slider:hover {
    background-color: alpha(@primary, 0.42);
}

/* ── App grid ─────────────────────────────────────────────────────────── */
.launcher-grid {
    background: transparent;
    padding: 6px 10px 12px 10px;
}

/* ── App tiles ────────────────────────────────────────────────────────── */
button.app-tile {
    background: transparent;
    background-color: transparent;
    border-radius: 10px;
    border: 1px solid transparent;
    padding: 10px 6px 8px 6px;
    min-width: ${TILE_WIDTH}px;
    min-height: ${TILE_HEIGHT}px;
    outline: none;
    box-shadow: none;
}

button.app-tile:hover {
    background-color: alpha(@primary, 0.09);
    border-color: alpha(@primary, 0.16);
}

button.app-tile:active {
    background-color: alpha(@on_primary_fixed_variant, 0.55);
    border-color: @primary;
}

button.app-tile:focus {
    outline: none;
    box-shadow: none;
    border-color: alpha(@primary, 0.3);
}

.app-tile-label {
    color: @on_surface;
    font-size: ${TEXT_FONT_SIZE}px;
    margin-top: 5px;
}

/* ── Context menu popovers (fallback — inline provider takes priority) ── */
popover.launcher-popover {
    background-color: transparent;
    border: none;
    border-radius: 12px;
    padding: 0px;
    box-shadow: none;
}

popover.launcher-popover > contents {
    background-color: @on_secondary;
    border: 1px solid alpha(@secondary, 0.5);
    border-radius: 12px;
    padding: 0px;
    min-width: 190px;
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.45);
    color: @primary;
}

popover.launcher-popover > arrow {
    background-color: @on_secondary;
}

popover.launcher-popover > contents separator {
    background-color: alpha(@secondary, 0.6);
    min-height: 1px;
}

popover.launcher-popover .pop-item {
    background: transparent;
    background-color: transparent;
    color: @primary;
    padding: 7px 14px;
    border-radius: 6px;
    border: none;
    box-shadow: none;
    font-size: 13px;
}

popover.launcher-popover .pop-item:hover {
    background-color: alpha(@primary, 0.11);
}

popover.launcher-popover .pop-section-header {
    font-size: 11px;
    font-weight: bold;
    color: @inverse_primary;
    padding: 5px 14px 2px 14px;
}

popover.launcher-popover button {
    background: none;
    background-color: transparent;
    border: none;
    box-shadow: none;
    min-width: 0;
    min-height: 0;
    padding: 0;
    margin: 0;
    outline: none;
}

/* ── Favorites section ────────────────────────────────────────────────── */
.fav-section-row {
    background: transparent;
    padding: 6px 12px 2px 12px;
}

/* Collapse toggle — inherits no button chrome, just the glyph label */
.fav-toggle-btn {
    background: transparent;
    background-color: transparent;
    border: none;
    box-shadow: none;
    padding: 0;
    margin: 0;
    min-width: 0;
    min-height: 0;
    outline: none;
}
.fav-toggle-btn:hover {
    background-color: alpha(@primary, 0.10);
    border-radius: 4px;
}

.fav-glyph {
    color: @primary;
    font-size: 14px;
    margin-right: 4px;
}

.fav-section-label {
    color: @primary;
    font-size: 11px;
    font-weight: bold;
}

.fav-separator {
    background-color: alpha(@primary, 0.25);
    margin-left: 12px;
    margin-right: 12px;
    margin-top: 2px;
    margin-bottom: 2px;
}
`;
}

// Inline popover provider — same pattern the dock uses to fix GTK4 popover
// transparency on Wayland (popover > contents needs an explicit bg rule).
const POPOVER_INLINE_CSS = `
popover.launcher-popover {
    background-color: transparent;
    border: none;
    border-radius: 12px;
}
popover.launcher-popover > contents {
    background-color: @on_secondary;
    border-radius: 12px;
    border: 1px solid alpha(@secondary, 0.5);
    box-shadow: 0 4px 14px rgba(0, 0, 0, 0.45);
    color: @primary;
}
popover.launcher-popover > arrow {
    background-color: @on_secondary;
}
popover.launcher-popover > contents separator {
    background-color: alpha(@secondary, 0.6);
    min-height: 1px;
}
popover.launcher-popover .pop-item {
    background: transparent;
    background-color: transparent;
    color: @primary;
    padding: 7px 14px;
    border-radius: 6px;
    border: none;
    box-shadow: none;
    font-size: 13px;
}
popover.launcher-popover .pop-item:hover {
    background-color: alpha(@primary, 0.11);
}
popover.launcher-popover .pop-section-header {
    font-size: 11px;
    font-weight: bold;
    color: @inverse_primary;
    padding: 5px 14px 2px 14px;
}
popover.launcher-popover button {
    background: none;
    background-color: transparent;
    border: none;
    box-shadow: none;
    min-width: 0;
    min-height: 0;
    padding: 0;
    margin: 0;
    outline: none;
}
`;

// ── AppLauncherWindow ──────────────────────────────────────────────────────

const AppLauncherWindow = GObject.registerClass({
    GTypeName: 'HyprCandyAppLauncherWindow',
}, class AppLauncherWindow extends Gtk.Window {

    constructor(application) {
        super({ title: 'HyprCandy Launcher', decorated: false, application });

        this._dockPos     = readDockPos();
        this._isVert      = (this._dockPos === 'left' || this._dockPos === 'right');
        this._allApps     = getAllApps();
        this._pinnedSet   = readPinnedApps();
        this._favoritesSet = readFavorites();
        this._runningApps = getRunningApps();
        this._popoverCSS              = null;
        this._popoverOpen             = false;
        this._postPopoverGrace        = false;
        this._graceTimer              = 0;
        this._pendingFavRefreshQuery  = undefined;
        this._colorMonitor            = null;   // Gio.FileMonitor for gtk-4.0/colors.css
        this._colorReloadTimer        = 0;      // debounce source ID

        this._loadGlobalCSS();
        this._setupLayerShell();
        this._buildUI();
        this._setupKeyboard();
        this._setupFocusClose();
        this._setupColorMonitor();

        this.connect('destroy', () => this._teardownColorMonitor());
        this.add_css_class('hyprcandy-launcher');
    }

    // ─── CSS ────────────────────────────────────────────────────────────

    _loadGlobalCSS() {
        const display  = Gdk.Display.get_default();

        // Load matugen colors (same paths the dock uses) so @primary etc. resolve
        const paths = [
            GLib.build_filenamev([HOME, '.config', 'gtk-3.0', 'colors.css']),
            GLib.build_filenamev([HOME, '.config', 'gtk-4.0', 'colors.css']),
        ];
        for (const p of paths) {
            if (!GLib.file_test(p, GLib.FileTest.EXISTS)) continue;
            const prov = new Gtk.CssProvider();
            try {
                prov.load_from_path(p);
                Gtk.StyleContext.add_provider_for_display(
                    display, prov, Gtk.STYLE_PROVIDER_PRIORITY_USER
                );
            } catch (_) {}
        }

        // Launcher-specific rules (built dynamically from LauncherConfig)
        const launcherProv = new Gtk.CssProvider();
        try {
            launcherProv.load_from_data(buildLauncherCSS(), -1);
            Gtk.StyleContext.add_provider_for_display(
                display, launcherProv, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );
        } catch (e) { console.error('[launcher] CSS load failed:', e.message); }
    }

    _getPopoverCSSProvider() {
        if (!this._popoverCSS) {
            this._popoverCSS = new Gtk.CssProvider();
            try { this._popoverCSS.load_from_data(POPOVER_INLINE_CSS, -1); } catch (_) {}
        }
        return this._popoverCSS;
    }

    // ─── Layer shell ─────────────────────────────────────────────────────

    // ─── Dock thickness query ────────────────────────────────────────────
    // Ask Hyprland for the live rendered height/width of the dock surface so
    // the launcher margin is exact regardless of config edits or innerPadding.
    // Falls back to a formula-based estimate if hyprctl is unavailable.
    _queryDockThick(pos) {
        try {
            const [ok, out] = GLib.spawn_command_line_sync('hyprctl layers -j');
            if (!ok) return null;
            const data = JSON.parse(_dec.decode(out));
            for (const monData of Object.values(data)) {
                for (const surfList of Object.values(monData.levels ?? {})) {
                    for (const s of (Array.isArray(surfList) ? surfList : [])) {
                        if (s.namespace === 'hyprcandy-dock') {
                            // w/h are the actual surface pixel dimensions
                            return (pos === 'left' || pos === 'right') ? s.w : s.h;
                        }
                    }
                }
            }
        } catch (_) {}
        return null;  // caller falls back to formula
    }

    // ─── Shared margin helper ────────────────────────────────────────────
    // Computes the margin (screen-edge → launcher edge) needed to clear the
    // dock, using the live dock size when available.
    _computeMargin(pos) {
        const cfg      = DockConfig;
        const iconPx   = cfg.appIconSize || 20;
        const borderPx = cfg.borderWidth || 2;
        const padPx    = cfg.innerPadding || 0;  // actual value, not hardcoded 4

        // Live dock thickness beats the formula; formula is the fallback.
        const measured  = this._queryDockThick(pos);
        const dockThick = measured ?? ((iconPx + 8) + 2 * padPx + 2 * borderPx);

        const ov = cfg.positionOverrides?.[pos] ?? {};
        let edgeMargin;
        if      (pos === 'bottom') edgeMargin = ov.marginBottom ?? cfg.marginBottom ?? 6;
        else if (pos === 'top'   ) edgeMargin = ov.marginTop    ?? cfg.marginTop    ?? 2;
        else if (pos === 'left'  ) edgeMargin = ov.marginLeft   ?? cfg.marginLeft   ?? 6;
        else                       edgeMargin = ov.marginRight  ?? cfg.marginRight  ?? 6;

        return dockThick + edgeMargin + GAP_FROM_DOCK;
    }

    _setupLayerShell() {
        const cfg  = DockConfig;
        const pos  = this._dockPos;

        Gtk4LayerShell.init_for_window(this);
        Gtk4LayerShell.set_namespace(this, 'hyprcandy-launcher');
        // OVERLAY sits above the dock's TOP layer so it renders on top of the dock.
        Gtk4LayerShell.set_layer(this, Gtk4LayerShell.Layer.OVERLAY);
        // -1 = don't steal screen real-estate from other windows
        Gtk4LayerShell.set_exclusive_zone(this, -1);
        // ON_DEMAND: gets keyboard only when the surface has focus, so other
        // surfaces still receive input (unlike EXCLUSIVE which grabs everything).
        Gtk4LayerShell.set_keyboard_mode(this, Gtk4LayerShell.KeyboardMode.ON_DEMAND);

        // Anchor to ONE edge (the dock's edge).  The compositor will centre the
        // surface on the perpendicular axis because neither opposite anchor is set.
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.BOTTOM, pos === 'bottom');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.TOP,    pos === 'top');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.LEFT,   pos === 'left');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.RIGHT,  pos === 'right');

        // ── Compute margin from the screen edge using live dock size ─────
        const totalMargin = this._computeMargin(pos);

        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.BOTTOM, pos === 'bottom' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.TOP,    pos === 'top'    ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.LEFT,   pos === 'left'   ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.RIGHT,  pos === 'right'  ? totalMargin : 0);

        // Window size — wider for horizontal docks, taller for vertical
        if (this._isVert) {
            this.set_size_request(W_VERT, H_VERT);
            this.set_default_size(W_VERT, H_VERT);
        } else {
            this.set_size_request(W_HORIZ, H_HORIZ);
            this.set_default_size(W_HORIZ, H_HORIZ);
        }
    }

    // ─── Live position refresh ───────────────────────────────────────────
    // Called from the SIGUSR1 show path so the launcher re-anchors to the
    // current dock edge even when the dock has cycled since last use.
    // gtk4-layer-shell allows set_anchor / set_margin after init_for_window;
    // the new values take effect on the next Wayland surface commit.

    _refreshLayerShell() {
        const newPos  = readDockPos();
        const newVert = (newPos === 'left' || newPos === 'right');

        // Always re-apply anchors/margins (dock may have moved even if pos
        // string is the same, e.g. after a restart with stale dock.pos).
        this._dockPos = newPos;
        this._isVert  = newVert;

        // ── Anchors — only the dock edge is anchored; compositor centres
        //             the launcher on the perpendicular axis automatically.
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.BOTTOM, newPos === 'bottom');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.TOP,    newPos === 'top');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.LEFT,   newPos === 'left');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.RIGHT,  newPos === 'right');

        // ── Margin from screen edge (uses live dock size via _computeMargin)
        const totalMargin = this._computeMargin(newPos);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.BOTTOM, newPos === 'bottom' ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.TOP,    newPos === 'top'    ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.LEFT,   newPos === 'left'   ? totalMargin : 0);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.RIGHT,  newPos === 'right'  ? totalMargin : 0);

        // ── Window size and FlowBox column counts
        const W    = newVert ? W_VERT  : W_HORIZ;
        const H    = newVert ? H_VERT  : H_HORIZ;
        const cols = newVert ? COLS_VERT : COLS_HORIZ;
        this.set_size_request(W, H);
        this.set_default_size(W, H);

        if (this._flow) {
            this._flow.set_max_children_per_line(cols);
            this._flow.set_min_children_per_line(cols);
        }
        if (this._favFlow) {
            this._favFlow.set_max_children_per_line(cols);
            this._favFlow.set_min_children_per_line(cols);
        }
    }

    // ─── Build UI ────────────────────────────────────────────────────────

    _buildUI() {
        const lc   = LauncherConfig;
        const winW = this._isVert ? W_VERT : W_HORIZ;
        const ip   = lc.innerPadding          || 10;
        const frac = Math.min(1, Math.max(0.2, lc.searchWidthFraction ?? 1.0));
        // Extra horizontal margin to shrink the search frame when frac < 1
        const sfExtraH = Math.max(0, Math.floor((winW - Math.round(winW * frac)) / 2));

        const root = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        this.set_child(root);

        // ── Search frame ────────────────────────────────────────────────
        const searchFrame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        searchFrame.add_css_class('search-frame');
        searchFrame.set_margin_start(ip + sfExtraH);
        searchFrame.set_margin_end(ip + sfExtraH);
        root.append(searchFrame);

        this._searchEntry = new Gtk.SearchEntry();
        this._searchEntry.set_placeholder_text('Search applications…');
        this._searchEntry.add_css_class('launcher-search');
        this._searchEntry.set_hexpand(true);
        searchFrame.append(this._searchEntry);

        // ── List frame ──────────────────────────────────────────────────
        const listFrame = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        listFrame.add_css_class('list-frame');
        listFrame.set_vexpand(true);
        root.append(listFrame);

        // ── Favorites section (fixed, not inside scroll) ─────────────────
        this._favSection = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        listFrame.append(this._favSection);

        const favHeaderRow = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 4);
        favHeaderRow.add_css_class('fav-section-row');
        this._favSection.append(favHeaderRow);

        // Full-width toggle button: "Favorites" title left, chevron right.
        // Clicking anywhere on the row collapses / expands the favorites grid.
        this._favCollapsed = false;
        const favToggleBtn = Gtk.Button.new();
        favToggleBtn.add_css_class('fav-toggle-btn');
        favToggleBtn.set_can_focus(false);
        favToggleBtn.set_hexpand(true);

        const favBtnBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 0);
        favBtnBox.set_hexpand(true);

        const favSectionLabel = Gtk.Label.new('Favorites');
        favSectionLabel.add_css_class('fav-section-label');
        favSectionLabel.set_halign(Gtk.Align.START);
        favSectionLabel.set_hexpand(true);
        favBtnBox.append(favSectionLabel);

        // Chevron on right: CHEV_UP when expanded (click to collapse),
        // CHEV_DOWN when collapsed (click to expand) — standard accordion UX.
        this._favChevron = Gtk.Label.new(CHEV_UP);
        this._favChevron.add_css_class('fav-glyph');
        favBtnBox.append(this._favChevron);

        favToggleBtn.set_child(favBtnBox);
        favHeaderRow.append(favToggleBtn);

        favToggleBtn.connect('clicked', () => {
            this._favCollapsed = !this._favCollapsed;
            this._favFlow.set_visible(!this._favCollapsed);
            this._favSep.set_visible(!this._favCollapsed);
            this._favChevron.set_text(this._favCollapsed ? CHEV_DOWN : CHEV_UP);
        });

        this._favFlow = new Gtk.FlowBox();
        this._favFlow.set_max_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._favFlow.set_min_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._favFlow.set_row_spacing(2);
        this._favFlow.set_column_spacing(2);
        this._favFlow.set_homogeneous(true);
        this._favFlow.set_selection_mode(Gtk.SelectionMode.SINGLE);
        this._favFlow.add_css_class('launcher-grid');
        this._favSection.append(this._favFlow);

        // Keyboard Enter on a focused favorites item → launch
        this._favFlow.connect('child-activated', (_fb, child) => {
            const btn = child.get_child();
            if (btn && btn._appData) { spawnApp(btn._appData.exec); this.close(); }
        });

        const favSep = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        favSep.add_css_class('fav-separator');
        this._favSep = favSep;
        this._favSection.append(favSep);

        this._favSection.set_visible(false);  // hidden until populated

        // ── Main scroll + FlowBox ───────────────────────────────────────
        const scroll = new Gtk.ScrolledWindow();
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.set_vexpand(true);
        scroll.add_css_class('launcher-scroll');
        listFrame.append(scroll);

        this._flow = new Gtk.FlowBox();
        this._flow.set_max_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._flow.set_min_children_per_line(this._isVert ? COLS_VERT : COLS_HORIZ);
        this._flow.set_row_spacing(2);
        this._flow.set_column_spacing(2);
        this._flow.set_homogeneous(true);
        this._flow.set_selection_mode(Gtk.SelectionMode.SINGLE);
        this._flow.add_css_class('launcher-grid');
        scroll.set_child(this._flow);

        // Keyboard Enter on a focused main-grid item → launch
        this._flow.connect('child-activated', (_fb, child) => {
            const btn = child.get_child();
            if (btn && btn._appData) { spawnApp(btn._appData.exec); this.close(); }
        });

        // Initial population
        this._refreshFavorites('');
        this._populateApps(this._allApps);

        // ── Search filtering ───────────────────────────────────────────
        this._searchEntry.connect('search-changed', () => {
            const q = this._searchEntry.get_text().toLowerCase().trim();
            this._refreshFavorites(q);
            this._populateApps(
                q ? this._allApps.filter(a => a.name.toLowerCase().includes(q)) : this._allApps
            );
        });

        // Enter on search → launch first filtered result
        this._searchEntry.connect('activate', () => {
            const q = this._searchEntry.get_text().toLowerCase().trim();
            const filtered = q
                ? this._allApps.filter(a => a.name.toLowerCase().includes(q))
                : this._allApps;
            if (filtered.length > 0) {
                spawnApp(filtered[0].exec);
                this.close();
            }
        });
    }


    _populateApps(apps) {
        let child = this._flow.get_first_child();
        while (child) {
            const next = child.get_next_sibling();
            this._flow.remove(child);
            child = next;
        }
        for (const app of apps)
            this._flow.append(this._makeAppTile(app));
    }

    _makeAppTile(app) {
        // ── Button ─────────────────────────────────────────────────────
        const btn = Gtk.Button.new();
        btn.add_css_class('app-tile');
        btn.set_tooltip_text(app.name);
        // Hard-pin dimensions so tiles never stretch when the row is short
        btn.set_size_request(TILE_WIDTH, TILE_HEIGHT);
        // Tag the app data so child-activated (Enter key) can retrieve it
        btn._appData = app;
        // Don't let the button steal keyboard focus — FlowBoxChild handles
        // arrow-key selection; the button only reacts to pointer events.
        btn.set_can_focus(false);

        // ── Icon + label ───────────────────────────────────────────────
        const col = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        col.set_halign(Gtk.Align.CENTER);
        col.set_valign(Gtk.Align.CENTER);
        btn.set_child(col);

        const img = (app.iconName.startsWith('/') || app.iconName.startsWith('~'))
            ? Gtk.Image.new_from_file(app.iconName)
            : Gtk.Image.new_from_icon_name(app.iconName);
        img.set_pixel_size(APP_ICON_SIZE);
        img.set_halign(Gtk.Align.CENTER);
        col.append(img);

        const lbl = Gtk.Label.new(app.name);
        lbl.add_css_class('app-tile-label');
        lbl.set_halign(Gtk.Align.CENTER);
        lbl.set_max_width_chars(12);
        lbl.set_ellipsize(3 /* Pango.EllipsizeMode.END */);
        lbl.set_wrap(false);
        col.append(lbl);

        // ── Left-click → launch ────────────────────────────────────────
        btn.connect('clicked', () => {
            spawnApp(app.exec);
            this.close();
        });

        // ── Right-click → context menu ─────────────────────────────────
        const rc = new Gtk.GestureClick();
        rc.set_button(3);
        rc.connect('pressed', () => this._showContextMenu(app, btn));
        btn.add_controller(rc);

        return btn;
    }

    // ─── Context menu ────────────────────────────────────────────────────

    _showContextMenu(app, parentBtn) {
        // Choose popover direction to open away from the dock edge (same logic
        // the dock uses in _showContextMenu / _showStartMenu)
        const pos = this._dockPos;
        let popPos;
        if      (pos === 'bottom') popPos = Gtk.PositionType.TOP;
        else if (pos === 'top'   ) popPos = Gtk.PositionType.BOTTOM;
        else if (pos === 'left'  ) popPos = Gtk.PositionType.RIGHT;
        else                       popPos = Gtk.PositionType.LEFT;

        const pop = new Gtk.Popover();
        // Parent to the launcher window rather than the tile button so that
        // _refreshFavorites can safely remove tiles (including parentBtn) from
        // _favFlow without corrupting the popover's parent chain.
        pop.set_parent(this);
        pop.set_has_arrow(false);
        pop.set_position(popPos);
        // Point at the button so the popover opens in the right place.
        {
            const [ok, bx, by] = parentBtn.translate_coordinates(this, 0, 0);
            if (ok)
                pop.set_pointing_to(new Gdk.Rectangle({
                    x: Math.round(bx), y: Math.round(by),
                    width:  parentBtn.get_width(),
                    height: parentBtn.get_height(),
                }));
        }
        pop.add_css_class('launcher-popover');
        // Inline provider to force correct background on Wayland
        pop.get_style_context().add_provider(
            this._getPopoverCSSProvider(),
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        );
        pop.connect('closed', () => {
            this._popoverOpen = false;
            // Grace period: block focus-loss close for 600 ms after any popover
            // closes so that pin/unpin actions (which popdown() the menu) don't
            // immediately dismiss the launcher when focus briefly returns to it.
            if (this._graceTimer) {
                GLib.source_remove(this._graceTimer);
                this._graceTimer = 0;
            }
            this._postPopoverGrace = true;
            this._graceTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 600, () => {
                this._postPopoverGrace = false;
                this._graceTimer = 0;
                return GLib.SOURCE_REMOVE;
            });
            // Unparent the popover first, THEN refresh the favorites grid.
            // Running _refreshFavorites while GTK4 is still tearing down the
            // popover surface caused widget-tree corruption that left favorites
            // stuck and made "Remove from Favorites" appear to do nothing.
            const pendingQuery = this._pendingFavRefreshQuery;
            this._pendingFavRefreshQuery = undefined;
            GLib.idle_add(GLib.PRIORITY_LOW, () => {
                try { pop.unparent(); } catch (_) {}
                // If a favorites add/remove happened, refresh the strip now
                // that the popover is safely gone from the widget tree.
                if (pendingQuery !== undefined) {
                    this._favoritesSet = readFavorites();
                    this._refreshFavorites(pendingQuery);
                    // Also re-populate main grid so removed-favorite apps reappear
                    const filtered = pendingQuery
                        ? this._allApps.filter(a => a.name.toLowerCase().includes(pendingQuery) && !this._favoritesSet.has(a.className))
                        : this._allApps.filter(a => !this._favoritesSet.has(a.className));
                    this._populateApps(filtered);
                }
                return GLib.SOURCE_REMOVE;
            });
        });
        this._popoverOpen = true;

        // ── Menu content ───────────────────────────────────────────────
        const menu = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        menu.set_margin_top(6);
        menu.set_margin_bottom(6);
        menu.set_margin_start(6);
        menu.set_margin_end(6);

        // ── Running instances (same-as-dock UX) ────────────────────────
        const key = app.className.toLowerCase();
        const instances = this._runningApps.get(key)
            ?? this._runningApps.get(app.className)
            ?? [];

        if (instances.length > 0) {
            // Section header (only when more than one instance)
            if (instances.length > 1) {
                const hdr = Gtk.Label.new('Running Windows');
                hdr.set_halign(Gtk.Align.START);
                hdr.add_css_class('pop-section-header');
                menu.append(hdr);
            }

            for (const inst of instances) {
                const short = inst.title.length > 34
                    ? inst.title.slice(0, 34) + '…'
                    : inst.title;
                const focBtn = Gtk.Button.new_with_label(
                    instances.length === 1 ? `Switch to Window` : short
                );
                focBtn.add_css_class('pop-item');
                focBtn.set_halign(Gtk.Align.FILL);
                focBtn.set_tooltip_text(inst.title);
                focBtn.connect('clicked', () => {
                    focusWindow(inst.address);
                    pop.popdown();
                    this.close();
                });
                menu.append(focBtn);
            }

            const sep0 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            sep0.set_margin_top(4);
            sep0.set_margin_bottom(4);
            menu.append(sep0);
        }

        // ── New Window (always) ────────────────────────────────────────
        const newBtn = Gtk.Button.new_with_label('New Window');
        newBtn.add_css_class('pop-item');
        newBtn.set_halign(Gtk.Align.FILL);
        newBtn.connect('clicked', () => {
            spawnApp(app.exec);
            pop.popdown();
            this.close();
        });
        menu.append(newBtn);

        // ── Separator ──────────────────────────────────────────────────
        const sep1 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        sep1.set_margin_top(4);
        sep1.set_margin_bottom(4);
        menu.append(sep1);

        // ── Pin / Unpin ────────────────────────────────────────────────
        this._pinnedSet = readPinnedApps();
        const isPinned  = this._pinnedSet.has(app.className);
        const pinBtn    = Gtk.Button.new_with_label(isPinned ? 'Unpin from Dock' : 'Pin to Dock');
        pinBtn.add_css_class('pop-item');
        pinBtn.set_halign(Gtk.Align.FILL);
        pinBtn.connect('clicked', () => {
            this._pinnedSet = readPinnedApps();
            if (this._pinnedSet.has(app.className))
                this._pinnedSet.delete(app.className);
            else
                this._pinnedSet.add(app.className);
            savePinnedApps(this._pinnedSet);
            signalDockRefresh();
            pop.popdown();
        });
        menu.append(pinBtn);

        // ── Favorites ──────────────────────────────────────────────────
        const sep2 = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
        sep2.set_margin_top(4);
        sep2.set_margin_bottom(4);
        menu.append(sep2);

        this._favoritesSet = readFavorites();
        const isFav   = this._favoritesSet.has(app.className);
        const favBtn  = Gtk.Button.new_with_label(isFav ? 'Remove from Favorites' : 'Add to Favorites');
        favBtn.add_css_class('pop-item');
        favBtn.set_halign(Gtk.Align.FILL);
        favBtn.connect('clicked', () => {
            this._favoritesSet = readFavorites();
            if (this._favoritesSet.has(app.className))
                this._favoritesSet.delete(app.className);
            else
                this._favoritesSet.add(app.className);
            writeFavorites(this._favoritesSet);
            // Capture query now (before popdown clears any state)
            const q = this._searchEntry
                ? this._searchEntry.get_text().toLowerCase().trim() : '';
            // Defer the grid refresh until after the popover is fully unparented
            // so GTK4 doesn't encounter widget-tree mutations while tearing down
            // the popover surface (which was the cause of favorites getting "stuck"
            // and Remove-from-Favorites having no visible effect).
            this._pendingFavRefreshQuery = q;
            pop.popdown();
            // _refreshFavorites will be called from the 'closed' handler once
            // pop.unparent() has been scheduled via idle_add.
        });
        menu.append(favBtn);

        // ── dGPU launch (only shown when switcheroo reports a dGPU) ────
        const gpus = getAvailableDGPUs();
        if (gpus.length > 0) {
            const gpuSepTop = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            gpuSepTop.set_margin_top(4);
            gpuSepTop.set_margin_bottom(4);
            menu.append(gpuSepTop);

            const gpuHdr = Gtk.Label.new('Launch on GPU');
            gpuHdr.set_halign(Gtk.Align.CENTER);
            gpuHdr.add_css_class('pop-section-header');
            menu.append(gpuHdr);

            const gpuSepBot = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            gpuSepBot.set_margin_top(4);
            gpuSepBot.set_margin_bottom(4);
            menu.append(gpuSepBot);

            for (const gpu of gpus) {
                const gpuBtn = Gtk.Button.new_with_label(abbreviateGpuName(gpu.name));
                gpuBtn.add_css_class('pop-item');
                gpuBtn.set_halign(Gtk.Align.FILL);
                gpuBtn.connect('clicked', () => {
                    spawnAppOnGPU(app.exec, gpu.envVars);
                    pop.popdown();
                    this.close();
                });
                menu.append(gpuBtn);
            }
        }

        pop.set_child(menu);
        pop.popup();
    }

    // ─── Keyboard / close ────────────────────────────────────────────────

    _setupKeyboard() {
        const cols = this._isVert ? COLS_VERT : COLS_HORIZ;

        // ── Search entry key handler ─────────────────────────────────────
        const kc = new Gtk.EventControllerKey();
        kc.connect('key-pressed', (_ctrl, keyval) => {
            if (keyval === Gdk.KEY_Escape) { this.close(); return true; }
            if (keyval === Gdk.KEY_Down) {
                // Down from search → favorites if visible+expanded, else main grid
                const target = (this._favSection?.get_visible() && !this._favCollapsed)
                    ? this._favFlow : this._flow;
                target.grab_focus();
                return true;
            }
            return false;
        });
        this._searchEntry.add_controller(kc);

        // ── _favFlow key handler — arrow-key edge detection ──────────────
        // Let GTK handle internal FlowBox navigation.  Only intercept when the
        // selected child is at the boundary of the grid so we can jump to the
        // adjacent widget instead of stopping at the edge.
        const favKc = new Gtk.EventControllerKey();
        favKc.connect('key-pressed', (_ctrl, keyval) => {
            if (keyval === Gdk.KEY_Escape) { this.close(); return true; }

            if (keyval === Gdk.KEY_Down) {
                const idx   = flowSelIdx(this._favFlow);
                const total = flowCount(this._favFlow);
                // Last row starts at the largest multiple of cols ≤ total-1
                const lastRowStart = total > 0 ? Math.floor((total - 1) / cols) * cols : 0;
                if (idx < 0 || idx >= lastRowStart) {
                    this._flow.grab_focus();
                    return true;
                }
            }
            if (keyval === Gdk.KEY_Up) {
                const idx = flowSelIdx(this._favFlow);
                if (idx < 0 || idx < cols) {
                    this._searchEntry.grab_focus();
                    return true;
                }
            }
            // Printable → back to search
            if (keyval === Gdk.KEY_BackSpace ||
                (keyval >= Gdk.KEY_space && keyval <= Gdk.KEY_asciitilde)) {
                this._searchEntry.grab_focus();
                return false;
            }
            return false;
        });
        this._favFlow.add_controller(favKc);

        // ── _flow key handler — arrow-key edge detection ─────────────────
        const flowKc = new Gtk.EventControllerKey();
        flowKc.connect('key-pressed', (_ctrl, keyval) => {
            if (keyval === Gdk.KEY_Escape) { this.close(); return true; }

            if (keyval === Gdk.KEY_Up) {
                const idx = flowSelIdx(this._flow);
                if (idx < 0 || idx < cols) {
                    // At top row — go to favorites if visible, else search
                    if (this._favSection?.get_visible() && !this._favCollapsed)
                        this._favFlow.grab_focus();
                    else
                        this._searchEntry.grab_focus();
                    return true;
                }
            }
            // Printable → back to search
            if (keyval === Gdk.KEY_BackSpace ||
                (keyval >= Gdk.KEY_space && keyval <= Gdk.KEY_asciitilde)) {
                this._searchEntry.grab_focus();
                return false;
            }
            return false;
        });
        this._flow.add_controller(flowKc);

        // ── Window-level ESC handler (fallback for any focused widget) ───
        const winKc = new Gtk.EventControllerKey();
        winKc.connect('key-pressed', (_ctrl, keyval) => {
            if (keyval === Gdk.KEY_Escape) { this.close(); return true; }
            if (keyval === Gdk.KEY_BackSpace ||
                (keyval >= Gdk.KEY_space && keyval <= Gdk.KEY_asciitilde)) {
                this._searchEntry.grab_focus();
                return false;
            }
            return false;
        });
        this.add_controller(winKc);
    }

    /**
     * Close when the launcher window loses compositor focus — gives the
     * same click-outside-to-dismiss behaviour as rofi.
     * Guards:
     *   _popoverOpen      — a context-menu popover is currently visible
     *   _postPopoverGrace — popover just closed; wait 600 ms before allowing
     *                       focus-loss to dismiss (keeps launcher alive after
     *                       "Pin to Dock" which popdowns the menu)
     */
    // ── CSS hot-reload (mirrors dock-main.js setupColorMonitor) ─────────────

    _setupColorMonitor() {
        const file = Gio.File.new_for_path(GTK4_COLORS_PATH);
        try {
            this._colorMonitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
            this._colorMonitor.connect('changed', (_m, _f, _o, ev) => {
                if (ev !== Gio.FileMonitorEvent.CHANGES_DONE_HINT &&
                    ev !== Gio.FileMonitorEvent.CREATED) return;
                if (this._colorReloadTimer) {
                    GLib.source_remove(this._colorReloadTimer);
                    this._colorReloadTimer = 0;
                }
                this._colorReloadTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 300, () => {
                    this._colorReloadTimer = 0;
                    this._loadGlobalCSS();
                    this.queue_draw();
                    return GLib.SOURCE_REMOVE;
                });
            });
        } catch (e) {
            console.warn('[launcher] color monitor setup failed:', e.message);
        }
    }

    _teardownColorMonitor() {
        if (this._colorReloadTimer) {
            GLib.source_remove(this._colorReloadTimer);
            this._colorReloadTimer = 0;
        }
        if (this._colorMonitor) {
            this._colorMonitor.cancel();
            this._colorMonitor = null;
        }
    }

    _setupFocusClose() {
        this._bgWin = null;

        // ── 1. BOTTOM-layer transparent click-catcher ─────────────────────
        // Covers the full screen at the BOTTOM layer (below normal windows but
        // above the desktop). Desktop clicks reach it; window clicks go to the
        // normal window above (launcher stays open for those — user presses ESC
        // or clicks empty space). Hover never reaches it — no hover-close.
        //
        // Using notify::is-active is intentionally avoided: on Hyprland with
        // focus_follows_mouse, is-active fires on pointer-leave (hover), not
        // only on click — causing unwanted hover-close.
        try {
            const bgWin = new Gtk.Window({ decorated: false });
            const thisApp = this.get_application();
            if (thisApp) thisApp.add_window(bgWin);

            Gtk4LayerShell.init_for_window(bgWin);
            Gtk4LayerShell.set_namespace(bgWin, 'hyprcandy-launcher-bg');
            Gtk4LayerShell.set_layer(bgWin, Gtk4LayerShell.Layer.BOTTOM);
            Gtk4LayerShell.set_exclusive_zone(bgWin, -1);
            // Anchor all four edges → covers the full output
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.TOP,    true);
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.BOTTOM, true);
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.LEFT,   true);
            Gtk4LayerShell.set_anchor(bgWin, Gtk4LayerShell.Edge.RIGHT,  true);

            // Fully transparent content — must have a child or GTK won't map it
            bgWin.set_child(new Gtk.Box());
            bgWin.set_opacity(0.002);  // non-zero so the compositor maps the surface

            const bgClick = new Gtk.GestureClick();
            bgClick.connect('pressed', () => {
                // set_visible(false) on the launcher triggers notify::visible
                // which hides bgWin automatically (see handler below).
                this.set_visible(false);
            });
            bgWin.add_controller(bgClick);

            bgWin.set_visible(false);
            this._bgWin = bgWin;
        } catch (e) {
            console.warn('[launcher] click-catcher setup failed:', e.message);
        }

        // Sync bgWin visibility with the launcher — single source of truth.
        // Covers ALL hide paths: ESC, app-tile click, empty-space click,
        // SIGUSR1 hide, and the bgWin click handler above.
        this.connect('notify::visible', () => {
            if (this._bgWin) this._bgWin.set_visible(this.get_visible());
        });

        // ── 2. Empty-space-click-to-close (BUBBLE-phase gesture) ─────────
        // GtkButton and GtkSearchEntry claim their gesture sequences during
        // BUBBLE propagation, denying parent gestures for the same sequence.
        // A GestureClick on the root box therefore only fires when the click
        // lands on blank background / padding that no child widget consumed —
        // i.e. "empty space" inside the launcher frame.
        const rootChild = this.get_child();
        if (rootChild) {
            const emptyClick = new Gtk.GestureClick();
            emptyClick.set_button(1);   // primary / left button only
            emptyClick.connect('released', (_g, _n, x, y) => {
                if (!this.get_visible())                         return;
                if (this._popoverOpen || this._postPopoverGrace) return;
                // pick() returns the deepest widget under the pointer; if it
                // resolves to something other than the root box (or window),
                // an interactive child already claimed the sequence — skip.
                const pick = this.pick(
                    x + rootChild.get_margin_start(),
                    y + rootChild.get_margin_top(),
                    Gtk.PickFlags.DEFAULT
                );
                if (pick && pick !== rootChild && pick !== this) return;
                this.set_visible(false);
            });
            rootChild.add_controller(emptyClick);
        }
    }

    // ── Fix 1: safe favorites clear ──────────────────────────────────────
    // Uses get_first_child() each iteration so GTK4 sibling pointer
    // rebinding after remove() never leaves a stale reference (fixes
    // the single-last-favorite stuck-tile bug).
    _refreshFavorites(query) {
        const q = (query ?? '').toLowerCase().trim();
        while (true) {
            const ch = this._favFlow.get_first_child();
            if (!ch) break;
            this._favFlow.remove(ch);
        }
        const favApps = this._allApps.filter(a =>
            this._favoritesSet.has(a.className) &&
            (!q || a.name.toLowerCase().includes(q))
        );
        this._favSection.set_visible(favApps.length > 0);
        for (const app of favApps)
            this._favFlow.append(this._makeAppTile(app));
    }

}); // end GObject.registerClass(AppLauncherWindow)

// ── Daemon Application (Fix 4) ─────────────────────────────────────────────
// Runs as a persistent daemon. SIGUSR1 (10) toggles visibility.
// The window is never destroyed between toggles — CSS and app-list are kept.

const LauncherApp = GObject.registerClass({
    GTypeName: 'HyprCandyLauncherApp',
}, class LauncherApp extends Gtk.Application {
    vfunc_activate() {
        this._win = new AppLauncherWindow(this);
        this.add_window(this._win);
        // Start hidden; SIGUSR1 will show it on first toggle
        this._win.set_visible(false);

        // SIGUSR1 (10): toggle show/hide.
        // dock-main.js sends pkill -10 -f "gjs app-launcher.js" instead of
        // spawning toggle-app-launcher.sh, which is faster (no shell fork).
        try {
            GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, 10, () => {
                if (this._win.get_visible()) {
                    this._win.set_visible(false);
                } else {
                    // Re-anchor to the current dock edge (user may have cycled
                    // positions since the launcher daemon last showed).
                    this._win._refreshLayerShell();
                    // Refresh running apps and reset search on each show
                    this._win._runningApps = getRunningApps();
                    this._win.set_visible(true);
                    this._win.present();
                    GLib.idle_add(GLib.PRIORITY_HIGH, () => {
                        this._win._searchEntry.set_text('');
                        this._win._refreshFavorites('');
                        this._win._populateApps(this._win._allApps);
                        this._win._searchEntry.grab_focus();
                        return GLib.SOURCE_REMOVE;
                    });
                }
                return GLib.SOURCE_CONTINUE;
            });
        } catch (e) {
            console.warn('[launcher] SIGUSR1 handler failed:', e.message);
        }

        // Keep the application alive indefinitely (daemon mode)
        this.hold();
    }
}); // end GObject.registerClass(LauncherApp)

const app = new LauncherApp({
    application_id: 'org.hyprcandy.AppLauncher',
    // NON_UNIQUE so multiple invocations don't conflict; only one daemon
    // should run at a time — managed by autostart.sh / dock-main.js.
    flags: Gio.ApplicationFlags.NON_UNIQUE,
});

app.run([imports.system.programInvocationName, ...ARGV]);
