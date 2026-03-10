#!/usr/bin/env gjs

// HyprCandy Dock - GTK4/GJS 2026 Implementation
// Modern replacement for nwg-dock-hyprland with HyprCandy theming
// Features: Drag-drop rearrange, async pin update, side popovers, proper indicators

imports.gi.versions.Gtk = '4.0';
imports.gi.versions.Gdk = '4.0';

const { Gtk, Gdk, Gio, GLib, GObject } = imports.gi;
const GLibUnix = imports.gi.GLibUnix;
const Gtk4LayerShell = imports.gi.Gtk4LayerShell;

// Import daemon + config
imports.searchPath.unshift('.');
const Daemon     = imports.daemon.Daemon;
const DockConfig = imports.config.DockConfig;

// --- Parse position flag from ARGV ------------------------------------
// Usage: gjs dock-main.js [-b|-t|-l|-r]
(function parsePositionFlag() {
    const args = ARGV || [];
    if      (args.includes('-t')) DockConfig.position = 'top';
    else if (args.includes('-l')) DockConfig.position = 'left';
    else if (args.includes('-r')) DockConfig.position = 'right';
    else                          DockConfig.position = 'bottom'; // default
})();

// Apply position-specific config overrides
(function applyPositionOverrides() {
    const pos = DockConfig.position;
    const overrides = DockConfig.positionOverrides?.[pos];
    if (overrides) {
        Object.assign(DockConfig, overrides);
        log('[dock] Applied position overrides for: ' + pos);
    }
})();

const IS_VERTICAL = (DockConfig.position === 'left' || DockConfig.position === 'right');

// --- Configuration (live from DockConfig) -----------------------------
// Three independent size axes: app icons, glyph icons, indicators
const APP_ICON_SIZE   = DockConfig.appIconSize;
const GLYPH_ICON_SIZE = DockConfig.glyphIconSize !== null
    ? DockConfig.glyphIconSize
    : Math.round(APP_ICON_SIZE * (DockConfig.glyphIconSizeFraction || 1.1));
const INDICATOR_SIZE  = DockConfig.indicatorSize !== null
    ? DockConfig.indicatorSize
    : Math.max(4, Math.round(APP_ICON_SIZE * DockConfig.indicatorSizeFraction));
const INDICATOR_SPACING = DockConfig.indicatorSpacing;
// Legacy alias used throughout
const ICON_SIZE = APP_ICON_SIZE;

// Glyph icons — Nerd Font Unicode codepoints (NF font required)
const GLYPH_START     = '󱗼';   //  Linux / start
const GLYPH_INDICATOR = '\u{F09DF}';  //  active-window dot
const GLYPH_TRASH     = '\udb82\ude7a';   //  trash
// Hyprland logo glyph (nf-linux-hyprland, NerdFonts >= 3.2)
const GLYPH_FALLBACK  = '󱙝';   //  shown when app has no icon

// --- CSS Management ---------------------------------------------------
const HOME = GLib.get_home_dir();
const GTK3_COLORS_PATH   = GLib.build_filenamev([HOME, '.config', 'gtk-3.0', 'colors.css']);
const GTK4_COLORS_PATH   = GLib.build_filenamev([HOME, '.config', 'gtk-4.0', 'colors.css']);
const DOCK_STYLE_PATH    = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'style.css']);
const DOCK_CONFIG_PATH   = GLib.build_filenamev([HOME, '.hyprcandy', 'GJS', 'hyprcandydock', 'config.js']);

let cssProviders = [];          // Static providers cleared/re-added on theme change
let dynamicConfigProvider = null; // Persistent provider for config-driven values — never cleared
let dockWindow = null;

let _colorMonitor    = null;  // Gio.FileMonitor for gtk-4.0/colors.css
let _colorReloadTimer = 0;    // GLib timeout source ID (debounce)

