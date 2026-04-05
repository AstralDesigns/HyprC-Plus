// HyprCandy App Launcher — Configuration
// Edit these values then restart the launcher (toggle-app-launcher.sh).
// Values can be overridden by ~/.config/hyprcandy/launcher-config.state (set via CC Menus tab).

'use strict';

const { GLib } = imports.gi;
const HOME = GLib.get_home_dir();

// ── Default values ──────────────────────────────────────────────────────

const DEFAULTS = {
    searchWidthFraction: 0.80,
    iconSize: 48,
    textFontSize: 11,
    fixedTileWidth: 90,
    fixedTileHeight: 78,
    frameWidth: 420,
    frameHeight: 490,
    frameWidthVert: 380,
    frameHeightVert: 560,
    borderRadius: 20,
    borderWidth: 2,
    searchRadius: 12,
    listRadius: 12,
    innerBorderWidth: 1,
    innerPadding: 10,
};

/** Read override state file if it exists, merging with defaults */
function readStateOverrides() {
    const path = `${HOME}/.config/hyprcandy/launcher-config.state`;
    try {
        const [ok, raw] = GLib.file_get_contents(path);
        if (ok) {
            const text = imports.byteArray.toString(raw);
            const obj = JSON.parse(text);
            return { ...DEFAULTS, ...obj };
        }
    } catch (_) {}
    return DEFAULTS;
}

const STATE = readStateOverrides();

var LauncherConfig = {
    searchWidthFraction: STATE.searchWidthFraction,
    iconSize:            STATE.iconSize,
    textFontSize:        STATE.textFontSize,
    fixedTileWidth:      STATE.fixedTileWidth,
    fixedTileHeight:     STATE.fixedTileHeight,
    frameWidth:          STATE.frameWidth,
    frameHeight:         STATE.frameHeight,
    frameWidthVert:      STATE.frameWidthVert,
    frameHeightVert:     STATE.frameHeightVert,
    borderRadius:        STATE.borderRadius,
    borderWidth:         STATE.borderWidth,
    searchRadius:        STATE.searchRadius,
    listRadius:          STATE.listRadius,
    innerBorderWidth:    STATE.innerBorderWidth,
    innerPadding:        STATE.innerPadding,
};
