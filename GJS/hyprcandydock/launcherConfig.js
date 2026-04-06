// HyprCandy App Launcher — Configuration
// Edit these values then restart the launcher (toggle-app-launcher.sh).
// These will later be exposed in the QuickShell Control Center → Menus tab.
//
// All numeric values are in pixels unless noted.

var LauncherConfig = {

    // ── Search bar width ──────────────────────────────────────────────
    searchWidthFraction: 0.25,       // @LC:searchWidthFraction

    // ── Icon size ─────────────────────────────────────────────────────
    iconSize: 48,                   // @LC:iconSize

    // ── Label font size ───────────────────────────────────────────────
    textFontSize: 14,               // @LC:textFontSize

    // ── App tile cell size ────────────────────────────────────────────
    // 0 = auto (iconSize + padding). The grid reflows to more columns
    // as the window grows instead of stretching tiles.
    tileWidth:  0,                  // @LC:tileWidth
    tileHeight: 0,                  // @LC:tileHeight

    // ── Main frame — horizontal dock (bottom / top) ───────────────────
    frameWidth:  700,               // @LC:frameWidth
    frameHeight: 620,               // @LC:frameHeight

    // ── Main frame — vertical dock (left / right) ─────────────────────
    frameWidthVert:  700,           // @LC:frameWidthVert
    frameHeightVert: 620,           // @LC:frameHeightVert

    // ── Border ────────────────────────────────────────────────────────
    borderRadius: 20,               // @LC:borderRadius
    borderWidth:  2,                // @LC:borderWidth
    searchRadius: 19,               // @LC:searchRadius
    listRadius:   12,               // @LC:listRadius
    innerBorderWidth: 2,            // @LC:innerBorderWidth

    // ── Inner frame padding ───────────────────────────────────────────
    innerPadding: 10,               // @LC:innerPadding
};
