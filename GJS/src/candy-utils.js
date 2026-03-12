#!/usr/bin/env gjs

/**
 * Candy Utils Control Center — Compact Start Panel
 * Side-menu navigation, live Cairo background, all controls restored.
 */

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gio = '2.0';
imports.gi.versions.GLib = '2.0';
imports.gi.versions.Gdk = '4.0';
const { Gtk, Gio, GLib, Gdk } = imports.gi;
const GdkPixbuf = imports.gi.GdkPixbuf;
const CairoMod = imports.gi.cairo;

const scriptDir = GLib.path_get_dirname(imports.system.programInvocationName);
imports.searchPath.unshift(scriptDir);

// ─── Config paths ────────────────────────────────────────────────────────────
const HOME = GLib.get_home_dir();
const CONFIG_DIR    = GLib.build_filenamev([HOME, '.config', 'hyprcandy']);
const HYPR_CONF     = GLib.build_filenamev([HOME, '.config', 'hypr', 'hyprviz.conf']);
const WAYBAR_STYLE  = GLib.build_filenamev([HOME, '.config', 'waybar', 'style.css']);
const WAYBAR_CONF   = GLib.build_filenamev([HOME, '.config', 'waybar', 'config.jsonc']);
const SWAYNC_STYLE  = GLib.build_filenamev([HOME, '.config', 'swaync', 'style.css']);
const ROFI_BORDER   = GLib.build_filenamev([HOME, '.config', 'hyprcandy', 'settings', 'rofi-border.rasi']);
const ROFI_RADIUS   = GLib.build_filenamev([HOME, '.config', 'hyprcandy', 'settings', 'rofi-border-radius.rasi']);
const WAYPAPER_INT  = GLib.build_filenamev([HOME, '.config', 'hyprcandy', 'hooks', 'waypaper_integration.sh']);
const DOCK_CONFIG   = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'config.js']);
const DOCK_CYCLE    = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'cycle.sh']);
const SDDM_THEME    = '/usr/share/sddm/themes/sugar-candy/theme.conf';

try { GLib.mkdir_with_parents(CONFIG_DIR, 0o755); } catch (e) {}

// ─── State helpers ───────────────────────────────────────────────────────────
function loadState(f, def) {
    try {
        let [ok, c] = GLib.file_get_contents(GLib.build_filenamev([CONFIG_DIR, f]));
        if (ok && c) return imports.byteArray.toString(c).trim();
    } catch (e) {}
    return def || '';
}
function saveState(f, v) {
    try { GLib.file_set_contents(GLib.build_filenamev([CONFIG_DIR, f]), v.toString()); } catch (e) {}
}
function loadBool(f, def) { return loadState(f, def ? 'enabled' : 'disabled') === 'enabled'; }
function saveBool(f, v) { saveState(f, v ? 'enabled' : 'disabled'); }

// ─── UI builder helpers ──────────────────────────────────────────────────────
function mkRow(parent, label, ...widgets) {
    const row = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, spacing: 4, margin_top: 1, margin_bottom: 1 });
    widgets.forEach(w => row.append(w));
    const lbl = Gtk.Label.new(label);
    lbl.add_css_class('cc-label');
    lbl.set_halign(Gtk.Align.START);
    row.append(lbl);
    parent.append(row);
    return row;
}

function mkEntry(width) {
    const e = new Gtk.Entry({ width_chars: width || 5, halign: Gtk.Align.START, max_width_chars: 5 });
    e.add_css_class('cc-entry');
    return e;
}

function mkBtn(label) {
    const b = new Gtk.Button({ label });
    b.add_css_class('cc-btn');
    return b;
}

function mkToggle(label, active) {
    const b = mkBtn(label);
    if (active) b.add_css_class('cc-active');
    return b;
}

function mkPM() {
    const dec = mkBtn('−'); dec.add_css_class('cc-pm');
    const inc = mkBtn('+'); inc.add_css_class('cc-pm');
    return [dec, inc];
}

function mkHeading(parent, text) {
    const lbl = Gtk.Label.new(text);
    lbl.add_css_class('cc-heading');
    lbl.set_halign(Gtk.Align.START);
    lbl.set_margin_top(4);
    lbl.set_margin_bottom(2);
    parent.append(lbl);
}