function loadCSS() {
    const display = Gdk.Display.get_default();
    
    // Remove old providers
    for (const provider of cssProviders) {
        try {
            Gtk.StyleContext.remove_provider_for_display(display, provider);
        } catch (e) { /* ignore */ }
    }
    cssProviders = [];

    // Load GTK3 colors (matugen named colors)
    if (GLib.file_test(GTK3_COLORS_PATH, GLib.FileTest.EXISTS)) {
        const gtk3Provider = new Gtk.CssProvider();
        try {
            gtk3Provider.load_from_path(GTK3_COLORS_PATH);
            Gtk.StyleContext.add_provider_for_display(display, gtk3Provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
            cssProviders.push(gtk3Provider);
        } catch (e) {
            log('[dock] Failed to load GTK3 colors: ' + e.message);
        }
    }

    // Load GTK4 colors
    if (GLib.file_test(GTK4_COLORS_PATH, GLib.FileTest.EXISTS)) {
        const gtk4Provider = new Gtk.CssProvider();
        try {
            gtk4Provider.load_from_path(GTK4_COLORS_PATH);
            Gtk.StyleContext.add_provider_for_display(display, gtk4Provider, Gtk.STYLE_PROVIDER_PRIORITY_USER);
            cssProviders.push(gtk4Provider);
        } catch (e) {
            log('[dock] Failed to load GTK4 colors: ' + e.message);
        }
    }

    // Load dock style
    if (GLib.file_test(DOCK_STYLE_PATH, GLib.FileTest.EXISTS)) {
        const styleProvider = new Gtk.CssProvider();
        try {
            styleProvider.load_from_path(DOCK_STYLE_PATH);
            Gtk.StyleContext.add_provider_for_display(display, styleProvider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
            cssProviders.push(styleProvider);
        } catch (e) {
            log('[dock] Failed to load dock style: ' + e.message);
        }
    }

    // Inject computed glyph sizes from config so ICON_SIZE drives all unicode labels.
    // This runs after style.css so it overrides the static fallback font-sizes.
    _injectGlyphSizeCSS(display);
}

function _injectGlyphSizeCSS(display) {
    // Read live from DockConfig so hot-reload (SIGUSR2) picks up new values.
    // Do NOT use the baked consts (APP_ICON_SIZE etc.) here — they are frozen
    // at process start and won't reflect config edits.
    const appPx       = DockConfig.appIconSize;
    const glyphPx     = DockConfig.glyphIconSize !== null
        ? DockConfig.glyphIconSize
        : Math.round(appPx * (DockConfig.glyphIconSizeFraction || 1.1));
    const indicatorPx = DockConfig.indicatorSize !== null
        ? DockConfig.indicatorSize
        : Math.max(4, Math.round(appPx * DockConfig.indicatorSizeFraction));
    const btnSize  = appPx + 8;
    const borderW  = DockConfig.borderWidth;
    const borderR  = DockConfig.borderRadius;
    const padPx    = DockConfig.innerPadding;

    const css = `
        /* Config-driven values — updated in-place on SIGUSR2 hot-reload */
        window.background {
            border-width: ${borderW}px;
            border-radius: ${borderR}px;
        }
        #box {
            padding: ${padPx}px;
        }
        #start-icon, #trash-icon {
            font-size: ${glyphPx}px;
        }
        .fallback-icon {
            font-size: ${glyphPx}px;
        }
        #active-indicator {
            font-size: ${indicatorPx}px;
        }
        /* Separator length matches icon size (not button container) */
        separator.dock-sep-v {
            min-height: ${appPx}px;
            max-height: ${appPx}px;
        }
        separator.dock-sep-h {
            min-width: ${appPx}px;
            max-width: ${appPx}px;
        }
        button.app-button, button.dock-button {
            min-width: ${btnSize}px;
            max-width: ${btnSize}px;
            min-height: ${btnSize}px;
            max-height: ${btnSize}px;
            overflow: hidden;
        }
        button.app-button image, button.dock-button image {
            min-width: ${appPx}px;
            max-width: ${appPx}px;
            min-height: ${appPx}px;
            max-height: ${appPx}px;
        }
    `;

    // Reuse the same provider object — just update its CSS in-place.
    // This provider lives outside cssProviders so loadCSS() never removes it.
    // It is registered once with the display at APPLICATION+1 priority
    // (higher than style.css at APPLICATION) so it always wins.
    if (!dynamicConfigProvider) {
        dynamicConfigProvider = new Gtk.CssProvider();
        Gtk.StyleContext.add_provider_for_display(
            display, dynamicConfigProvider,
            Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION + 1);
    }
    try {
        dynamicConfigProvider.load_from_data(css, -1);
    } catch (e) {
        log('[dock] Failed to inject config CSS: ' + e.message);
    }
}

// --- Hot-reload (SIGUSR2) ---------------------------------------------

// Read all @HCD-tagged values from config.js and write them into DockConfig.
// Returns true on success.
function reloadConfigFromFile() {
    try {
        const [ok, contents] = GLib.file_get_contents(DOCK_CONFIG_PATH);
        if (!ok) { log('[dock] hot-reload: cannot read config.js'); return false; }
        const text = new TextDecoder().decode(contents);
        // Match lines like:  appIconSize: 24,    // @HCD:appIconSize
        // Captures: key (group 1), numeric value (group 2)
        // Numeric @HCD values
        const numRe = /\b(\w+):[ \t]*([0-9]+(?:\.[0-9]+)?),[ \t]*\/\/ @HCD:\1\b/g;
        let match;
        while ((match = numRe.exec(text)) !== null) {
            const key = match[1];
            const val = Number(match[2]);
            if (!isNaN(val)) {
                DockConfig[key] = val;
                log('[dock] hot-reload: ' + key + ' = ' + val);
            }
        }
        // String @HCD values  (e.g.  startIcon: '',   // @HCD:startIcon)
        const strRe = /\b(\w+):[ \t]*'([^']*)',[ \t]*\/\/ @HCD:\1\b/g;
        while ((match = strRe.exec(text)) !== null) {
            const key = match[1];
            DockConfig[key] = match[2];
            log('[dock] hot-reload: ' + key + ' = \'' + match[2] + '\'');
        }
        // Re-parse and apply positionOverrides for the current position
        // so margin edits inside positionOverrides take effect on hot-reload.
        try {
            const ovMatch = text.match(/positionOverrides\s*:\s*\{([\s\S]*?)\n    \}/);
            if (ovMatch) {
                const pos = DockConfig.position;
                const posBlk = ovMatch[1].match(new RegExp(pos + '\\s*:\\s*\\{([^}]*?)\\}'));
                if (posBlk) {
                    const kvRe = /(\w+)\s*:\s*([0-9]+(?:\.[0-9]+)?)/g;
                    let kv;
                    while ((kv = kvRe.exec(posBlk[1])) !== null) {
                        DockConfig[kv[1]] = Number(kv[2]);
                        log('[dock] hot-reload override: ' + kv[1] + ' = ' + kv[2]);
                    }
                }
            }
        } catch (e) {
            log('[dock] hot-reload positionOverrides parse error: ' + e.message);
        }
        return true;
    } catch (e) {
        log('[dock] hot-reload error reading config: ' + e.message);
        return false;
    }
}

// Re-apply all four layer-shell margins from the (possibly updated) DockConfig.
function applyMarginsToLayerShell(win) {
    if (!win) return;
    const cfg = DockConfig;
    Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.BOTTOM, cfg.marginBottom);
    Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.TOP,    cfg.marginTop);
    Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.LEFT,   cfg.marginLeft);
    Gtk4LayerShell.set_margin(win, Gtk4LayerShell.Edge.RIGHT,  cfg.marginRight);
}

// Full hot-reload: config values → CSS + layer-shell + exclusive zone.
// Triggered by SIGUSR2 (kill -12 <pid>) — sent by candy-utils after editing config.js.
//
// What each @HCD variable hot-reloads to:
//   appIconSize   → button min/max size + image pixel_size CSS (CSS side; button
//                   widget size_request needs a dock restart for structural rebuild)
//   innerPadding  → #box { padding }          (CSS re-inject)
//   borderWidth   → window.background border  (CSS re-inject)
//   borderRadius  → window.background radius  (CSS re-inject)
//   marginBottom/Top/Left/Right → Gtk4LayerShell.set_margin (live)
function hotReload() {
    log('[dock] SIGUSR2 received — hot-reloading config');
    if (!reloadConfigFromFile()) return;
    const display = Gdk.Display.get_default();
    if (display) _injectGlyphSizeCSS(display);
    applyMarginsToLayerShell(dockWindow);
    if (dockWindow) {
        // Update start icon glyph if it changed
        if (dockWindow._startIconLabel) {
            dockWindow._startIconLabel.set_text(
                DockConfig.startIcon !== null ? DockConfig.startIcon : GLYPH_START
            );
        }
        // Update button spacing
        if (dockWindow.mainBox)
            dockWindow.mainBox.set_spacing(DockConfig.buttonSpacing);
        dockWindow._scheduleExclusiveZoneUpdate();
    }
    log('[dock] hot-reload complete');
}

