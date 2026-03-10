// HyprCandy Dock — Configuration
// All visual and layout values live here.
// Restart the dock after editing: pkill -f "gjs dock-main.js" && ./launch-modular.sh
//
// ── candy-utils integration ───────────────────────────────────────────────────
// Variables tagged with @HCD:<name> are the ones candy-utils.js should edit.
// Each tag is unique in the file so sed can target it unambiguously.
//
// Numeric @HCD variables (replace N with new value):
//   sed -i 's/appIconSize:[ \t]*[0-9]*/appIconSize: N/' config.js
//
// String @HCD variables (replace GLYPH with new character or escape):
//   sed -i "s/startIcon: '[^']*'/startIcon: 'GLYPH'/" config.js
//
// Same pattern applies to all @HCD-tagged variables — just swap the key name.
// ─────────────────────────────────────────────────────────────────────────────

var DockConfig = {

    // ── Start button icon (NerdFont glyph) ────────────────────────────────
    // Paste any glyph directly (use rofi glyph menu or any NerdFont codepoint).
    // null = fall back to the GLYPH_START const in dock-main.js.
    // candy-utils sed pattern:  sed -i "s/startIcon: '[^']*'/startIcon: 'GLYPH'/" config.js
    startIcon: '󱗼',               // @HCD:startIcon

    // ── Button spacing (gap between every button in the dock) ─────────────
    // Controls GtkBox spacing — applies uniformly between start↔first-app,
    // app↔app, and last-app↔trash so all gaps are edited in one place.
    buttonSpacing: 2,              // @HCD:buttonSpacing

    // ── App icon size (Gtk.Image pixel_size) ─────────────────────────────
    // Controls Gtk.Image icons from the theme (e.g. Nautilus, Firefox).
    // This is the primary value used for exclusive-zone and button footprint.
    appIconSize: 20,               // @HCD:appIconSize

    // ── Glyph icon size (NerdFont unicode labels) ────────────────────────
    // Controls start, trash, and fallback glyph font-size independently.
    // NerdFont glyphs render SMALLER than Gtk.Image at the same numeric value
    // because the font bounding box includes internal whitespace. The auto
    // formula multiplies by glyphIconSizeFraction (default 1.1) to compensate.
    // Set glyphIconSize to an explicit px value to override auto-derive.
    glyphIconSize: null,
    glyphIconSizeFraction: 1.0,   // auto = round(appIconSize * this)

    // ── Indicator size ───────────────────────────────────────────────────
    // Active-window dot font-size in px. Set null to auto-derive.
    // Auto = max(4, round(appIconSize * indicatorSizeFraction))
    indicatorSize: null,
    indicatorSizeFraction: 0.18,  // used when indicatorSize is null
    indicatorSpacing: 4,          // px gap between two dots

    // ── Legacy alias ─────────────────────────────────────────────────────
    // For backward compat. Reads appIconSize.
    get iconSize() { return this.appIconSize; },

    // ── Internal padding ──────────────────────────────────────────────────
    // Space between the icons and the dock outer edges (px).
    innerPadding: 0,               // @HCD:innerPadding

    // ── Border ────────────────────────────────────────────────────────────
    borderWidth: 2,                // @HCD:borderWidth
    borderRadius: 10,              // @HCD:borderRadius

    // ── External margins (dock edge ↔ screen / window edge) ──────────────
    // The exclusive zone is auto-calculated from the rendered content height:
    //   exclusiveZone = mainBox.naturalHeight + borderWidth*2
    // The compositor adds the anchored-edge margin (e.g. marginBottom for a
    // bottom dock) on top of that automatically.  Hyprland's own gaps_out +
    // border_size provide the gap between windows and the reserved boundary.
    // Set exclusiveZoneOverride (number) to force a specific value.
    exclusiveZoneOverride: null,

    marginBottom: 6,               // @HCD:marginBottom
    marginLeft:   10,              // @HCD:marginLeft
    marginRight:  10,              // @HCD:marginRight
    marginTop:    2,               // @HCD:marginTop

    // ── Popover gaps ─────────────────────────────────────────────────────
    popoverGapDock: 12,   // px between dock border and first popover
    popoverGapSide: 12,   // px between first popover and side popover

    // ── Position ──────────────────────────────────────────────────────────
    // Overridden at runtime by CLI flag: gjs dock-main.js [-b | -t | -l | -r]
    position: 'bottom',

    // ── Debounce ──────────────────────────────────────────────────────────
    refreshDebounceMs: 80,

    // ── Position-specific overrides ───────────────────────────────────────
    // Override any base config values for specific dock positions.
    // Only specify values you want to change; unspecified values inherit
    // from the base config above.
    //
    // Example: if you want a thicker border for left dock:
    //   positionOverrides: { left: { borderWidth: 4 } }
    positionOverrides: {
        left: {
            marginLeft:   6,   // screen edge gap
            marginRight:  2,   // window-side gap
            marginTop:    0,
            marginBottom: 0,
        },
        right: {
            marginRight:  6,   // screen edge gap
            marginLeft:   2,   // window-side gap
            marginTop:    0,
            marginBottom: 0,
        },
        top: {
            marginTop:    6,   // screen edge gap
            marginBottom: 0,   // window-side gap
            // marginLeft / marginRight inherit base (10px)
        },
        bottom: {
            marginRight: 10,
            marginLeft: 10,
            marginTop: 2,
            // Inherits all base values (marginBottom:6, marginTop:2, left/right:10)
        },
    },
};