// ─── Dock config.js read/write (hyprcandy-dock) ─────────────────────────────
function readDockVal(key, isStr) {
    try {
        let [ok, c] = GLib.file_get_contents(DOCK_CONFIG);
        if (ok && c) {
            let txt = imports.byteArray.toString(c);
            let m = txt.match(new RegExp(`^\\s*${key}:\\s*([^,\\n]+)`, 'm'));
            if (m) { let v = m[1].trim(); return isStr ? v.replace(/['"]/g, '') : v; }
        }
    } catch (e) {}
    return '';
}

function writeDockVal(key, value, isStr) {
    try {
        let [ok, c] = GLib.file_get_contents(DOCK_CONFIG);
        if (ok && c) {
            let txt = imports.byteArray.toString(c);
            let nv = isStr ? `'${value}'` : value;
            txt = txt.replace(new RegExp(`(^\\s*${key}:\\s*)([^,\\n]+)`, 'm'), `$1${nv}`);
            GLib.file_set_contents(DOCK_CONFIG, txt);
            GLib.spawn_command_line_async('pkill -SIGUSR2 -f "gjs dock-main.js"');
        }
    } catch (e) {}
}

function readDockPosMargin(pos, key, def) {
    try {
        let [ok, c] = GLib.file_get_contents(DOCK_CONFIG);
        if (ok && c) {
            let txt = imports.byteArray.toString(c);
            // Find the positionOverrides block, then the position sub-block
            let overrides = txt.match(/positionOverrides\s*:\s*\{([\s\S]*?)\n    \}/);
            if (overrides) {
                // Within overrides, find the specific position block
                let posBlk = overrides[1].match(new RegExp(pos + '\\s*:\\s*\\{([^}]*?)\\}'));
                if (posBlk) {
                    let m = posBlk[1].match(new RegExp(key + '\\s*:\\s*([0-9.]+)'));
                    if (m) return m[1];
                }
            }
            // Fallback: check base-level value
            let baseM = txt.match(new RegExp('^\\s*' + key + '\\s*:\\s*([0-9.]+)', 'm'));
            if (baseM) return baseM[1];
        }
    } catch (e) {}
    return def;
}

function writeDockPosMargin(pos, key, val) {
    try {
        let [ok, c] = GLib.file_get_contents(DOCK_CONFIG);
        if (ok && c) {
            let txt = imports.byteArray.toString(c);
            // Try to find the key inside the position's override block
            // Match: positionOverrides: { ... pos: { ... key: N ... } ... }
            let re = new RegExp(`(${pos}:\\s*\\{[^}]*?)(${key}:\\s*)([0-9.]+)`);
            let m = txt.match(re);
            if (m) {
                txt = txt.replace(re, `$1$2${val}`);
            } else {
                // Key doesn't exist in the position block — inject it
                let posRe = new RegExp(`(${pos}:\\s*\\{)`);
                if (txt.match(posRe)) {
                    txt = txt.replace(posRe, `$1\n            ${key}: ${val},`);
                } else {
                    // Position block doesn't exist — create it inside positionOverrides
                    txt = txt.replace(/(positionOverrides:\s*\{)/, `$1\n        ${pos}: {\n            ${key}: ${val},\n        },`);
                }
            }
            GLib.file_set_contents(DOCK_CONFIG, txt);
            GLib.spawn_command_line_async('pkill -SIGUSR2 -f "gjs dock-main.js"');
            GLib.spawn_command_line_async('hyprctl reload');
        }
    } catch (e) {}
}

// ─── User Profile Section ────────────────────────────────────────────────────
function createUserProfile() {
    const box = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        halign: Gtk.Align.CENTER, valign: Gtk.Align.START,
        margin_top: 6, margin_bottom: 4 });

    const AVATAR_SZ = 56;
    const userIconPath = GLib.build_filenamev([CONFIG_DIR, 'user-icon.png']);
    let avatarPixbuf = null;

    function loadIcon() {
        try {
            if (GLib.file_test(userIconPath, GLib.FileTest.EXISTS))
                avatarPixbuf = GdkPixbuf.Pixbuf.new_from_file_at_scale(userIconPath, AVATAR_SZ, AVATAR_SZ, false);
            else avatarPixbuf = null;
        } catch (e) { avatarPixbuf = null; }
    }
    loadIcon();

    const avatarDa = new Gtk.DrawingArea();
    avatarDa.set_size_request(AVATAR_SZ, AVATAR_SZ);
    avatarDa.set_content_width(AVATAR_SZ);
    avatarDa.set_content_height(AVATAR_SZ);
    avatarDa.set_can_target(false);
    avatarDa.set_halign(Gtk.Align.CENTER);

    avatarDa.set_draw_func((_da, cr, w, h) => {
        const r = Math.min(w, h) / 2;
        cr.arc(w / 2, h / 2, r, 0, 2 * Math.PI);
        cr.clip();
        if (avatarPixbuf) {
            const CairoGdk = imports.gi.Gdk;
            CairoGdk.cairo_set_source_pixbuf(cr, avatarPixbuf, (w - AVATAR_SZ) / 2, (h - AVATAR_SZ) / 2);
            cr.paint();
        } else {
            cr.setSourceRGBA(0.5, 0.5, 0.5, 0.25);
            cr.paint();
            cr.setSourceRGBA(1, 1, 1, 0.5);
            cr.arc(w / 2, h / 2 - 4, 10, 0, 2 * Math.PI);
            cr.fill();
            cr.arc(w / 2, h / 2 + 16, 16, Math.PI, 0);
            cr.fill();
        }
    });

    const iconBtn = Gtk.Button.new();
    iconBtn.add_css_class('cc-avatar-btn');
    iconBtn.set_child(avatarDa);
    iconBtn.connect('clicked', () => {
        const dlg = new Gtk.FileChooserNative({ title: 'Select User Icon', action: Gtk.FileChooserAction.OPEN, modal: true });
        const filt = Gtk.FileFilter.new(); filt.set_name('Images'); filt.add_mime_type('image/*'); dlg.add_filter(filt);
        dlg.connect('response', (d, r) => {
            if (r === Gtk.ResponseType.ACCEPT) {
                const p = d.get_file().get_path();
                GLib.spawn_command_line_async(`magick "${p}" -resize 128x128^ -gravity center -extent 128x128 "${userIconPath}"`);
                GLib.timeout_add(GLib.PRIORITY_DEFAULT, 600, () => { loadIcon(); avatarDa.queue_draw(); return false; });
            }
        });
        dlg.show();
    });
    box.append(iconBtn);

    const unFile = GLib.build_filenamev([CONFIG_DIR, 'username.txt']);
    let un = GLib.get_user_name();
    try { let [ok, c] = GLib.file_get_contents(unFile); if (ok && c) { let s = imports.byteArray.toString(c).trim(); if (s) un = s; } } catch (e) {}
    const nameLbl = Gtk.Label.new(un);
    nameLbl.add_css_class('cc-username');
    box.append(nameLbl);

    return box;
}

// ═══════════════════════════════════════════════════════════════════════════════
// PANELS
// ═══════════════════════════════════════════════════════════════════════════════

// ─── Themes Panel ────────────────────────────────────────────────────────────
function createThemesPanel() {
    const panel = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        margin_start: 6, margin_end: 6, margin_top: 6, margin_bottom: 6 });
    mkHeading(panel, '󰔎 Matugen Themes');

    const schemeMap = {
        'Light': 'scheme-fidelity', 'Dark': 'scheme-monochrome', 'Content': 'scheme-content',
        'Expressive': 'scheme-expressive', 'Neutral': 'scheme-neutral', 'Rainbow': 'scheme-rainbow',
        'Tonal-spot': 'scheme-tonal-spot', 'Fruit-salad': 'scheme-fruit-salad', 'Vibrant': 'scheme-vibrant'
    };
    let current = loadState('matugen-state', 'scheme-content');
    const btns = [];

    const gtk3File = GLib.build_filenamev([HOME, '.config', 'matugen', 'templates', 'gtk3.css']);
    const gtk4File = GLib.build_filenamev([HOME, '.config', 'matugen', 'templates', 'gtk4.css']);
    const waybarFile = WAYBAR_STYLE;
    const dockFile = GLib.build_filenamev([HOME, '.config', 'nwg-dock-hyprland', 'style.css']);
    const swayncFile = SWAYNC_STYLE;

    function apply(name) {
        const scheme = schemeMap[name]; if (!scheme) return;
        GLib.spawn_command_line_async(`sed -i 's/--type scheme-[^ ]*/--type ${scheme}/' '${WAYPAPER_INT}'`);

        if (name === 'Light') {
            GLib.spawn_command_line_async(`sed -i 's/-m dark/-m light/g' '${WAYPAPER_INT}'`);
            GLib.file_set_contents('/tmp/hyprcandy-gtk.sh',
                `#!/bin/sh\nsed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @primary_fixed_dim;/' '${gtk3File}'\n` +
                `sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @inverse_primary;/' '${gtk3File}'\n` +
                `sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @primary_fixed_dim;/' '${gtk4File}'\n` +
                `sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @inverse_primary;/' '${gtk4File}'\n`);
            GLib.spawn_command_line_async('sh /tmp/hyprcandy-gtk.sh');
            GLib.spawn_command_line_async(`sed -i 's/color: @primary_fixed_dim;/color: @primary;/g' '${waybarFile}'`);
            GLib.spawn_command_line_async(`sed -i 's/@inverse_primary, @scrim/@inverse_primary, @primary_fixed_dim/g' '${waybarFile}'`);
            GLib.spawn_command_line_async(`sed -i '8s/@primary_fixed_dim;/@inverse_primary;/g' '${dockFile}'`);
            GLib.spawn_command_line_async(`sed -i '60s/@background;/@buttoncolor;/g; 68s/@bordercolor;/@background;/g' '${swayncFile}'`);
            GLib.spawn_command_line_async(`sed -i '59s/color: .*;/color: @primary_fixed_dim;/g; 103s/color: .*;/color: @primary_fixed_dim;/g; 519s/color: .*;/color: @primary_fixed_dim;/g;' '${waybarFile}'`);
        } else if (name === 'Dark') {
            GLib.spawn_command_line_async(`sed -i 's/-m light/-m dark/g' '${WAYPAPER_INT}'`);
            GLib.file_set_contents('/tmp/hyprcandy-gtk.sh',
                `#!/bin/sh\nsed -i 's/@on_secondary/@on_primary_fixed_variant/g' '${gtk3File}'\n` +
                `sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_primary_fixed_variant;/' '${gtk3File}'\n` +
                `sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' '${gtk3File}'\n` +
                `sed -i 's/@on_secondary/@on_primary_fixed_variant/g' '${gtk4File}'\n` +
                `sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_primary_fixed_variant;/' '${gtk4File}'\n` +
                `sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' '${gtk4File}'\n`);
            GLib.spawn_command_line_async('sh /tmp/hyprcandy-gtk.sh');
            GLib.spawn_command_line_async(`sed -i 's/color: @primary;/color: @primary_fixed_dim;/g' '${waybarFile}'`);
            GLib.spawn_command_line_async(`sed -i 's/@inverse_primary, @primary_fixed_dim/@inverse_primary, @scrim/g' '${waybarFile}'`);
            GLib.spawn_command_line_async(`sed -i '8s/@primary_fixed_dim;/@inverse_primary;/g' '${dockFile}'`);
            GLib.spawn_command_line_async(`sed -i '60s/@buttoncolor;/@background;/g; 68s/@background;/@bordercolor;/g' '${swayncFile}'`);
            GLib.spawn_command_line_async(`sed -i '59s/color: .*;/color: @secondary_container;/g; 103s/color: .*;/color: @secondary_container;/g; 519s/color: .*;/color: @secondary_container;/g;' '${waybarFile}'`);
        } else {
            // All other dark-mode schemes share the same sed logic
            GLib.spawn_command_line_async(`sed -i 's/-m light/-m dark/g' '${WAYPAPER_INT}'`);
            GLib.file_set_contents('/tmp/hyprcandy-gtk.sh',
                `#!/bin/sh\nsed -i 's/@on_primary_fixed_variant/@on_secondary/g' '${gtk3File}'\n` +
                `sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_secondary;/' '${gtk3File}'\n` +
                `sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' '${gtk3File}'\n` +
                `sed -i 's/@on_primary_fixed_variant/@on_secondary/g' '${gtk4File}'\n` +
                `sed -i 's/@define-color dialog_bg_color .*;/@define-color dialog_bg_color @on_secondary;/' '${gtk4File}'\n` +
                `sed -i 's/@define-color dialog_fg_color .*;/@define-color dialog_fg_color @primary;/' '${gtk4File}'\n`);
            GLib.spawn_command_line_async('sh /tmp/hyprcandy-gtk.sh');
            GLib.spawn_command_line_async(`sed -i 's/@inverse_primary, @primary_fixed_dim/@inverse_primary, @scrim/g' '${waybarFile}'`);
            GLib.spawn_command_line_async(`sed -i '8s/@primary_fixed_dim;/@inverse_primary;/g' '${dockFile}'`);
            GLib.spawn_command_line_async(`sed -i '60s/@buttoncolor;/@background;/g; 68s/@background;/@bordercolor;/g' '${swayncFile}'`);
            GLib.spawn_command_line_async(`sed -i '59s/color: .*;/color: @secondary_container;/g; 103s/color: .*;/color: @secondary_container;/g; 519s/color: .*;/color: @secondary_container;/g;' '${waybarFile}'`);
        }

        GLib.spawn_command_line_async("bash -c '$HOME/.config/hyprcandy/hooks/waypaper_integration.sh'");
        saveState('matugen-state', scheme);
        current = scheme;
        btns.forEach((b, i) => {
            if (schemeMap[Object.keys(schemeMap)[i]] === current) b.add_css_class('cc-active');
            else b.remove_css_class('cc-active');
        });
    }

    // Stack theme buttons vertically, one per row
    Object.keys(schemeMap).forEach((name) => {
        const b = mkBtn(name);
        if (schemeMap[name] === current) b.add_css_class('cc-active');
        b.connect('clicked', () => apply(name));
        btns.push(b);
        panel.append(b);
    });
    return panel;
}