// --- Colour hot-reload (matugen) --------------------------------------
// GTK4 does NOT auto-reload custom CssProviders on disk change — only its
// own theme CSS responds to GtkSettings signals.  We therefore watch
// gtk-4.0/colors.css with a single Gio.FileMonitor.  matugen regenerates
// both gtk-3.0 and gtk-4.0 colours together, so watching the gtk-4.0 file
// is sufficient; the gtk-3.0 provider is reloaded in the same loadCSS() call.
//
// Leak-prevention:
//   • Only CHANGES_DONE_HINT / CREATED events trigger a reload (avoids
//     duplicate firings from editors that do atomic write + rename).
//   • A single debounce timer (300 ms) is tracked and cancelled before being
//     re-queued, so rapid successive writes never stack up.
//   • teardownColorMonitor() cancels both the monitor and any pending timer;
//     it is called from vfunc_close_request so nothing outlives the process.

function setupColorMonitor() {
    const file = Gio.File.new_for_path(GTK4_COLORS_PATH);
    try {
        _colorMonitor = file.monitor_file(Gio.FileMonitorFlags.NONE, null);
        _colorMonitor.connect('changed', (_mon, _f, _other, eventType) => {
            if (eventType !== Gio.FileMonitorEvent.CHANGES_DONE_HINT &&
                eventType !== Gio.FileMonitorEvent.CREATED) return;
            if (_colorReloadTimer) {
                GLib.source_remove(_colorReloadTimer);
                _colorReloadTimer = 0;
            }
            _colorReloadTimer = GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 300, () => {
                _colorReloadTimer = 0;
                loadCSS();
                if (dockWindow) dockWindow.queue_draw();
                return GLib.SOURCE_REMOVE;
            });
        });
    } catch (e) {
        log('[dock] Color monitor setup failed: ' + e.message);
    }
}

function teardownColorMonitor() {
    if (_colorReloadTimer) {
        GLib.source_remove(_colorReloadTimer);
        _colorReloadTimer = 0;
    }
    if (_colorMonitor) {
        _colorMonitor.cancel();
        _colorMonitor = null;
    }
}

// --- Drag and Drop Manager --------------------------------------------
var DragDropManager = class {
    constructor(dock) {
        this.dock = dock;
        this.draggedWidget = null;
        if (this.dock.mainBox) {
            this.setupDragDrop();
        }
    }

    setupDragDrop() {
        if (!this.dock.mainBox) return;
        
        // GTK4 DropTarget for the main box
        const dropTarget = new Gtk.DropTarget({
            actions: Gdk.DragAction.MOVE,
            // Use proper GTK4 content format
            formats: Gdk.ContentFormats.new_for_gtype(Gtk.Widget),
        });

        dropTarget.connect('drop', (target, value, x, y) => {
            this._onDrop(value, x, y);
            return true;
        });

        dropTarget.connect('motion', (target, x, y) => {
            return this._onDragMotion(x, y);
        });

        dropTarget.connect('leave', () => {
            this._onDragLeave();
        });

        this.dock.mainBox.add_controller(dropTarget);
    }

    _onDrop(widget, x, y) {
        if (!widget || widget === this.draggedWidget) return;

        // Find drop position
        let dropAfter = null;
        let child = this.dock.mainBox.get_first_child();
        
        while (child) {
            const alloc = child.get_allocation();
            if (x > alloc.x + alloc.width / 2) {
                dropAfter = child;
            }
            child = child.get_next_sibling();
        }

        // Reorder widget
        if (dropAfter && dropAfter !== widget) {
            this.dock.mainBox.reorder_child_after(widget, dropAfter);
        } else if (!dropAfter && this.dock.mainBox.get_first_child() !== widget) {
            this.dock.mainBox.reorder_child_after(widget, null);
        }

        this.draggedWidget = null;
    }

    _onDragMotion(x, y) {
        // Visual feedback could be added here
        return Gdk.DragAction.MOVE;
    }

    _onDragLeave() {
        // Cleanup visual feedback
    }

    setupDragSource(widget) {
        const dragSource = new Gtk.DragSource({
            actions: Gdk.DragAction.MOVE,
        });

        dragSource.connect('prepare', (source, x, y) => {
            this.draggedWidget = widget;
            // Use GTK4 content provider correctly
            const content = new Gdk.ContentProvider();
            content.set_value(widget, Gtk.Widget.$gtype);
            return content;
        });

        dragSource.connect('drag-begin', () => {
            widget.set_opacity(0.5);
        });

        dragSource.connect('drag-end', () => {
            widget.set_opacity(1.0);
            this.draggedWidget = null;
        });

        widget.add_controller(dragSource);
    }
};

