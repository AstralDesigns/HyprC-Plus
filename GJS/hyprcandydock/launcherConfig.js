// HyprCandy App Launcher — Configuration
// Edit these values then restart the launcher (toggle-app-launcher.sh).
// These will later be exposed in the QuickShell Control Center → Menus tab.
//
// All numeric values are in pixels unless noted.

var LauncherConfig = {

    // ── Search bar width ──────────────────────────────────────────────
    searchWidthFraction: 0.20,       // @LC:searchWidthFraction

    // ── Icon size ─────────────────────────────────────────────────────
    iconSize: 44,                   // @LC:iconSize

    // ── Label font size ───────────────────────────────────────────────
    textFontSize: 14,               // @LC:textFontSize

    // ── App tile cell size ────────────────────────────────────────────
    // 0 = auto (iconSize + padding). The grid reflows to more columns
    // as the window grows instead of stretching tiles.
    tileWidth: 0,                  // @LC:tileWidth
    tileHeight: 0,                  // @LC:tileHeight

    // ── Main frame — horizontal dock (bottom / top) ───────────────────
    frameWidth: 1175,               // @LC:frameWidth
    frameHeight: 645,               // @LC:frameHeight

    // ── Main frame — vertical dock (left / right) ─────────────────────
    frameWidthVert: 1175,           // @LC:frameWidthVert
    frameHeightVert: 645,           // @LC:frameHeightVert

    // ── Border ────────────────────────────────────────────────────────
    borderRadius: 18,               // @LC:borderRadius
    borderWidth: 2,                // @LC:borderWidth
    searchRadius: 30,               // @LC:searchRadius
    listRadius: 16,               // @LC:listRadius
    innerBorderWidth: 0,            // @LC:innerBorderWidth

    // ── Inner frame padding ───────────────────────────────────────────
    innerPadding: 10,               // @LC:innerPadding
};