// ─── Waybar Panel ────────────────────────────────────────────────────────────
function createWaybarPanel() {
    const panel = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        margin_start: 6, margin_end: 6, margin_top: 6, margin_bottom: 6 });
    mkHeading(panel, '󱟛 Bar');

    // Islands/Bar toggle
    let islands = loadState('waybar-islands.state', 'bar') === 'islands';
    const islandBtn = mkToggle(islands ? 'Mode: 󰇘' : 'Mode: 󱟛', islands);
    islandBtn.connect('clicked', () => {
        islands = !islands;
        const bs = loadState('waybar_border_size.state', '2');
        if (islands) {
            GLib.spawn_command_line_async(`sed -i '25s/background: @blur_background;/background: none;/' '${WAYBAR_STYLE}'`);
            GLib.spawn_command_line_async(`sed -i '32s/border: ${bs}px solid @on_primary_fixed_variant;/border: 0px solid @on_primary_fixed_variant;/' '${WAYBAR_STYLE}'`);
            islandBtn.set_label('Mode: 󰇘'); islandBtn.add_css_class('cc-active');
        } else {
            GLib.spawn_command_line_async(`sed -i '25s/background: none;/background: @blur_background;/' '${WAYBAR_STYLE}'`);
            GLib.spawn_command_line_async(`sed -i '32s/border: 0px solid @on_primary_fixed_variant;/border: ${bs}px solid @on_primary_fixed_variant;/' '${WAYBAR_STYLE}'`);
            islandBtn.set_label('Mode: 󱟛'); islandBtn.remove_css_class('cc-active');
        }
        saveState('waybar-islands.state', islands ? 'islands' : 'bar');
    });

    // Position toggle
    let bottom = loadState('waybar-position.txt', 'top') === 'bottom';
    const posBtn = mkToggle(bottom ? 'Pos: 󰅀' : 'Pos: 󰅃', bottom);
    posBtn.connect('clicked', () => {
        bottom = !bottom;
        const rofi1 = GLib.build_filenamev([HOME, '.config', 'rofi', 'bluetooth-menu.rasi']);
        const rofi2 = GLib.build_filenamev([HOME, '.config', 'rofi', 'power-menu.rasi']);
        const rofi3 = GLib.build_filenamev([HOME, '.config', 'rofi', 'wifi-menu.rasi']);
        if (bottom) {
            GLib.spawn_command_line_async(`sed -i '5s/"position": "top",/"position": "bottom",/' '${WAYBAR_CONF}'`);
            [rofi1, rofi2, rofi3].forEach(f => GLib.spawn_command_line_async(`sed -i 's/location:                 north;/location:                 south;/' '${f}'`));
            posBtn.set_label('Pos: 󰅀'); posBtn.add_css_class('cc-active');
        } else {
            GLib.spawn_command_line_async(`sed -i '5s/"position": "bottom",/"position": "top",/' '${WAYBAR_CONF}'`);
            [rofi1, rofi2, rofi3].forEach(f => GLib.spawn_command_line_async(`sed -i 's/location:                 south;/location:                 north;/' '${f}'`));
            posBtn.set_label('Pos: 󰅃'); posBtn.remove_css_class('cc-active');
        }
        GLib.spawn_command_line_async('systemctl --user restart waybar.service');
        saveState('waybar-position.txt', bottom ? 'bottom' : 'top');
    });

    const toggleRow = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, spacing: 3 });
    islandBtn.set_hexpand(true); posBtn.set_hexpand(true);
    toggleRow.append(islandBtn); toggleRow.append(posBtn);
    panel.append(toggleRow);

    // Border
    const borderE = mkEntry(3);
    borderE.set_text(loadState('waybar_border_size.state', '2'));
    borderE.connect('activate', () => {
        const n = parseInt(borderE.get_text());
        if (!isNaN(n) && n >= 0 && n <= 10) {
            try {
                let [ok, c] = GLib.file_get_contents(WAYBAR_STYLE);
                if (ok && c) {
                    let txt = imports.byteArray.toString(c);
                    let m = txt.match(/border:\s*([0-9]+)px\s*solid\s*@on_primary_fixed_variant;/);
                    if (m) GLib.spawn_command_line_async(`sed -i '32s/border: ${m[1]}px solid @on_primary_fixed_variant;/border: ${n}px solid @on_primary_fixed_variant;/' '${WAYBAR_STYLE}'`);
                }
            } catch (e) {}
            saveState('waybar_border_size.state', n.toString());
        }
    });
    mkRow(panel, 'Border', borderE);

    // Padding
    const padE = mkEntry(3);
    padE.set_text(loadState('waybar_padding.state', '3.5'));
    padE.connect('activate', () => {
        const v = parseFloat(padE.get_text());
        if (!isNaN(v) && v >= 0 && v <= 10) {
            const vs = v.toFixed(1);
            try {
                let [ok, c] = GLib.file_get_contents(WAYBAR_STYLE);
                if (ok && c) {
                    let m = imports.byteArray.toString(c).match(/padding: ([0-9.]+)px;/);
                    if (m) GLib.spawn_command_line_async(`sed -i '31s/padding: ${m[1]}px;/padding: ${vs}px;/' '${WAYBAR_STYLE}'`);
                }
            } catch (e) {}
            saveState('waybar_padding.state', vs);
        }
    });
    mkRow(panel, 'Padding', padE);

    // Radius
    const radE = mkEntry(3);
    radE.set_text(loadState('waybar_outer_radius.state', '20.0'));
    radE.connect('activate', () => {
        const v = parseFloat(radE.get_text());
        if (!isNaN(v) && v >= 0 && v <= 40) {
            const vs = v.toFixed(1);
            GLib.spawn_command_line_async(`sed -i '30s/border-radius: [0-9.]*px;/border-radius: ${vs}px;/' '${WAYBAR_STYLE}'`);
            GLib.spawn_command_line_async(`sed -i '19s/border-radius: [0-9.]*px;/border-radius: ${vs}px;/' '${WAYBAR_STYLE}'`);
            saveState('waybar_outer_radius.state', vs);
        }
    });
    mkRow(panel, 'Radius', radE);

    // Side Margins
    const sideE = mkEntry(3);
    sideE.set_text(loadState('waybar_side_margin.state', '4.5'));
    sideE.connect('activate', () => {
        const v = parseFloat(sideE.get_text());
        if (!isNaN(v) && v >= 0 && v <= 200) {
            const vs = v.toFixed(1);
            GLib.spawn_command_line_async(`sed -i '27s/margin-left: [0-9.]*px;/margin-left: ${vs}px;/' '${WAYBAR_STYLE}'`);
            GLib.spawn_command_line_async(`sed -i '28s/margin-right: [0-9.]*px;/margin-right: ${vs}px;/' '${WAYBAR_STYLE}'`);
            saveState('waybar_side_margin.state', vs);
        }
    });
    mkRow(panel, 'Sides', sideE);

    // Top Margin
    const topE = mkEntry(3);
    topE.set_text(loadState('waybar_top_margin.state', '4.5'));
    topE.connect('activate', () => {
        const v = parseFloat(topE.get_text());
        if (!isNaN(v) && v >= 0 && v <= 20) {
            const vs = v.toFixed(1);
            GLib.spawn_command_line_async(`sed -i '26s/margin-top: [0-9.]*px;/margin-top: ${vs}px;/' '${WAYBAR_STYLE}'`);
            saveState('waybar_top_margin.state', vs);
        }
    });
    mkRow(panel, 'Top', topE);

    // Bottom Margin
    const botE = mkEntry(3);
    botE.set_text(loadState('waybar_bottom_margin.state', '0.0'));
    botE.connect('activate', () => {
        const v = parseFloat(botE.get_text());
        if (!isNaN(v) && v >= 0 && v <= 20) {
            const vs = v.toFixed(1);
            GLib.spawn_command_line_async(`sed -i '29s/margin-bottom: [0-9.]*px;/margin-bottom: ${vs}px;/' '${WAYBAR_STYLE}'`);
            saveState('waybar_bottom_margin.state', vs);
        }
    });
    mkRow(panel, 'Bottom', botE);

    // Start Icon — targets distro "default" icon on line 230 of config.jsonc
    const distroE = mkEntry(5);
    function loadDistroIcon() {
        // Prefer state file (written by candy-utils, read by waybar-distro-icon.sh)
        try {
            const stateFile = GLib.build_filenamev([HOME, '.config', 'hyprcandy', 'waybar-start-icon.txt']);
            let [ok, c] = GLib.file_get_contents(stateFile);
            if (ok && c) {
                const icon = imports.byteArray.toString(c).trim();
                if (icon) return icon;
            }
        } catch (e) {}
        // Fall back to reading config.jsonc line 230 (initial / legacy)
        try {
            let [ok, c] = GLib.file_get_contents(WAYBAR_CONF);
            if (ok && c) {
                let lines = imports.byteArray.toString(c).split('\n');
                if (lines.length >= 230) {
                    let m = lines[229].match(/"default":\s*"([^"]*)"/);
                    if (m) return m[1].trim();
                }
            }
        } catch (e) {}
        return '';
    }
    distroE.set_text(loadDistroIcon());
    distroE.connect('activate', () => {
        const icon = distroE.get_text();
        if (!icon) return;
        // Write state file — waybar-distro-icon.sh polls this and re-emits on SIGRTMIN+9
        const stateDir = GLib.build_filenamev([HOME, '.config', 'hyprcandy']);
        GLib.mkdir_with_parents(stateDir, 0o755);
        const stateFile = GLib.build_filenamev([stateDir, 'waybar-start-icon.txt']);
        GLib.file_set_contents(stateFile, icon);
        // Signal waybar to re-run the exec script — no restart needed
        GLib.spawn_command_line_async('pkill -SIGRTMIN+9 waybar');
    });
    mkRow(panel, 'Start Icon', distroE);

    // Workspace Icons — active, empty, persistent (persistent shared with 6-10)
    mkHeading(panel, '  Workspaces');

    function loadWsIcon(key) {
        try {
            let [ok, c] = GLib.file_get_contents(WAYBAR_CONF);
            if (ok && c) {
                let m = imports.byteArray.toString(c).match(new RegExp('"' + key + '":\\s*"([^"]*)"'));
                if (m) return m[1];
            }
        } catch (e) {}
        return '';
    }

    function writeWsIcon(key, icon) {
        // Update all occurrences of "key": "..." in config.jsonc
        GLib.spawn_command_line_async(
            `sed -i 's/"${key}": "[^"]*"/"${key}": "${icon}"/g' '${WAYBAR_CONF}'`
        );
        // If updating persistent, also apply to workspaces 6-10
        if (key === 'persistent') {
            for (let n = 6; n <= 10; n++) {
                GLib.spawn_command_line_async(
                    `sed -i 's/"${n}": "[^"]*"/"${n}": "${icon}"/g' '${WAYBAR_CONF}'`
                );
            }
        }
        // Reload waybar config without restarting the service — no flicker
        GLib.spawn_command_line_async('killall -SIGUSR2 waybar');
    }

    const wsIcons = [
        ['Active', 'active'],
        ['Empty', 'empty'],
        ['Persistent', 'persistent'],
    ];
    wsIcons.forEach(([label, key]) => {
        const e = mkEntry(5);
        e.set_text(loadWsIcon(key));
        e.connect('activate', () => { if (e.get_text() !== null) writeWsIcon(key, e.get_text()); });
        mkRow(panel, label, e);
    });

    return panel;
}

