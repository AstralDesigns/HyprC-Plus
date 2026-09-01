// HyprCandy App Launcher — Configuration
// Edit these values then restart the launcher (toggle-app-launcher.sh).
// These will later be exposed in the QuickShell Control Center → Menus tab.
//
// All numeric values are in pixels unless noted.

var LauncherConfig = {

    // ── Icon size ─────────────────────────────────────────────────────
    // Pixel size for the app icons in the grid.
    iconSize: 48,                   // @LC:iconSize

    // ── Main frame — horizontal dock (bottom / top) ───────────────────
    frameWidth: 500,               // @LC:frameWidth
    frameHeight: 480,               // @LC:frameHeight

    // ── Main frame — vertical dock (left / right) ─────────────────────
    frameWidthVert: 380,           // @LC:frameWidthVert
    frameHeightVert: 560,           // @LC:frameHeightVert

    // ── Border ────────────────────────────────────────────────────────
    // Applies to the outer window AND the inner search/list frames.
    borderRadius: 20,               // @LC:borderRadius   (outer window)
    borderWidth: 2,                // @LC:borderWidth    (outer window)
    innerRadius: 12,               // @LC:innerRadius    (search + list boxes)
    innerBorderWidth: 0,            // @LC:innerBorderWidth

    // ── Inner frame padding ───────────────────────────────────────────
    // Gap between the outer window border and the inner search/list boxes.
    innerPadding: 10,               // @LC:innerPadding   (px, all sides)
};