// --- Dock Window ------------------------------------------------------
const HyprCandyDock = GObject.registerClass({
    GTypeName: 'HyprCandyDock',
}, class HyprCandyDock extends Gtk.ApplicationWindow {
    _init(application) {
        super._init({
            application: application,
            title: 'HyprCandy Dock',
            decorated: false,
            resizable: false,
        });

        this.daemon = new Daemon(this);
        this.clientWidgets = new Map();
        
        // Track separators
        this._startSeparator = null;
        this._endSeparator = null;
        this._trashButton = null;

        dockWindow = this;

        this._setupLayerShell();
        this._createDock();
        
        // Initialize drag-drop manager after mainBox is created
        this.dragDropManager = new DragDropManager(this);
        
        this._initializeDock();
    }

    _setupLayerShell() {
        const cfg = DockConfig;
        const pos = cfg.position; // 'bottom' | 'top' | 'left' | 'right'

        Gtk4LayerShell.init_for_window(this);
        Gtk4LayerShell.set_namespace(this, 'hyprcandy-dock');
        // TOP layer: exclusive zones are respected by normal windows.
        // OVERLAY would render above everything but exclusive zone is ignored.
        Gtk4LayerShell.set_layer(this, Gtk4LayerShell.Layer.TOP);

        // Anchor the correct edge; clear the opposing three
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.BOTTOM, pos === 'bottom');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.TOP,    pos === 'top');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.LEFT,   pos === 'left');
        Gtk4LayerShell.set_anchor(this, Gtk4LayerShell.Edge.RIGHT,  pos === 'right');

        // Margins from config
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.BOTTOM, cfg.marginBottom);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.TOP,    cfg.marginTop);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.LEFT,   cfg.marginLeft);
        Gtk4LayerShell.set_margin(this, Gtk4LayerShell.Edge.RIGHT,  cfg.marginRight);

        // Exclusive zone is set after the first layout pass via
        // _scheduleExclusiveZoneUpdate() — at this point the surface hasn't
        // been sized yet, so get_allocated_height() would return 0.

        log('[dock] Layer shell configured for position: ' + pos);
    }

    // Exclusive zone — reserves screen real-estate so tiled/maximised windows
    // never overlap the dock.
    //
    // GTK4 layer-shell: get_allocated_height() is unreliable (compositor
    // manages allocation externally).  Instead we query mainBox.measure()
    // for the NATURAL content height and add borderWidth*2 for the CSS
    // border the compositor draws around the content.
    //
    // The compositor automatically adds the anchored-edge margin (e.g.
    // marginBottom for a bottom dock) on top of the exclusive zone value.
    // Hyprland also applies its own gaps_out + border_size between windows
    // and the reserved boundary.  So zone = surfaceSize is sufficient.
    updateExclusiveZone() {
        const cfg = DockConfig;
        if (cfg.exclusiveZoneOverride !== null && cfg.exclusiveZoneOverride !== undefined) {
            Gtk4LayerShell.set_exclusive_zone(this, cfg.exclusiveZoneOverride);
            return;
        }
        const axis = IS_VERTICAL ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL;
        const contentSize = this.mainBox
            ? this.mainBox.measure(axis, -1)[1]   // [1] = natural size
            : (cfg.appIconSize + cfg.innerPadding * 2);  // fallback before mainBox exists
        const zone = contentSize + cfg.borderWidth * 2;
        Gtk4LayerShell.set_exclusive_zone(this, zone);
        log('[dock] exclusiveZone = ' + zone + ' (content=' + contentSize + ' + border=' + (cfg.borderWidth * 2) + ')');
    }

    // Called after layout changes. Short timeout ensures GTK has committed
    // the allocation before we query get_allocated_height().
    _scheduleExclusiveZoneUpdate() {
        if (this._ezUpdateId) return; // debounce
        this._ezUpdateId = GLib.timeout_add(GLib.PRIORITY_DEFAULT, 200, () => {
            this._ezUpdateId = 0;
            this.updateExclusiveZone();
            return GLib.SOURCE_REMOVE;
        });
    }

    _createDock() {
        // Orientation: horizontal for bottom/top, vertical for left/right
        const orientation = IS_VERTICAL
            ? Gtk.Orientation.VERTICAL
            : Gtk.Orientation.HORIZONTAL;

        this.mainBox = Gtk.Box.new(orientation, DockConfig.buttonSpacing);
        this.mainBox.set_name('box');
        this.mainBox.set_halign(Gtk.Align.CENTER);
        this.mainBox.set_valign(Gtk.Align.CENTER); // centres icons — fixes 1px top-heavy offset

        this.set_child(this.mainBox);
        // Horizontal docks: 100 is a minimum along-edge width while buttons load.
        // Vertical docks: 100 would force 100 px thickness — use natural size instead.
        if (IS_VERTICAL) {
            this.set_default_size(-1, -1);
        } else {
            this.set_default_size(100, -1);
        }

        log('[dock] Dock UI created (' + (IS_VERTICAL ? 'vertical' : 'horizontal') + ')');
    }

    async _initializeDock() {
        // Add start button first (leftmost)
        this._addStartButton();
        this._addSeparator('start');

        // Load initial clients
        await this.daemon.loadInitialClients();

        // Start event monitoring
        this.daemon.startEventMonitoring();

        // Separator before trash, then trash button last (rightmost)
        this._addSeparator('end');
        this._addTrashButton();

        this.show();

        // Schedule exclusive zone update after the first GTK layout pass.
        // At this point get_allocated_height() returns the real surface size.
        this._scheduleExclusiveZoneUpdate();
        log('[dock] Dock initialized');
    }

    _addSeparator(tag) {
        const sep = Gtk.Separator.new(
            IS_VERTICAL ? Gtk.Orientation.HORIZONTAL : Gtk.Orientation.VERTICAL
        );
        sep.set_name('separator-' + tag);
        sep.add_css_class(IS_VERTICAL ? 'dock-sep-h' : 'dock-sep-v');
        this.mainBox.append(sep);
        if (tag === 'start') this._startSeparator = sep;
        if (tag === 'end') this._endSeparator = sep;
    }

    _addStartButton() {
        // Start button has no indicator — it is a launcher, not a tracked app.
        // No dotsPlaceholder, no container wrapper, no overlay.  Plain button only.
        const btn = Gtk.Button.new();
        btn.add_css_class('app-button');
        btn.add_css_class('dock-button');
        btn.set_size_request(ICON_SIZE + 8, ICON_SIZE + 8);
        btn.set_halign(Gtk.Align.CENTER);
        btn.set_valign(Gtk.Align.CENTER);

        const label = Gtk.Label.new(
            DockConfig.startIcon !== null ? DockConfig.startIcon : GLYPH_START
        );
        label.set_name('start-icon');
        label.set_halign(Gtk.Align.CENTER);
        label.set_valign(Gtk.Align.CENTER);
        btn.set_child(label);
        btn.set_tooltip_text('Applications');

        // Left click - launch rofi
        btn.connect('clicked', () => {
            GLib.spawn_command_line_async('rofi -show drun');
        });

        // Right click - show settings menu
        const gesture = new Gtk.GestureClick();
        gesture.set_button(3); // Right click
        gesture.connect('pressed', () => {
            this._showStartMenu(btn);
        });
        btn.add_controller(gesture);

        this.mainBox.append(btn);
        this._startButton = btn;
        this._startIconLabel = label;
    }

    _addTrashButton() {
        // Trash button has no indicator — same as start, no container/overlay needed.
        const btn = Gtk.Button.new();
        btn.add_css_class('app-button');
        btn.add_css_class('dock-button');
        btn.set_size_request(ICON_SIZE + 8, ICON_SIZE + 8);
        btn.set_halign(Gtk.Align.CENTER);
        btn.set_valign(Gtk.Align.CENTER);

        const label = Gtk.Label.new(GLYPH_TRASH);
        label.set_name('trash-icon');
        label.set_halign(Gtk.Align.CENTER);
        label.set_valign(Gtk.Align.CENTER);
        btn.set_child(label);
        btn.set_tooltip_text('Trash');

        btn.connect('clicked', () => {
            GLib.spawn_command_line_async('nautilus trash:///');
        });

        this.mainBox.append(btn);
        this._trashButton = btn;
    }

    _updateFromDaemon(clientData) {
        const currentClasses = new Set(this.clientWidgets.keys());
        const newClasses = new Set(clientData.map(d => d.className));

        // Remove deleted apps
        for (const className of currentClasses) {
            if (!newClasses.has(className)) {
                const widget = this.clientWidgets.get(className);
                if (widget) {
                    this.mainBox.remove(widget);
                    this.clientWidgets.delete(className);
                    log('[dock] Removed: ' + className);
                }
            }
        }

        // Add or update apps
        for (const data of clientData) {
            if (!this.clientWidgets.has(data.className)) {
                this._addClientButton(data);
            } else {
                this._updateClientButton(data);
            }
        }

        // Reorder: sep-end → trash must always be the final two widgets
        const lastApp = this._getLastAppWidget();
        if (this._endSeparator) {
            this.mainBox.reorder_child_after(this._endSeparator, lastApp);
        }
        if (this._trashButton) {
            this.mainBox.reorder_child_after(
                this._trashButton, this._endSeparator || lastApp);
        }

        // Surface width may have changed (app added/removed) — re-sync zone
        this._scheduleExclusiveZoneUpdate();
    }

    _getLastAppWidget() {
        let last = null;
        for (const [, widget] of this.clientWidgets) {
            last = widget;
        }
        return last;
    }

    _addClientButton(data) {
        // Each app button is a Gtk.Overlay so the indicator dots can be
        // overlaid directly on the button face at the screen-facing edge —
        // no sibling dotsBox means no extra layout height/width for any button.
        //
        // Screen-facing edge per dock position:
        //   bottom → dots at BOTTOM  (halign CENTER, valign END)
        //   top    → dots at TOP     (halign CENTER, valign START)
        //   left   → dots at LEFT    (halign START,  valign CENTER)
        //   right  → dots at RIGHT   (halign END,    valign CENTER)
        const pos = DockConfig.position;
        let dotsHalign, dotsValign;
        if (pos === 'top') {
            dotsHalign = Gtk.Align.CENTER; dotsValign = Gtk.Align.START;
        } else if (pos === 'left') {
            dotsHalign = Gtk.Align.START;  dotsValign = Gtk.Align.CENTER;
        } else if (pos === 'right') {
            dotsHalign = Gtk.Align.END;    dotsValign = Gtk.Align.CENTER;
        } else {
            // bottom (default)
            dotsHalign = Gtk.Align.CENTER; dotsValign = Gtk.Align.END;
        }

        // Icon button — fixed footprint
        const btn = Gtk.Button.new();
        btn.add_css_class('app-button');
        btn.add_css_class('dock-button');
        btn.set_name('app-' + data.className);
        btn.set_size_request(ICON_SIZE + 8, ICON_SIZE + 8);

        const iconName = this.daemon.getIcon(data.iconClass || data.className);
        let iconWidget;
        if (iconName === 'application-x-executable' || !iconName) {
            const fallbackLabel = Gtk.Label.new(GLYPH_FALLBACK);
            fallbackLabel.add_css_class('fallback-icon');
            btn.set_size_request(ICON_SIZE + 8, ICON_SIZE + 8);
            fallbackLabel.set_halign(Gtk.Align.CENTER);
            fallbackLabel.set_valign(Gtk.Align.CENTER);
            iconWidget = fallbackLabel;
        } else if (iconName.startsWith('/') || iconName.startsWith('~')) {
            iconWidget = Gtk.Image.new_from_file(iconName);
            iconWidget.set_pixel_size(ICON_SIZE);
            iconWidget.set_halign(Gtk.Align.CENTER);
            iconWidget.set_valign(Gtk.Align.CENTER);
        } else {
            iconWidget = Gtk.Image.new_from_icon_name(iconName);
            iconWidget.set_pixel_size(ICON_SIZE);
            iconWidget.set_halign(Gtk.Align.CENTER);
            iconWidget.set_valign(Gtk.Align.CENTER);
        }
        btn.set_child(iconWidget);

        const tooltipText = data.instances.length > 1
            ? (data.displayName || data.className) + ' (' + data.instances.length + ')'
            : (data.displayName || data.className);
        btn.set_tooltip_text(tooltipText);

        btn.connect('clicked', () => {
            const freshClientData = this.daemon.getClientData();
            const freshData = freshClientData.find(d => d.className === data.className);
            const instances = freshData ? freshData.instances : data.instances;
            if (instances.length > 0) {
                this.daemon.focusWindow(instances[0].address);
            } else {
                // Pinned but not running — launch via desktop entry
                const lookupClass = (freshData || data).iconClass || data.className;
                this.daemon.launchApp(lookupClass);
            }
        });

        const gesture = new Gtk.GestureClick();
        gesture.set_button(3);
        gesture.connect('pressed', () => {
            const freshClientData = this.daemon.getClientData();
            const freshData = freshClientData.find(d => d.className === data.className) || data;
            this._showContextMenu(freshData, btn);
        });
        btn.add_controller(gesture);

        // Dots overlay — lives on top of the button, zero layout cost.
        // Orientation: horizontal for bottom/top, vertical for left/right.
        const dotsBox = Gtk.Box.new(
            IS_VERTICAL ? Gtk.Orientation.VERTICAL : Gtk.Orientation.HORIZONTAL, 0);
        dotsBox.set_halign(dotsHalign);
        dotsBox.set_valign(dotsValign);
        dotsBox.set_name('indicator-dots');
        this._populateDots(dotsBox, data);

        // Wrap button + dots in an overlay — no size penalty vs a plain button
        const overlay = new Gtk.Overlay();
        overlay.set_halign(Gtk.Align.CENTER);
        overlay.set_valign(Gtk.Align.CENTER);
        overlay.set_child(btn);
        overlay.add_overlay(dotsBox);
        // Prevent the dots from influencing the overlay's own size request
        overlay.set_measure_overlay(dotsBox, false);
        // Allow input events to pass through the transparent dots area to the button
        overlay.set_clip_overlay(dotsBox, true);

        this.dragDropManager.setupDragSource(overlay);

        if (this._endSeparator) {
            const lastWidget = this._getLastAppWidget();
            this.mainBox.insert_child_after(overlay, lastWidget);
        } else {
            this.mainBox.append(overlay);
        }

        this.clientWidgets.set(data.className, overlay);
    }

    _updateClientButton(data) {
        // clientWidgets now stores the Gtk.Overlay directly.
        // Structure: overlay { child=btn, overlay=dotsBox }
        const overlay = this.clientWidgets.get(data.className);
        if (!overlay) return;

        const btn = overlay.get_child();
        if (btn) {
            const tooltipText = data.instances.length > 1
                ? (data.displayName || data.className) + ' (' + data.instances.length + ')'
                : (data.displayName || data.className);
            btn.set_tooltip_text(tooltipText);
        }

        // dotsBox is the first overlay child (added via add_overlay)
        const dotsBox = this._findDotsBox(overlay);
        if (dotsBox) {
            while (dotsBox.get_first_child()) {
                dotsBox.remove(dotsBox.get_first_child());
            }
            this._populateDots(dotsBox, data);
        }
    }

    // Walk the overlay's children to find the named dotsBox widget.
    // Gtk.Overlay keeps its overlay children as siblings AFTER the main child
    // in the internal child list, so we skip the first child (the button).
    _findDotsBox(overlay) {
        let child = overlay.get_first_child();
        while (child) {
            if (child.get_name() === 'indicator-dots') return child;
            child = child.get_next_sibling();
        }
        return null;
    }

    // Shared helper — fills a dotsBox with indicator glyphs
    _populateDots(dotsBox, data) {
        const instanceCount = data.instances ? data.instances.length : 0;
        if (instanceCount > 0) {
            if (instanceCount > 1) {
                const first = Gtk.Label.new(GLYPH_INDICATOR);
                first.set_name('active-indicator');
                dotsBox.append(first);
                const second = Gtk.Label.new(GLYPH_INDICATOR);
                second.set_name('active-indicator');
                if (IS_VERTICAL) second.set_margin_top(INDICATOR_SPACING);
                else              second.set_margin_start(INDICATOR_SPACING);
                dotsBox.append(second);
            } else {
                const dot = Gtk.Label.new(GLYPH_INDICATOR);
                dot.set_name('active-indicator');
                dotsBox.append(dot);
            }
        }
    }

    // --- Context Menu (GTK4 Popover with nwg-style side menu) ---------
    _showContextMenu(data, parentButton) {
        // Compute popover directions so the menu always opens away from the
        // screen edge regardless of which edge the dock is anchored to.
        const _pos = DockConfig.position;
        const _gapD = DockConfig.popoverGapDock || 12;
        const _gapS = DockConfig.popoverGapSide || 12;
        let mainPopPos, mainOffX, mainOffY, sidePopPos, sideOffX, sideOffY;
        if (_pos === 'top') {
            mainPopPos = Gtk.PositionType.BOTTOM; mainOffX = 0;      mainOffY = _gapD;
            sidePopPos = Gtk.PositionType.BOTTOM; sideOffX = 0;      sideOffY = _gapS;
        } else if (_pos === 'left') {
            mainPopPos = Gtk.PositionType.RIGHT;  mainOffX = _gapD;  mainOffY = 0;
            sidePopPos = Gtk.PositionType.RIGHT;  sideOffX = _gapS;  sideOffY = 0;
        } else if (_pos === 'right') {
            mainPopPos = Gtk.PositionType.LEFT;   mainOffX = -_gapD; mainOffY = 0;
            sidePopPos = Gtk.PositionType.LEFT;   sideOffX = -_gapS; sideOffY = 0;
        } else {
            mainPopPos = Gtk.PositionType.TOP;    mainOffX = 0;      mainOffY = -_gapD;
            sidePopPos = Gtk.PositionType.RIGHT;  sideOffX = _gapS;  sideOffY = 0;
        }

        // Main popover
        const mainPopover = new Gtk.Popover();
        mainPopover.set_parent(parentButton);
        mainPopover.set_has_arrow(false);
        mainPopover.set_position(mainPopPos);
        mainPopover.add_css_class('dock-popover');
        mainPopover.set_offset(mainOffX, mainOffY);
        
        // Apply inline styling for transparency fix
        const mainStyleContext = mainPopover.get_style_context();
        mainStyleContext.add_provider(this._getPopoverCSSProvider(), Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        const menuBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        menuBox.set_margin_start(6);
        menuBox.set_margin_end(6);
        menuBox.set_margin_top(6);
        menuBox.set_margin_bottom(6);

        // Track whichever side popover is currently open so we can close it
        // before opening another one — Wayland only allows one grab chain at a time.
        let openSidePopover = null;

        // Show instances only when app is running
        if (data.instances.length > 0) {
            // Per-instance entries with side popover on hover
            data.instances.forEach((instance, idx) => {
                // Instance header row
                const headerBox = Gtk.Box.new(Gtk.Orientation.HORIZONTAL, 6);

                const _instanceIconName = this.daemon.getIcon(data.iconClass || data.className);
                const instanceIcon = (_instanceIconName.startsWith('/') || _instanceIconName.startsWith('~'))
                    ? Gtk.Image.new_from_file(_instanceIconName)
                    : Gtk.Image.new_from_icon_name(_instanceIconName);
                instanceIcon.set_pixel_size(16);
                headerBox.append(instanceIcon);

                const title = instance.title.length > 30
                    ? instance.title.substring(0, 30) + '...'
                    : instance.title;
                const wsName = instance.workspace
                    ? (instance.workspace.name || instance.workspace.id || '?')
                    : '?';
                const headerLabel = Gtk.Label.new(title + ' (' + wsName + ')');
                headerLabel.set_halign(Gtk.Align.START);
                headerLabel.set_hexpand(true);
                headerBox.append(headerLabel);

                const chevronLabel = Gtk.Label.new('›');
                chevronLabel.set_halign(Gtk.Align.END);
                chevronLabel.set_valign(Gtk.Align.CENTER);
                chevronLabel.set_margin_start(8);
                headerBox.append(chevronLabel);

                // Focus button
                const focusBtn = Gtk.Button.new();
                focusBtn.set_child(headerBox);
                focusBtn.add_css_class('popover-item');
                focusBtn.set_halign(Gtk.Align.FILL);
                focusBtn.connect('clicked', () => {
                    this.daemon.focusWindow(instance.address);
                    mainPopover.popdown();
                });

                // Side popover for actions (opens on hover)
                const sidePopover = new Gtk.Popover();
                sidePopover.set_parent(focusBtn);
                sidePopover.set_has_arrow(false);
                sidePopover.set_position(sidePopPos);
                sidePopover.add_css_class('dock-popover');
                sidePopover.set_offset(sideOffX, sideOffY);
                
                // Apply inline styling for transparency fix
                const sideStyleContext = sidePopover.get_style_context();
                sideStyleContext.add_provider(this._getPopoverCSSProvider(), Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

                const actionsBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
                actionsBox.set_margin_start(6);
                actionsBox.set_margin_end(6);
                actionsBox.set_margin_top(6);
                actionsBox.set_margin_bottom(6);

                // Window actions
                const windowActions = [
                    { label: 'Close Window', fn: () => this.daemon.closeWindow(instance.address) },
                    { label: 'Toggle Floating', fn: () => this.daemon.hyprctl('dispatch togglefloating address:' + instance.address) },
                    { label: 'Fullscreen', fn: () => this.daemon.hyprctl('dispatch fullscreen address:' + instance.address) },
                ];

                for (const wa of windowActions) {
                    const actionBtn = Gtk.Button.new_with_label(wa.label);
                    actionBtn.add_css_class('popover-item');
                    actionBtn.add_css_class('popover-action');
                    actionBtn.set_halign(Gtk.Align.FILL);
                    actionBtn.connect('clicked', () => {
                        wa.fn();
                        sidePopover.popdown();
                        mainPopover.popdown();
                    });
                    actionsBox.append(actionBtn);
                }

                // Move to workspace — separator, header in @inverse_primary, separator, then WS buttons
                const wsSepTop = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
                wsSepTop.set_margin_top(4);
                wsSepTop.set_margin_bottom(4);
                actionsBox.append(wsSepTop);

                const wsMenuLabel = Gtk.Label.new('Move to Workspace');
                wsMenuLabel.set_halign(Gtk.Align.CENTER);
                wsMenuLabel.add_css_class('popover-section-header');
                actionsBox.append(wsMenuLabel);

                const wsSepBottom = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
                wsSepBottom.set_margin_top(4);
                wsSepBottom.set_margin_bottom(4);
                actionsBox.append(wsSepBottom);

                for (let i = 1; i <= 10; i++) {
                    const wsBtn = Gtk.Button.new_with_label('→ WS ' + i);
                    wsBtn.add_css_class('popover-item');
                    wsBtn.add_css_class('popover-action');
                    wsBtn.set_halign(Gtk.Align.FILL);
                    wsBtn.connect('clicked', () => {
                        this.daemon.hyprctl('dispatch movetoworkspace ' + i + ',address:' + instance.address);
                        sidePopover.popdown();
                        mainPopover.popdown();
                    });
                    actionsBox.append(wsBtn);
                }

                sidePopover.set_child(actionsBox);

                // Hover to open side popover.
                // Close any previously open side popover first so Wayland's
                // single-grab-chain constraint is never violated.
                const hoverCtrl = new Gtk.EventControllerMotion();
                hoverCtrl.connect('enter', () => {
                    if (openSidePopover && openSidePopover !== sidePopover) {
                        openSidePopover.popdown();
                    }
                    openSidePopover = sidePopover;
                    sidePopover.popup();
                });
                focusBtn.add_controller(hoverCtrl);

                // Close when mouse leaves the actions box; clear the shared ref.
                const actionsHoverCtrl = new Gtk.EventControllerMotion();
                actionsHoverCtrl.connect('leave', () => {
                    sidePopover.popdown();
                    if (openSidePopover === sidePopover) openSidePopover = null;
                });
                actionsBox.add_controller(actionsHoverCtrl);

                menuBox.append(focusBtn);

                // Separator between instances
                if (idx < data.instances.length - 1) {
                    const sep = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
                    sep.set_margin_top(4);
                    sep.set_margin_bottom(4);
                    menuBox.append(sep);
                }
            });
        }

        // --- GPU to Launch New Window (shown for ALL apps, running or not) ---
        const gpus = this.daemon.getAvailableGPUs();
        if (gpus.length > 0) {
            // Single separator between instances and GPU section
            if (data.instances.length > 0) {
                const gpuSepTop = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
                gpuSepTop.set_margin_top(4);
                gpuSepTop.set_margin_bottom(4);
                menuBox.append(gpuSepTop);
            }

            // Section header — centred, @inverse_primary colour via CSS class
            const gpuHeader = Gtk.Label.new('GPU to Launch New Window');
            gpuHeader.set_halign(Gtk.Align.CENTER);
            gpuHeader.add_css_class('popover-section-header');
            menuBox.append(gpuHeader);

            const gpuSepBottom = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            gpuSepBottom.set_margin_top(4);
            gpuSepBottom.set_margin_bottom(4);
            menuBox.append(gpuSepBottom);

            for (const gpu of gpus) {
                const gpuBtn = Gtk.Button.new_with_label(gpu);
                gpuBtn.add_css_class('popover-item');
                gpuBtn.add_css_class('popover-action');
                gpuBtn.set_halign(Gtk.Align.FILL);
                gpuBtn.connect('clicked', () => {
                    this.daemon.launchWithGPU(data.iconClass || data.className, gpu);
                    mainPopover.popdown();
                });
                menuBox.append(gpuBtn);
            }
            // Separator after GPU section
            const gpuSepAfter = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            gpuSepAfter.set_margin_top(4);
            gpuSepAfter.set_margin_bottom(4);
            menuBox.append(gpuSepAfter);
        } else {
            // No GPU detection — plain "New Window" fallback
            const newWinBtn = Gtk.Button.new_with_label('New Window');
            newWinBtn.add_css_class('popover-item');
            newWinBtn.set_halign(Gtk.Align.FILL);
            newWinBtn.connect('clicked', () => {
                const execCmd = this.daemon.getExecFromDesktop(data.iconClass || data.className);
                GLib.spawn_command_line_async(execCmd || (data.iconClass || data.className).toLowerCase());
                mainPopover.popdown();
            });
            menuBox.append(newWinBtn);
            // Separator after New Window button
            const newWinSep = Gtk.Separator.new(Gtk.Orientation.HORIZONTAL);
            newWinSep.set_margin_top(4);
            newWinSep.set_margin_bottom(4);
            menuBox.append(newWinSep);
        }

        // Close all windows (only when multiple instances running)
        if (data.instances.length > 1) {
            const closeAllBtn = Gtk.Button.new_with_label('Close All Windows');
            closeAllBtn.add_css_class('popover-item');
            closeAllBtn.set_halign(Gtk.Align.FILL);
            closeAllBtn.connect('clicked', () => {
                for (const instance of data.instances) {
                    this.daemon.closeWindow(instance.address);
                }
                mainPopover.popdown();
            });
            menuBox.append(closeAllBtn);
        }

        // Pin / Unpin - always show at bottom
        const pinBtn = Gtk.Button.new_with_label(data.pinned ? 'Unpin' : 'Pin');
        pinBtn.add_css_class('popover-item');
        pinBtn.set_halign(Gtk.Align.FILL);
        pinBtn.connect('clicked', () => {
            this.daemon.togglePin(data.iconClass || data.className);
            mainPopover.popdown();
            // Async refresh after pin state changes
            GLib.timeout_add(GLib.PRIORITY_DEFAULT_IDLE, 150, () => {
                this._updateFromDaemon(this.daemon.getClientData());
                return false;
            });
        });
        menuBox.append(pinBtn);

        mainPopover.set_child(menuBox);
        mainPopover.popup();
    }

    _showStartMenu(parentButton) {
        // Calculate popover position based on dock position
        let mainPopPos, mainOffX, mainOffY;
        const _gap = 8;
        
        if (IS_VERTICAL) {
            mainPopPos = (DockConfig.position === 'left') ? Gtk.PositionType.RIGHT : Gtk.PositionType.LEFT;
            mainOffX = _gap;
            mainOffY = 0;
        } else {
            mainPopPos = (DockConfig.position === 'bottom') ? Gtk.PositionType.TOP : Gtk.PositionType.BOTTOM;
            mainOffX = 0;
            mainOffY = -_gap;
        }

        // Create popover
        const popover = new Gtk.Popover();
        popover.set_parent(parentButton);
        popover.set_has_arrow(false);
        popover.set_position(mainPopPos);
        popover.add_css_class('dock-popover');
        popover.set_offset(mainOffX, mainOffY);
        
        // Apply styling
        const styleContext = popover.get_style_context();
        styleContext.add_provider(this._getPopoverCSSProvider(), Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        // Create menu content
        const menuBox = Gtk.Box.new(Gtk.Orientation.VERTICAL, 0);
        menuBox.set_margin_top(4);
        menuBox.set_margin_bottom(4);
        menuBox.set_size_request(40, 6);

        // Settings button
        const settingsBtn = Gtk.Button.new_with_label('Toggle Hyprland Settings');
        settingsBtn.add_css_class('popover-item');
        settingsBtn.set_halign(Gtk.Align.FILL);
        settingsBtn.connect('clicked', () => {
            GLib.spawn_command_line_async('bash -c "$HOME/.hyprcandy/GJS/toggle-hyprland-settings.sh"');
            popover.popdown();
        });
        menuBox.append(settingsBtn);

        popover.set_child(menuBox);
        popover.popup();
    }

    _getPopoverCSSProvider() {
        if (!this._popoverCSSProvider) {
            this._popoverCSSProvider = new Gtk.CssProvider();
            // GTK4 popovers have a 'contents' node that needs explicit background.
            // We must NOT @import gtk.css as it resets our rules.
            const popoverCSS = `
                popover.dock-popover {
                    background-color: transparent;
                    border: none;
                    border-radius: 12px;
                    color: @primary;
                }
                popover.dock-popover > contents {
                    background-color: @on_secondary;
                    border-radius: 12px;
                    border: 1px solid alpha(@secondary, 0.5);
                    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
                    color: @primary;
                }
                popover.dock-popover > arrow {
                    background-color: @on_secondary;
                }
                popover.dock-popover > contents separator {
                    background-color: @secondary;
                    min-height: 1px;
                }
                popover.dock-popover .popover-item {
                    background: transparent;
                    background-color: transparent;
                    color: @primary;
                    padding: 6px 12px;
                    border-radius: 6px;
                    border: none;
                    box-shadow: none;
                }
                popover.dock-popover .popover-item:hover {
                    background-color: alpha(@primary, 0.12);
                }
                popover.dock-popover .popover-action {
                    font-size: 12px;
                    padding: 4px 10px;
                }
                popover.dock-popover .popover-sublabel {
                    font-size: 11px;
                    font-weight: bold;
                    color: @primary;
                    padding: 4px 12px 2px 12px;
                }
                popover.dock-popover .popover-section-header {
                    font-size: 11px;
                    font-weight: bold;
                    color: @inverse_primary;
                    padding: 4px 12px 2px 12px;
                    margin-top: 2px;
                }
            `;
            this._popoverCSSProvider.load_from_data(popoverCSS, -1);
        }
        return this._popoverCSSProvider;
    }

    vfunc_close_request() {
        teardownColorMonitor();
        this.daemon.shutdown();
        return false;
    }
});

// --- Application ------------------------------------------------------
const DockApplication = GObject.registerClass({
    GTypeName: 'HyprCandyDockApplication',
}, class DockApplication extends Gtk.Application {
    vfunc_activate() {
        // Load CSS (static providers: GTK3/4 colours + style.css)
        loadCSS();

        // Watch gtk-4.0/colors.css so matugen theme changes hot-reload colours
        setupColorMonitor();

        // Create dock
        dockWindow = new HyprCandyDock(this);
        this.add_window(dockWindow);
    }
});

// --- Signal handler (module scope) -----------------------------------
// Registered HERE — before app.run() — so there is zero race window
// between process start and the handler being active.
//
// SIGUSR2 (12) is the hot-reload signal.  SIGUSR1 (10) is reserved by GJS
// for internal heap-dump / profiling when --profile is active.
// candy-utils reloads the dock with:
//   pkill -12 -f 'gjs dock-main.js'
GLibUnix.signal_add_full(GLib.PRIORITY_DEFAULT, 12, () => {
    hotReload();
    return GLib.SOURCE_CONTINUE;
});
log('[dock] SIGUSR2 (12) handler registered — send with: pkill -12 -f \'gjs dock-main.js\'');

// --- Launch -----------------------------------------------------------
const app = new DockApplication({
    application_id: 'com.hyprcandy.dock',
    flags: Gio.ApplicationFlags.NON_UNIQUE,
});
app.run(ARGV);