// ─── Hyprland Panel ──────────────────────────────────────────────────────────
function createHyprlandPanel() {
    const panel = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        margin_start: 6, margin_end: 6, margin_top: 6, margin_bottom: 6 });
    mkHeading(panel, ' Hyprland');

    // Hyprsunset toggle
    let sunsetOn = loadBool('hyprsunset.state', false);
    const sunsetBtn = mkToggle(sunsetOn ? 'Hyprsunset 󰌵' : 'Hyprsunset 󰌶', sunsetOn);
    sunsetBtn.connect('clicked', () => {
        sunsetOn = !sunsetOn;
        if (sunsetOn) {
            GLib.spawn_command_line_async("bash -c 'hyprsunset &'");
            sunsetBtn.set_label('Hyprsunset 󰌵'); sunsetBtn.add_css_class('cc-active');
        } else {
            GLib.spawn_command_line_async('pkill hyprsunset');
            sunsetBtn.set_label('Hyprsunset 󰌶'); sunsetBtn.remove_css_class('cc-active');
        }
        saveBool('hyprsunset.state', sunsetOn);
    });

    panel.append(sunsetBtn);

    // Gamma +/−
    const gammaRow = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, spacing: 3 });
    const gammaDec = mkBtn('γ −10'); gammaDec.set_hexpand(true);
    const gammaInc = mkBtn('γ +10'); gammaInc.set_hexpand(true);
    gammaDec.connect('clicked', () => GLib.spawn_command_line_async('hyprctl hyprsunset gamma -10'));
    gammaInc.connect('clicked', () => GLib.spawn_command_line_async('hyprctl hyprsunset gamma +10'));
    gammaRow.append(gammaDec); gammaRow.append(gammaInc);
    panel.append(gammaRow);

    // Hyprpicker
    const pickerBtn = mkBtn('󰈊  Hyprpicker');
    pickerBtn.connect('clicked', () => GLib.spawn_command_line_async('hyprpicker'));
    panel.append(pickerBtn);

    // X-Ray toggle — sentinel file is the single source of truth, matching xray.sh
const XRAY_SENTINEL = GLib.build_filenamev([HOME, '.config', 'hyprcandy', 'settings', 'xray-on']);
let xrayOn = GLib.file_test(XRAY_SENTINEL, GLib.FileTest.EXISTS);
const xrayBtn = mkToggle(xrayOn ? 'X-Ray  On' : 'X-Ray  Off', xrayOn);
xrayBtn.connect('clicked', () => {
    GLib.spawn_command_line_async(`bash ${HOME}/.config/hypr/scripts/xray.sh`);
    // Re-read sentinel after script runs — file exists = on
    xrayOn = !xrayOn;
    xrayBtn.set_label(xrayOn ? 'X-Ray  On' : 'X-Ray  Off');
    if (xrayOn) xrayBtn.add_css_class('cc-active');
    else xrayBtn.remove_css_class('cc-active');
});
panel.append(xrayBtn);
    
    // Opacity toggle
    let opacOn = loadBool('opacity.state', false);
    const opacBtn = mkToggle(opacOn ? 'Opacity On' : 'Opacity Off', opacOn);
    opacBtn.connect('clicked', () => {
        opacOn = !opacOn;
        GLib.spawn_command_line_async('bash -c "$HOME/.config/hypr/scripts/window-opacity.sh"');
        opacBtn.set_label(opacOn ? 'Opacity On' : 'Opacity Off');
        if (opacOn) opacBtn.add_css_class('cc-active'); else opacBtn.remove_css_class('cc-active');
        saveBool('opacity.state', opacOn);
    });
    panel.append(opacBtn);

    // Opacity +/− (sets both active and inactive uniformly)
    const [aoDec, aoInc] = mkPM();
    function updateOpacity(delta) {
        try {
            let [ok, c] = GLib.file_get_contents(HYPR_CONF);
            if (ok && c) {
                let txt = imports.byteArray.toString(c);
                let m = txt.match(/active_opacity = ([0-9.]+)/);
                if (m) {
                    let v = Math.max(0, Math.min(1, parseFloat(m[1]) + delta * 0.05)).toFixed(2);
                    GLib.spawn_command_line_async(`sed -i 's/active_opacity = .*/active_opacity = ${v}/' "${HYPR_CONF}"`);
                    GLib.spawn_command_line_async(`sed -i 's/inactive_opacity = .*/inactive_opacity = ${v}/' "${HYPR_CONF}"`);
                    GLib.spawn_command_line_async('hyprctl reload');
                }
            }
        } catch (e) {}
    }
    aoDec.connect('clicked', () => updateOpacity(-1));
    aoInc.connect('clicked', () => updateOpacity(1));
    mkRow(panel, 'Opacity', aoDec, aoInc);

    // Blur Size +/−
    const [bsDec, bsInc] = mkPM();
    function updateBlur(key, delta) {
        try {
            let [ok, c] = GLib.file_get_contents(HYPR_CONF);
            if (ok && c) {
                let txt = imports.byteArray.toString(c);
                let blk = txt.match(/blur \{[\s\S]*?\}/);
                if (blk) {
                    let m = blk[0].match(new RegExp(key + ' = ([0-9]+)'));
                    if (m) {
                        let cur = parseInt(m[1]), nv = Math.max(0, cur + delta);
                        if (key === 'size')
                            GLib.spawn_command_line_async(`sed -i '/blur {/,/}/{s/size = ${cur}/size = ${nv}/}' '${HYPR_CONF}'`);
                        else
                            GLib.spawn_command_line_async(`sed -i 's/passes = ${cur}/passes = ${nv}/' '${HYPR_CONF}'`);
                        GLib.spawn_command_line_async('hyprctl reload');
                    }
                }
            }
        } catch (e) {}
    }
    bsDec.connect('clicked', () => updateBlur('size', -1));
    bsInc.connect('clicked', () => updateBlur('size', 1));
    mkRow(panel, 'Blur Size', bsDec, bsInc);

    const [bpDec, bpInc] = mkPM();
    bpDec.connect('clicked', () => updateBlur('passes', -1));
    bpInc.connect('clicked', () => updateBlur('passes', 1));
    mkRow(panel, 'Blur Passes', bpDec, bpInc);

    // Hyprland Gap Presets — stacked vertically
    mkHeading(panel, '  Gap Presets');
    ['minimal', 'balanced', 'spacious', 'zero'].forEach((p) => {
        const b = mkBtn(p.charAt(0).toUpperCase() + p.slice(1));
        b.connect('clicked', () => GLib.spawn_command_line_async(`bash -c '$HOME/.config/hyprcandy/hooks/hyprland_gap_presets.sh ${p}'`));
        panel.append(b);
    });

    return panel;
}

// ─── Dock Panel (hyprcandy-dock) ─────────────────────────────────────────────
function createDockPanel() {
    const panel = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        margin_start: 6, margin_end: 6, margin_top: 6, margin_bottom: 6 });
    mkHeading(panel, '󰞒 Dock');

    // Cycle position
    const cycleBtn = mkBtn('󰶘 Cycle Position');
    cycleBtn.connect('clicked', () => GLib.spawn_command_line_async(`bash "${DOCK_CYCLE}"`));
    panel.append(cycleBtn);

    // Universal settings — all fields hot-reload via SIGUSR2, EXCEPT appIconSize
    // which requires a full dock restart because Gtk.Image pixel_size is set once
    // at widget construction time and cannot be changed at runtime.
    // appIconSize is handled separately below.
    const fields = [
        ['Spacing',  'buttonSpacing', false, 0, 30],
        ['Padding',  'innerPadding',  false, 0, 30],
        ['Border W', 'borderWidth',   false, 0, 10],
        ['Border R', 'borderRadius',  false, 0, 100],
    ];
    fields.forEach(([label, key, isStr, lo, hi]) => {
        const e = mkEntry(3);
        e.set_text(readDockVal(key, isStr));
        e.connect('activate', () => {
            const n = parseInt(e.get_text());
            if (!isNaN(n) && n >= lo && n <= hi) writeDockVal(key, n, isStr);
        });
        mkRow(panel, label, e);
    });

    // Icon Size — writes config then toggle.sh × 2 (hide → 1 s sleep → re-launch)
    // because Gtk.Image pixel_size is baked in at construction; SIGUSR2 can't resize images.
    const DOCK_TOGGLE = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'toggle.sh']);
    const iconSizeE = mkEntry(3);
    iconSizeE.set_text(readDockVal('appIconSize', false));
    iconSizeE.connect('activate', () => {
        const n = parseInt(iconSizeE.get_text());
        if (!isNaN(n) && n >= 12 && n <= 64) {
            writeDockVal('appIconSize', n, false);
            // toggle.sh hides the dock on first call and re-launches on second.
            // We call it once immediately, wait 1 s, then call it again.
            GLib.spawn_command_line_async(`bash "${DOCK_TOGGLE}"`);
            GLib.timeout_add(GLib.PRIORITY_DEFAULT, 1000, () => {
                GLib.spawn_command_line_async(`bash "${DOCK_TOGGLE}"`);
                return GLib.SOURCE_REMOVE;
            });
        }
    });
    mkRow(panel, 'Icon Size', iconSizeE);

    // Start icon
    const sE = mkEntry(3);
    sE.set_text(readDockVal('startIcon', true) || '󱗼');
    sE.connect('activate', () => { if (sE.get_text()) writeDockVal('startIcon', sE.get_text(), true); });
    mkRow(panel, 'Start Icon', sE);

    return panel;
}

// ─── Swaync Panel ────────────────────────────────────────────────────────────
function createSwayncPanel() {
    const panel = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        margin_start: 6, margin_end: 6, margin_top: 6, margin_bottom: 6 });
    mkHeading(panel, ' SwayNC');

    // Border
    const bE = mkEntry(3);
    function loadSwayncBorder() {
        let v = loadState('swaync_border_size.state', '');
        if (v) return v;
        try {
            let [ok, c] = GLib.file_get_contents(SWAYNC_STYLE);
            if (ok && c) { let m = imports.byteArray.toString(c).match(/border:\s*([0-9]+)px\s*solid\s*@bordercolor;/); if (m) return m[1]; }
        } catch (e) {}
        return '2';
    }
    bE.set_text(loadSwayncBorder());
    bE.connect('activate', () => {
        const n = parseInt(bE.get_text());
        if (!isNaN(n) && n >= 0 && n <= 10) {
            try {
                let [ok, c] = GLib.file_get_contents(SWAYNC_STYLE);
                if (ok && c) {
                    let m = imports.byteArray.toString(c).match(/border:\s*([0-9]+)px\s*solid\s*@bordercolor;/);
                    if (m) GLib.spawn_command_line_async(`sed -i '17s/border: ${m[1]}px solid @bordercolor;/border: ${n}px solid @bordercolor;/' '${SWAYNC_STYLE}'`);
                }
            } catch (e) {}
            saveState('swaync_border_size.state', n.toString());
            GLib.spawn_command_line_async("bash -c 'swaync-client -rs'");
        }
    });
    mkRow(panel, 'Border', bE);

    // Radius
    const rE = mkEntry(3);
    rE.set_text(loadState('swaync_outer_radius.state', '10.0'));
    rE.connect('activate', () => {
        const v = parseFloat(rE.get_text());
        if (!isNaN(v) && v >= 0 && v <= 20) {
            const vs = v.toFixed(1);
            GLib.spawn_command_line_async(`sed -i '18s/border-radius: [0-9.]*px;/border-radius: ${vs}px;/' '${SWAYNC_STYLE}'`);
            saveState('swaync_outer_radius.state', vs);
            GLib.spawn_command_line_async("bash -c 'swaync-client -rs'");
        }
    });
    mkRow(panel, 'Radius', rE);

    return panel;
}

// ─── Rofi Panel ──────────────────────────────────────────────────────────────
function createRofiPanel() {
    const panel = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        margin_start: 6, margin_end: 6, margin_top: 6, margin_bottom: 6 });
    mkHeading(panel, '󰮫 Menus');

    // Border
    const bE = mkEntry(3);
    function loadRofiBorder() {
        try {
            let [ok, c] = GLib.file_get_contents(ROFI_BORDER);
            if (ok && c) { let m = imports.byteArray.toString(c).match(/border-width: ([0-9]+)px/); if (m) return m[1]; }
        } catch (e) {}
        return '2';
    }
    bE.set_text(loadRofiBorder());
    bE.connect('activate', () => {
        const n = parseInt(bE.get_text());
        if (!isNaN(n) && n >= 0 && n <= 10) {
            try {
                let [ok, c] = GLib.file_get_contents(ROFI_BORDER);
                if (ok && c) {
                    let m = imports.byteArray.toString(c).match(/border-width: ([0-9]+)px/);
                    if (m) GLib.spawn_command_line_async(`sed -i 's/border-width: ${m[1]}px/border-width: ${n}px/' '${ROFI_BORDER}'`);
                }
            } catch (e) {}
        }
    });
    mkRow(panel, 'Border', bE);

    // Radius
    const rE = mkEntry(3);
    function loadRofiRadius() {
        try {
            let [ok, c] = GLib.file_get_contents(ROFI_RADIUS);
            if (ok && c) { let m = imports.byteArray.toString(c).match(/border-radius: ([0-9.]+)em/); if (m) return m[1]; }
        } catch (e) {}
        return '1.0';
    }
    rE.set_text(loadRofiRadius());
    rE.connect('activate', () => {
        const v = parseFloat(rE.get_text());
        if (!isNaN(v) && v >= 0 && v <= 5) {
            const vs = v.toFixed(1);
            try {
                let [ok, c] = GLib.file_get_contents(ROFI_RADIUS);
                if (ok && c) {
                    let m = imports.byteArray.toString(c).match(/border-radius: ([0-9.]+)em/);
                    if (m) GLib.spawn_command_line_async(`sed -i 's/border-radius: ${m[1]}em/border-radius: ${vs}em/' '${ROFI_RADIUS}'`);
                }
            } catch (e) {}
        }
    });
    mkRow(panel, 'Radius', rE);

    return panel;
}

// ─── SDDM Panel ────────────────────────────────────────────────────────────
function createSDDMPanel() {
    const panel = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 4,
        margin_start: 6, margin_end: 6, margin_top: 6, margin_bottom: 6 });
    mkHeading(panel, '󰍂 SDDM');

    // Helper: read a Key=value line from theme.conf
    function readSDDMVal(key, fallback) {
        try {
            let [ok, c] = GLib.file_get_contents(SDDM_THEME);
            if (ok && c) {
                let m = imports.byteArray.toString(c).match(new RegExp('^' + key + '=(.*)$', 'm'));
                if (m) return m[1].replace(/^"|"$/g, '').trim();
            }
        } catch (e) {}
        return fallback;
    }

    // Helper: write a Key=value line in theme.conf via sudo sed (root-owned file)
    function writeSDDMVal(key, val) {
        GLib.spawn_command_line_async(
            `sudo sed -i 's|^${key}=.*|${key}=${val}|' '${SDDM_THEME}'`
        );
    }

    // ── Header Text ─────────────────────────────────────────────────────────
    // Any string/glyph shown at the top of the SDDM login form.
    const headerE = mkEntry(12);
    headerE.set_max_width_chars(20);
    headerE.set_text(loadState('sddm_header.state', '') || readSDDMVal('HeaderText', ''));
    headerE.connect('activate', () => {
        const v = headerE.get_text();          // preserve spaces + glyphs as-is
        writeSDDMVal('HeaderText', v);
        saveState('sddm_header.state', v);
    });
    mkRow(panel, 'Header', headerE);
    
    // ── Form Psition ─────────────────────────────────────────────────────────
    // Form position: left, center, right
    const formposE = mkEntry(8);
    formposE.set_max_width_chars(8);
    formposE.set_text(loadState('sddm_form.state', '') || readSDDMVal('FormPosition', ''));
    formposE.connect('activate', () => {
        const v = formposE.get_text();          // preserve spaces + glyphs as-is
        writeSDDMVal('FormPosition', v);
        saveState('sddm_form.state', v);
    });
    mkRow(panel, 'Form Pos', formposE);

    // ── Blur Radius ──────────────────────────────────────────────────────────
    // Controls background blur strength (0 = no blur, 100 = max).
    // PartialBlur or FullBlur must be enabled in theme.conf for this to apply.
    const blurE = mkEntry(3);
    blurE.set_text(loadState('sddm_blur.state', '') || readSDDMVal('BlurRadius', '75'));
    blurE.connect('activate', () => {
        const n = parseInt(blurE.get_text());
        if (!isNaN(n) && n >= 0 && n <= 100) {
            writeSDDMVal('BlurRadius', n.toString());
            saveState('sddm_blur.state', n.toString());
        }
    });
    mkRow(panel, 'Blur R', blurE);
    
    // Preview SDDM
    const previewBtn = mkBtn('󰈈  Preview');
    previewBtn.connect('clicked', () => GLib.spawn_command_line_async(`sddm-greeter --test-mode --theme /usr/share/sddm/themes/sugar-candy`));
    panel.append(previewBtn);
    
    return panel;
}

// ═══════════════════════════════════════════════════════════════════════════════
// CSS
// ═══════════════════════════════════════════════════════════════════════════════
function injectCSS() {
    const p = new Gtk.CssProvider();
    const css = `
        .cc-frame { background: transparent; border-radius: 16px; }

        .cc-avatar-btn {
            background: transparent; border-radius: 50%;
            border: 2px solid alpha(@primary, 0.4);
            padding: 2px; min-width: 56px; min-height: 56px;
        }
        .cc-avatar-btn:hover { border-color: @primary; background: alpha(@primary, 0.08); }

        .cc-username { font-size: 20px; font-weight: 700; color: @primary; }

        .cc-menu-btn {
            background-color: alpha(@inverse_primary, 0.7); border:0.5px solid alpha(@background, 0.7); box-shadow: 0 0 0 0 @background, 0 0 0 2px @backgound inset; border-radius: 6px;
            padding: 10px 10px; font-size: 14px; color: alpha(@primary, 0.7);
        }
        .cc-menu-btn:hover { background: alpha(@primary, 0.08); color: @primary; }
        .cc-menu-btn.cc-active {
            background-color: alpha(@inverse_primary, 0.7); border:0.5px solid alpha(@background, 0.7); box-shadow: 0 0 0 0 @primary_fixed_dim, 0 0 0 2px @primary_fixed_dim inset; border-radius: 6px;
            padding: 10px 10px; font-size: 14px; color: alpha(@primary, 0.7);
        }
        .cc-menu-btn.cc-active:hover { background: alpha(@primary, 0.08); color: @primary; }

        .cc-heading {
            font-size: 14px; font-weight: 700; color: @primary;
            letter-spacing: 0.5px;
        }

        .cc-label { font-size: 12px; color: @primary; }

        .cc-entry {
            background: alpha(@primary, 0.06); border: 1px solid alpha(@primary, 0.15);
            border-radius: 6px; padding: 2px 4px; font-size: 12px; min-height: 22px;
            color: @primary;
        }
        .cc-entry:hover { border-color: @primary; color: alpha(@primary-fixed_dim, 0.7); }
        /* GTK4 focus ring lives on the entry node itself via :focus-within.
           Also strip the default blue outline from the text child node. */
        .cc-entry:focus-within {
            border-color: @primary_fixed_dim;
            outline: none;
            box-shadow: none;
        }
        .cc-entry text:focus,
        .cc-entry > text {
            color: @primary;
            outline: none;
            box-shadow: none;
        }
        /* Kill GTK4's default blue undershoot/overshoot highlight */
        .cc-entry undershoot.left,
        .cc-entry undershoot.right {
            background: none;
            box-shadow: none;
        }

        .cc-btn {
            background: alpha(@inverse_primary, 0.7); border: 1px solid alpha(@primary, 0.15);
            border-radius: 6px; padding: 2px 6px; font-size: 12px; min-height: 22px;
            color: @primary;
        }
        .cc-btn:hover { background: alpha(@primary, 0.12); }
        .cc-btn.cc-active, .cc-active {
            background: alpha(@inverse_primary, 0.7); border: 2px solid alpha(@primary, 0.7); color: @primary;
        }
        .cc-btn.cc-active:hover, .cc-active { background: alpha(@primary, 0.12); }

        .cc-pm { min-width: 22px; min-height: 22px; padding: 0; }

        .cc-side-panel {
            background: alpha(@surface, 0.88); border-radius: 0 16px 16px 0;
        }

        scrollbar { background: transparent; min-width: 4px; }
        slider { background: alpha(@primary, 0.2); border-radius: 2px; }
    `;
    p.load_from_data(css, css.length);
    Gtk.StyleContext.add_provider_for_display(Gdk.Display.get_default(), p, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
}

// ═══════════════════════════════════════════════════════════════════════════════
// MAIN LAYOUT WITH LIVE BACKGROUND
// ═══════════════════════════════════════════════════════════════════════════════
function createControlCenterContent() {
    injectCSS();

    const overlay = new Gtk.Overlay();
    overlay.set_hexpand(true);
    overlay.set_vexpand(true);

    // ── Live Cairo background covering entire panel ──
    let _bgColors = null;
    let _phase = 0;
    const BG_FPS = 10;
    const PHASE_STEP = (2 * Math.PI) / (BG_FPS * 50);

    function _resolveColors(widget) {
        try {
            const sc = widget.get_style_context();
            const [ok1, c1] = sc.lookup_color('inverse_primary');
            const [ok2, c2] = sc.lookup_color('background');
            const [ok3, c3] = sc.lookup_color('blur_background');
            if (ok1 && ok2) {
                _bgColors = {
                    inv:  { r: c1.red, g: c1.green, b: c1.blue, a: 1 },
                    bg:   { r: c2.red, g: c2.green, b: c2.blue, a: 1 },
                    blur: ok3 ? { r: c3.red, g: c3.green, b: c3.blue, a: c3.alpha }
                              : { r: c2.red, g: c2.green, b: c2.blue, a: 0.8 }
                };
            }
        } catch (e) {}
    }

    const bgDa = new Gtk.DrawingArea();
    bgDa.set_hexpand(true);
    bgDa.set_vexpand(true);
    bgDa.set_can_target(false);

    function lx(p, f, o) { return Math.sin(p * f + o) * 0.5 + 0.5; }
    function ly(p, f, o) { return Math.cos(p * f + o) * 0.5 + 0.5; }
    function bs(p, f, o, lo, hi) { return lo + (Math.sin(p * f + o) * 0.5 + 0.5) * (hi - lo); }

    bgDa.set_draw_func((_da, cr, w, h) => {
        if (!_bgColors) { _resolveColors(bgDa); return; }
        const p = _phase;
        const phi = 1.6180339887, r2 = 1.4142135623, r3 = 1.7320508075;
        const inv = _bgColors.inv, bg = _bgColors.bg, blur = _bgColors.blur;

        // Rounded clip for entire panel
        const rad = 16;
        cr.newSubPath();
        cr.arc(w - rad, rad, rad, -Math.PI / 2, 0);
        cr.arc(w - rad, h - rad, rad, 0, Math.PI / 2);
        cr.arc(rad, h - rad, rad, Math.PI / 2, Math.PI);
        cr.arc(rad, rad, rad, Math.PI, 3 * Math.PI / 2);
        cr.closePath();
        cr.clip();

        cr.setSourceRGBA(bg.r, bg.g, bg.b, 0.95);
        cr.rectangle(0, 0, w, h);
        cr.fill();

        const blobs = [
            [lx(p,phi*0.7,0),    ly(p,phi*0.5,0.5),  bs(p,0.41,0,0.55,0.75), bs(p,0.53,1.1,0.4,0.65), inv,  bs(p,0.67,0.3,0.55,0.8)],
            [lx(p,r2*0.6,1.2),   ly(p,r2*0.8,2.1),   bs(p,0.37,2.3,0.45,0.7),bs(p,0.61,0.7,0.5,0.72), bg,   bs(p,0.53,1.7,0.5,0.75)],
            [lx(p,r3*0.45,2.5),  ly(p,r3*0.55,0.8),  bs(p,0.29,1.5,0.6,0.8), bs(p,0.47,3.2,0.35,0.6), inv,  bs(p,0.71,2.9,0.45,0.7)],
            [lx(p,0.53,3.7),     ly(p,0.71,1.4),     bs(p,0.55,3,0.4,0.65),  bs(p,0.33,1.8,0.55,0.75),bg,   bs(p,0.43,0.6,0.55,0.78)],
            [lx(p,phi*0.38,4.2), ly(p,r2*0.42,3),    bs(p,0.43,0.9,0.5,0.68),bs(p,0.59,2.5,0.42,0.66),inv,  bs(p,0.59,3.5,0.48,0.72)],
            [lx(p,0.29,1.8),     ly(p,0.37,5.1),     bs(p,0.31,4.1,0.65,0.85),bs(p,0.49,0.3,0.38,0.58),blur, bs(p,0.37,1.2,0.52,0.76)]
        ];

        for (const [cxF, cyF, wF, hF, color, fade] of blobs) {
            const cx0 = cxF * w, cy0 = cyF * h;
            const radius = Math.max(wF * w, hF * h) / 2;
            if (radius < 1) continue;
            const g = new CairoMod.RadialGradient(cx0, cy0, 0, cx0, cy0, radius);
            g.addColorStopRGBA(0, color.r, color.g, color.b, 0.7);
            g.addColorStopRGBA(fade, color.r, color.g, color.b, 0.25);
            g.addColorStopRGBA(1, color.r, color.g, color.b, 0);
            cr.setSource(g);
            cr.rectangle(0, 0, w, h);
            cr.fill();
        }
    });

    _resolveColors(bgDa);

    // Watch GTK4 colors.css for changes and immediately re-resolve background colors
    const _colorsPath = GLib.build_filenamev([HOME, '.config', 'gtk-4.0', 'colors.css']);
    let _colorProvider = null;
    let _colorDebounce = 0;
    function _reloadColorProvider() {
        const display = Gdk.Display.get_default();
        if (!display) return;
        if (_colorProvider) {
            try { Gtk.StyleContext.remove_provider_for_display(display, _colorProvider); } catch (e) {}
        }
        _colorProvider = new Gtk.CssProvider();
        try {
            _colorProvider.load_from_path(_colorsPath);
            Gtk.StyleContext.add_provider_for_display(display, _colorProvider, Gtk.STYLE_PROVIDER_PRIORITY_USER + 1);
        } catch (e) {}
        _resolveColors(bgDa);
    }
    if (GLib.file_test(_colorsPath, GLib.FileTest.EXISTS)) {
        _reloadColorProvider();
        const colFile = Gio.File.new_for_path(_colorsPath);
        const colMon = colFile.monitor_file(Gio.FileMonitorFlags.NONE, null);
        colMon.connect('changed', () => {
            if (_colorDebounce) GLib.source_remove(_colorDebounce);
            _colorDebounce = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 300, () => {
                _colorDebounce = 0;
                _reloadColorProvider();
                return GLib.SOURCE_REMOVE;
            });
        });
        bgDa.connect('destroy', () => { colMon.cancel(); if (_colorDebounce) GLib.source_remove(_colorDebounce); });
    }

    let _gcCounter = 0;
    const animId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, Math.round(1000 / BG_FPS), () => {
        _phase += PHASE_STEP;
        bgDa.queue_draw();
        if (++_gcCounter > BG_FPS * 60) {
            _gcCounter = 0;
            imports.system.gc();
        }
        return GLib.SOURCE_CONTINUE;
    });
    bgDa.connect('destroy', () => GLib.source_remove(animId));

    overlay.set_child(bgDa);

    // ── Content layout: profile on top, left menu + right panel below ──
    const outerBox = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 0,
        hexpand: true, vexpand: true });

    // User profile centered at top, spanning full width
    outerBox.append(createUserProfile());

    // Two-column area below profile
    const columnsBox = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, spacing: 0,
        hexpand: true, vexpand: true });

    // Left: menu buttons
    const leftCol = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 6,
        margin_start: 4, margin_end: 4, margin_top: 2, margin_bottom: 4 });
    leftCol.set_size_request(158, -1);
    leftCol.set_vexpand(true);

    // Menu items
    const menuDefs = [
        ['  Hyprland',  'hyprland'],
        ['󰔎  Themes',    'themes'],
        ['󱟛  Bar',    'waybar'],
        ['󰞒  Dock',      'dock'],
        ['  SwayNC',    'swaync'],
        ['󰮫  Menus',      'rofi'],
        ['󰍂  SDDM',      'sddm'],
    ];

    const panels = {};
    let activeMenuBtn = null;
    let activeMenuId = null;

    // Right: scrolled side panel, hidden by default (visibility toggle)
    const rightScroll = new Gtk.ScrolledWindow({
        hscrollbar_policy: Gtk.PolicyType.NEVER,
        vscrollbar_policy: Gtk.PolicyType.AUTOMATIC,
        vexpand: true,
    });
    rightScroll.set_size_request(158, -1);
    rightScroll.add_css_class('cc-side-panel');
    rightScroll.set_visible(false);

    // Inner box for right panel content
    const rightCol = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL, spacing: 0 });
    rightScroll.set_child(rightCol);

    // Build panels lazily
    const panelBuilders = {
        themes: createThemesPanel,
        waybar: createWaybarPanel,
        hyprland: createHyprlandPanel,
        dock: createDockPanel,
        swaync: createSwayncPanel,
        rofi: createRofiPanel,
        sddm: createSDDMPanel,
    };

    function showPanel(id) {
        let child = rightCol.get_first_child();
        while (child) { rightCol.remove(child); child = rightCol.get_first_child(); }
        if (!panels[id]) panels[id] = panelBuilders[id]();
        rightCol.append(panels[id]);
    }

    menuDefs.forEach(([label, id]) => {
        const btn = new Gtk.Button();
        btn.add_css_class('cc-menu-btn');
        const row = new Gtk.Box({ orientation: Gtk.Orientation.HORIZONTAL, spacing: 6 });
        const lbl = Gtk.Label.new(label);
        lbl.set_halign(Gtk.Align.START);
        row.append(lbl);
        btn.set_child(row);

        btn.connect('clicked', () => {
            if (activeMenuId === id) {
                // Toggle off: hide right panel
                btn.remove_css_class('cc-active');
                rightScroll.set_visible(false);
                activeMenuBtn = null;
                activeMenuId = null;
            } else {
                // Switch to this panel
                if (activeMenuBtn) activeMenuBtn.remove_css_class('cc-active');
                btn.add_css_class('cc-active');
                activeMenuBtn = btn;
                activeMenuId = id;
                showPanel(id);
                rightScroll.set_visible(true);
            }
        });
        leftCol.append(btn);
    });

    columnsBox.append(leftCol);
    columnsBox.append(rightScroll);
    outerBox.append(columnsBox);

    overlay.add_overlay(outerBox);

    const frame = new Gtk.Box({ orientation: Gtk.Orientation.VERTICAL });
    frame.add_css_class('cc-frame');
    frame.append(overlay);
    return frame;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Exports
// ═══════════════════════════════════════════════════════════════════════════════
function createCandyUtilsBox() {
    return createControlCenterContent();
}

function createWindow() {
    const LS = imports.gi.Gtk4LayerShell;
    const win = new Gtk.Window({ resizable: false, decorated: false, title: '',
        default_width: 324, default_height: 660 });
    if (LS.is_supported()) {
        LS.init_for_window(win);
        LS.set_layer(win, LS.Layer.TOP);
        LS.set_exclusive_zone(win, 0);
        LS.set_keyboard_mode(win, LS.KeyboardMode.ON_DEMAND);
        LS.set_namespace(win, 'candy-widgets');
        LS.set_anchor(win, LS.Edge.TOP, true);
        LS.set_margin(win, LS.Edge.TOP, 45);
    }
    const utilsBox = createCandyUtilsBox();
    utilsBox.add_css_class('candy-widget');
    win.set_child(utilsBox);
    const kc = new Gtk.EventControllerKey();
    kc.connect('key-pressed', (_c, k) => {
        if (k === Gdk.KEY_Escape) { win.hide(); return true; }
        return false;
    });
    win.add_controller(kc);
    return win;
}

var exports = {
    createCandyUtilsBox,
    createWindow,
    createControlCenterContent
};
