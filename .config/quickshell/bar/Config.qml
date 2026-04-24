pragma Singleton

import QtQuick
import QtCore
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  Config.qml — Single source of truth for all bar behaviour and appearance.
//  Edit here; future control-center UI will write these values at runtime.
//
//  PERSISTENCE: All values are saved to ~/.config/hyprcandy/qs_bar_config.json
//  and loaded on startup. Fresh installs use defaults below.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: cfg

    // ── Set application identifiers for Settings ───────────────────────────
    Component.onCompleted: {
        Qt.application.name = "hyprcandy-bar"
        Qt.application.organization = "hyprcandy"
        Qt.application.organizationDomain = "hyprcandy.local"
        // Load persisted values after properties are initialized
        _loadSettings()
    }

    // ── Settings persistence helper ────────────────────────────────────────
    property Settings _settings: Settings { category: "qs-bar-config-v1" }
    // Auto-save every 5 seconds
    property Timer _saveTimer: Timer {
        interval: 5000
        repeat: true
        running: true
        onTriggered: _saveSettings()
    }

    // QSettings INI backend stores booleans as "true"/"false" strings.
    // On read they come back as strings — coerce them to proper bools.
    function _toBool(v) {
        if (v === true || v === 1) return true
        if (v === false || v === 0) return false
        if (typeof v === "string") {
            const s = v.toLowerCase().trim()
            if (s === "true" || s === "1" || s === "yes") return true
            if (s === "false" || s === "0" || s === "no") return false
        }
        return !!v  // fallback
    }

    function _loadSettings() {
        // cavaGradientEndColor is now computed from cavaEndMode/cavaEndVar — no seed needed
        // Tab 1: General
        var v = _settings.value("barMode"); if (v !== undefined && v !== null) barMode = v
        v = _settings.value("barPosition"); if (v !== undefined && v !== null) barPosition = v
        v = _settings.value("barHeight"); if (v !== undefined && v !== null) barHeight = v
        v = _settings.value("moduleHeight"); if (v !== undefined && v !== null) moduleHeight = v
        v = _settings.value("outerMarginTop"); if (v !== undefined && v !== null) outerMarginTop = v
        v = _settings.value("outerMarginBottom"); if (v !== undefined && v !== null) outerMarginBottom = v
        v = _settings.value("outerMarginSide"); if (v !== undefined && v !== null) outerMarginSide = v
        v = _settings.value("barEdgePaddingLeft");  if (v !== undefined && v !== null) barEdgePaddingLeft  = v
        v = _settings.value("barEdgePaddingRight"); if (v !== undefined && v !== null) barEdgePaddingRight = v
        v = _settings.value("barRadius"); if (v !== undefined && v !== null) barRadius = v
        v = _settings.value("islandRadius"); if (v !== undefined && v !== null) islandRadius = v
        v = _settings.value("islandBorder"); if (v !== undefined && v !== null) islandBorder = v
        v = _settings.value("islandBorderAlpha"); if (v !== undefined && v !== null) islandBorderAlpha = v
        v = _settings.value("barBorderWidth"); if (v !== undefined && v !== null) barBorderWidth = v
        v = _settings.value("barBorderAlpha"); if (v !== undefined && v !== null) barBorderAlpha = v
        v = _settings.value("islandBgStyle");  if (v !== undefined && v !== null) islandBgStyle  = v
        v = _settings.value("barRectBgStyle"); if (v !== undefined && v !== null) barRectBgStyle = v
        v = _settings.value("moduleBgOpacity"); if (v !== undefined && v !== null) moduleBgOpacity = v
        v = _settings.value("islandBgOpacityIsland"); if (v !== undefined && v !== null) islandBgOpacityIsland = v
        v = _settings.value("islandSpacing"); if (v !== undefined && v !== null) islandSpacing = v
        v = _settings.value("modPadH"); if (v !== undefined && v !== null) modPadH = v
        v = _settings.value("modPadV"); if (v !== undefined && v !== null) modPadV = v
        v = _settings.value("groupedSpacing"); if (v !== undefined && v !== null) groupedSpacing = v
        v = _settings.value("glyphSize"); if (v !== undefined && v !== null) glyphSize = v
        v = _settings.value("infoGlyphSize"); if (v !== undefined && v !== null) infoGlyphSize = v
        v = _settings.value("mediaGlyphSize"); if (v !== undefined && v !== null) mediaGlyphSize = v
        v = _settings.value("infoFontSize");   if (v !== undefined && v !== null) infoFontSize   = v
        v = _settings.value("labelFontSize");  if (v !== undefined && v !== null) labelFontSize  = v
        v = _settings.value("mediaPlayPauseSize"); if (v !== undefined && v !== null) mediaPlayPauseSize = v
        v = _settings.value("mediaThumbSize"); if (v !== undefined && v !== null) mediaThumbSize = v
        v = _settings.value("batteryRadialVisible"); if (v !== undefined && v !== null) batteryRadialVisible = _toBool(v)
        v = _settings.value("batteryRadialSize"); if (v !== undefined && v !== null) batteryRadialSize = v
        v = _settings.value("batteryRadialWidth"); if (v !== undefined && v !== null) batteryRadialWidth = v
        v = _settings.value("trayIconSz"); if (v !== undefined && v !== null) trayIconSz = v
        v = _settings.value("trayItemPadH");   if (v !== undefined && v !== null) trayItemPadH   = v
        v = _settings.value("trayItemSpacing"); if (v !== undefined && v !== null) trayItemSpacing = v
        v = _settings.value("ccGlyph"); if (v !== undefined && v !== null) ccGlyph = v
        v = _settings.value("ccGlyphColorA"); if (v !== undefined && v !== null) ccGlyphOpacity = Math.min(1, Math.max(0, parseFloat(v)))
        v = _settings.value("wsIconMode"); if (v !== undefined && v !== null) wsIconMode = v
        v = _settings.value("wsGlyphSize"); if (v !== undefined && v !== null) wsGlyphSize = v
        v = _settings.value("wsSpacing"); if (v !== undefined && v !== null) wsSpacing = v
        v = _settings.value("wsMarginLeft"); if (v !== undefined && v !== null) wsMarginLeft = v
        v = _settings.value("wsMarginRight"); if (v !== undefined && v !== null) wsMarginRight = v
        v = _settings.value("wsPadLeft"); if (v !== undefined && v !== null) wsPadLeft = v
        v = _settings.value("wsPadRight"); if (v !== undefined && v !== null) wsPadRight = v
        v = _settings.value("wsPadTop"); if (v !== undefined && v !== null) wsPadTop = v
        v = _settings.value("wsPadBottom"); if (v !== undefined && v !== null) wsPadBottom = v
        v = _settings.value("wsSeparators"); if (v !== undefined && v !== null) wsSeparators = _toBool(v)
        v = _settings.value("wsSeparatorSize"); if (v !== undefined && v !== null) wsSeparatorSize = v
        v = _settings.value("wsSeparatorPadLeft"); if (v !== undefined && v !== null) wsSeparatorPadLeft = v
        v = _settings.value("wsSeparatorPadRight"); if (v !== undefined && v !== null) wsSeparatorPadRight = v
        v = _settings.value("wsSeparatorGlyph"); if (v !== undefined && v !== null) wsSeparatorGlyph = v
        v = _settings.value("wsDotActive"); if (v !== undefined && v !== null) wsDotActive = v
        v = _settings.value("wsDotPersistent"); if (v !== undefined && v !== null) wsDotPersistent = v
        v = _settings.value("wsDotEmpty"); if (v !== undefined && v !== null) wsDotEmpty = v
        v = _settings.value("wsIcons"); if (v !== undefined && v !== null) { try { wsIcons = JSON.parse(v) } catch(e) {} }
        v = _settings.value("wsActiveOpacity");     if (v !== undefined && v !== null) wsActiveOpacity     = v
        v = _settings.value("wsPersistentOpacity"); if (v !== undefined && v !== null) wsPersistentOpacity = v
        v = _settings.value("wsEmptyOpacity");      if (v !== undefined && v !== null) wsEmptyOpacity      = v
        v = _settings.value("wsSeparatorOpacity");  if (v !== undefined && v !== null) wsSeparatorOpacity  = v
        v = _settings.value("mediaInfoFontSize"); if (v !== undefined && v !== null) mediaInfoFontSize = v
        v = _settings.value("mediaPadLeft"); if (v !== undefined && v !== null) mediaPadLeft = v
        v = _settings.value("mediaPadRight"); if (v !== undefined && v !== null) mediaPadRight = v
        v = _settings.value("mediaPadTop"); if (v !== undefined && v !== null) mediaPadTop = v
        v = _settings.value("mediaPadBottom"); if (v !== undefined && v !== null) mediaPadBottom = v
        v = _settings.value("cavaWidth"); if (v !== undefined && v !== null) cavaWidth = v
        v = _settings.value("cavaBarSpacing"); if (v !== undefined && v !== null) cavaBarSpacing = v
        v = _settings.value("cavaStyle"); if (v !== undefined && v !== null) cavaStyle = v
        v = _settings.value("cavaTransparentWhenInactive"); if (v !== undefined && v !== null) cavaTransparentWhenInactive = _toBool(v)
        v = _settings.value("cavaActiveOpacity"); if (v !== undefined && v !== null) cavaActiveOpacity = v
        v = _settings.value("cavaInactiveOpacity"); if (v !== undefined && v !== null) cavaInactiveOpacity = v
        v = _settings.value("cavaAutoHide"); if (v !== undefined && v !== null) cavaAutoHide = _toBool(v)
        v = _settings.value("cavaGradientEnabled"); if (v !== undefined && v !== null) cavaGradientEnabled = _toBool(v)
        v = _settings.value("cavaGradientSplit"); if (v !== undefined && v !== null) cavaGradientSplit = parseFloat(v)
        v = _settings.value("cavaStartMode"); if (v !== undefined && v !== null) cavaStartMode = v
        v = _settings.value("cavaEndMode");   if (v !== undefined && v !== null) cavaEndMode   = v
        v = _settings.value("cavaStartVar");  if (v !== undefined && v !== null) cavaStartVar  = v
        v = _settings.value("cavaEndVar");    if (v !== undefined && v !== null) cavaEndVar    = v
        v = _settings.value("cavaStartPywalVar"); if (v !== undefined && v !== null) cavaStartPywalVar = v
        v = _settings.value("cavaEndPywalVar");   if (v !== undefined && v !== null) cavaEndPywalVar   = v
        v = _settings.value("cavaStartCustomColor"); if (v !== undefined && v !== null) _cavaStartCustomColor = v
        v = _settings.value("cavaEndCustomColor");   if (v !== undefined && v !== null) _cavaEndCustomColor   = v
        v = _settings.value("cavaGlyphCustomColor"); if (v !== undefined && v !== null) _cavaGlyphCustomColor = v
        v = _settings.value("wsBgOpacity"); if (v !== undefined && v !== null) wsBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("groupedBgOpacity"); if (v !== undefined && v !== null) groupedBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("ungroupedBgOpacity"); if (v !== undefined && v !== null) ungroupedBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("trayBgOpacity"); if (v !== undefined && v !== null) trayBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("startMenuBgOpacity"); if (v !== undefined && v !== null) startMenuBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("mediaBgOpacity"); if (v !== undefined && v !== null) mediaBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("cavaBgOpacity"); if (v !== undefined && v !== null) cavaBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("distroBgOpacity"); if (v !== undefined && v !== null) distroBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("activeWindowBgOpacity"); if (v !== undefined && v !== null) activeWindowBgOpacity = v
        v = _settings.value("activeWindowMinWidth"); if (v !== undefined && v !== null) activeWindowMinWidth = v
        v = _settings.value("showCava"); if (v !== undefined && v !== null) showCava = _toBool(v)
        v = _settings.value("showWeather"); if (v !== undefined && v !== null) showWeather = _toBool(v)
        v = _settings.value("showBattery"); if (v !== undefined && v !== null) showBattery = _toBool(v)
        v = _settings.value("showMediaPlayer"); if (v !== undefined && v !== null) showMediaPlayer = _toBool(v)
        v = _settings.value("showIdleInhibitor"); if (v !== undefined && v !== null) showIdleInhibitor = _toBool(v)
        v = _settings.value("showRofi"); if (v !== undefined && v !== null) showRofi = _toBool(v)
        v = _settings.value("showUpdates"); if (v !== undefined && v !== null) showUpdates = _toBool(v)
        v = _settings.value("showPowerProfiles"); if (v !== undefined && v !== null) showPowerProfiles = _toBool(v)
        v = _settings.value("showOverview"); if (v !== undefined && v !== null) showOverview = _toBool(v)
        v = _settings.value("showNotifications"); if (v !== undefined && v !== null) showNotifications = _toBool(v)
        v = _settings.value("showWallpaper"); if (v !== undefined && v !== null) showWallpaper = _toBool(v)
        v = _settings.value("showTray"); if (v !== undefined && v !== null) showTray = _toBool(v)
        v = _settings.value("showBluetooth"); if (v !== undefined && v !== null) showBluetooth = _toBool(v)
        //v = _settings.value("showWindow"); if (v !== undefined && v !== null) showWindow = v
        v = _settings.value("showDistro"); if (v !== undefined && v !== null) showDistro = _toBool(v)
        // ── Launcher (GJS app-launcher) ───────────────────────────────────
        v = _settings.value("launcherSearchWidth");    if (v !== undefined && v !== null) launcherSearchWidth    = v
        v = _settings.value("launcherIconSize");       if (v !== undefined && v !== null) launcherIconSize       = v
        v = _settings.value("launcherTextFontSize");   if (v !== undefined && v !== null) launcherTextFontSize   = v
        v = _settings.value("launcherFixedTileWidth"); if (v !== undefined && v !== null) launcherFixedTileWidth = v
        v = _settings.value("launcherFixedTileHeight");if (v !== undefined && v !== null) launcherFixedTileHeight= v
        v = _settings.value("launcherFrameWidth");     if (v !== undefined && v !== null) launcherFrameWidth     = v
        v = _settings.value("launcherFrameHeight");    if (v !== undefined && v !== null) launcherFrameHeight    = v
        v = _settings.value("launcherFrameWidthVert"); if (v !== undefined && v !== null) launcherFrameWidthVert = v
        v = _settings.value("launcherFrameHeightVert");if (v !== undefined && v !== null) launcherFrameHeightVert= v
        v = _settings.value("launcherBorderRadius");   if (v !== undefined && v !== null) launcherBorderRadius   = v
        v = _settings.value("launcherBorderWidth");    if (v !== undefined && v !== null) launcherBorderWidth    = v
        v = _settings.value("launcherSearchRadius");   if (v !== undefined && v !== null) launcherSearchRadius   = v
        v = _settings.value("launcherListRadius");     if (v !== undefined && v !== null) launcherListRadius     = v
        v = _settings.value("launcherInnerBorderWidth");if(v !== undefined && v !== null) launcherInnerBorderWidth=v
        v = _settings.value("launcherInnerPadding");   if (v !== undefined && v !== null) launcherInnerPadding   = v
        // Bar autohide + dock runtime state
        v = _settings.value("barAutoHide");      if (v !== undefined && v !== null) barAutoHide      = _toBool(v)
        v = _settings.value("barAutoHideDelay"); if (v !== undefined && v !== null) barAutoHideDelay = parseInt(v) || 5
        v = _settings.value("dockAutoHide");     if (v !== undefined && v !== null) dockAutoHide     = _toBool(v)
        v = _settings.value("dockAutoHideDelay");if (v !== undefined && v !== null) dockAutoHideDelay= parseInt(v) || 5
        v = _settings.value("dockMargin");       if (v !== undefined && v !== null) dockMargin       = parseInt(v) || 6
    }

    function _saveSettings() {
        _settings.setValue("barMode", barMode)
        _settings.setValue("barPosition", barPosition)
        _settings.setValue("barHeight", barHeight)
        _settings.setValue("moduleHeight", moduleHeight)
        _settings.setValue("outerMarginTop", outerMarginTop)
        _settings.setValue("outerMarginBottom", outerMarginBottom)
        _settings.setValue("outerMarginSide", outerMarginSide)
        _settings.setValue("barEdgePaddingLeft",  barEdgePaddingLeft)
        _settings.setValue("barEdgePaddingRight", barEdgePaddingRight)
        _settings.setValue("barRadius", barRadius)
        _settings.setValue("islandRadius", islandRadius)
        _settings.setValue("islandBorder", islandBorder)
        _settings.setValue("islandBorderAlpha", islandBorderAlpha)
        _settings.setValue("barBorderWidth", barBorderWidth)
        _settings.setValue("barBorderAlpha", barBorderAlpha)
        _settings.setValue("islandBgStyle",  islandBgStyle)
        _settings.setValue("barRectBgStyle", barRectBgStyle)
        _settings.setValue("moduleBgOpacity", moduleBgOpacity)
        _settings.setValue("islandBgOpacityIsland", islandBgOpacityIsland)
        _settings.setValue("islandSpacing", islandSpacing)
        _settings.setValue("modPadH", modPadH)
        _settings.setValue("modPadV", modPadV)
        _settings.setValue("groupedSpacing", groupedSpacing)
        _settings.setValue("glyphSize", glyphSize)
        _settings.setValue("infoGlyphSize", infoGlyphSize)
        _settings.setValue("mediaGlyphSize", mediaGlyphSize)
        _settings.setValue("infoFontSize",   infoFontSize)
        _settings.setValue("labelFontSize",  labelFontSize)
        _settings.setValue("mediaPlayPauseSize", mediaPlayPauseSize)
        _settings.setValue("mediaThumbSize", mediaThumbSize)
        _settings.setValue("batteryRadialVisible", batteryRadialVisible)
        _settings.setValue("batteryRadialSize", batteryRadialSize)
        _settings.setValue("batteryRadialWidth", batteryRadialWidth)
        _settings.setValue("trayIconSz", trayIconSz)
        _settings.setValue("trayItemPadH",    trayItemPadH)
        _settings.setValue("trayItemSpacing", trayItemSpacing)
        _settings.setValue("ccGlyph", ccGlyph)
        _settings.setValue("ccGlyphColorA", ccGlyphOpacity)
        _settings.setValue("wsIconMode", wsIconMode)
        _settings.setValue("wsGlyphSize", wsGlyphSize)
        _settings.setValue("wsSpacing", wsSpacing)
        _settings.setValue("wsMarginLeft", wsMarginLeft)
        _settings.setValue("wsMarginRight", wsMarginRight)
        _settings.setValue("wsPadLeft", wsPadLeft)
        _settings.setValue("wsPadRight", wsPadRight)
        _settings.setValue("wsPadTop", wsPadTop)
        _settings.setValue("wsPadBottom", wsPadBottom)
        _settings.setValue("wsSeparators", wsSeparators)
        _settings.setValue("wsSeparatorSize", wsSeparatorSize)
        _settings.setValue("wsSeparatorPadLeft", wsSeparatorPadLeft)
        _settings.setValue("wsSeparatorPadRight", wsSeparatorPadRight)
        _settings.setValue("wsSeparatorGlyph", wsSeparatorGlyph)
        _settings.setValue("wsDotActive", wsDotActive)
        _settings.setValue("wsDotPersistent", wsDotPersistent)
        _settings.setValue("wsDotEmpty", wsDotEmpty)
        _settings.setValue("wsIcons", JSON.stringify(wsIcons))
        _settings.setValue("wsActiveOpacity",     wsActiveOpacity)
        _settings.setValue("wsPersistentOpacity", wsPersistentOpacity)
        _settings.setValue("wsEmptyOpacity",      wsEmptyOpacity)
        _settings.setValue("wsSeparatorOpacity",  wsSeparatorOpacity)
        _settings.setValue("mediaInfoFontSize", mediaInfoFontSize)
        _settings.setValue("mediaPadLeft", mediaPadLeft)
        _settings.setValue("mediaPadRight", mediaPadRight)
        _settings.setValue("mediaPadTop", mediaPadTop)
        _settings.setValue("mediaPadBottom", mediaPadBottom)
        _settings.setValue("cavaWidth", cavaWidth)
        _settings.setValue("cavaBarSpacing", cavaBarSpacing)
        _settings.setValue("cavaStyle", cavaStyle)
        _settings.setValue("cavaTransparentWhenInactive", cavaTransparentWhenInactive)
        _settings.setValue("cavaActiveOpacity", cavaActiveOpacity)
        _settings.setValue("cavaInactiveOpacity", cavaInactiveOpacity)
        _settings.setValue("cavaAutoHide", cavaAutoHide)
        _settings.setValue("cavaGradientEnabled", cavaGradientEnabled)
        _settings.setValue("cavaGradientSplit",   cavaGradientSplit)
        _settings.setValue("cavaStartMode",        cavaStartMode)
        _settings.setValue("cavaEndMode",          cavaEndMode)
        _settings.setValue("cavaStartVar",         cavaStartVar)
        _settings.setValue("cavaEndVar",           cavaEndVar)
        _settings.setValue("cavaStartPywalVar",    cavaStartPywalVar)
        _settings.setValue("cavaEndPywalVar",      cavaEndPywalVar)
        _settings.setValue("cavaStartCustomColor", _cavaStartCustomColor)
        _settings.setValue("cavaEndCustomColor",   _cavaEndCustomColor)
        _settings.setValue("cavaGlyphCustomColor", _cavaGlyphCustomColor)
        _settings.setValue("wsBgOpacity", wsBgOpacity)
        _settings.setValue("groupedBgOpacity", groupedBgOpacity)
        _settings.setValue("ungroupedBgOpacity", ungroupedBgOpacity)
        _settings.setValue("trayBgOpacity", trayBgOpacity)
        _settings.setValue("startMenuBgOpacity", startMenuBgOpacity)
        _settings.setValue("mediaBgOpacity", mediaBgOpacity)
        _settings.setValue("cavaBgOpacity", cavaBgOpacity)
        _settings.setValue("distroBgOpacity", distroBgOpacity)
        _settings.setValue("activeWindowBgOpacity", activeWindowBgOpacity)
        _settings.setValue("activeWindowMinWidth", activeWindowMinWidth)
        _settings.setValue("showCava", showCava)
        _settings.setValue("showWeather", showWeather)
        _settings.setValue("showBattery", showBattery)
        _settings.setValue("showMediaPlayer", showMediaPlayer)
        _settings.setValue("showIdleInhibitor", showIdleInhibitor)
        _settings.setValue("showRofi", showRofi)
        _settings.setValue("showUpdates", showUpdates)
        _settings.setValue("showPowerProfiles", showPowerProfiles)
        _settings.setValue("showOverview", showOverview)
        _settings.setValue("showNotifications", showNotifications)
        _settings.setValue("showWallpaper", showWallpaper)
        _settings.setValue("showTray", showTray)
        _settings.setValue("showBluetooth", showBluetooth)
        //_settings.setValue("showWindow", showWindow)
        _settings.setValue("showDistro", showDistro)
        // ── Launcher (GJS app-launcher) ───────────────────────────────────
        _settings.setValue("launcherSearchWidth",     launcherSearchWidth)
        _settings.setValue("launcherIconSize",        launcherIconSize)
        _settings.setValue("launcherTextFontSize",    launcherTextFontSize)
        _settings.setValue("launcherFixedTileWidth",  launcherFixedTileWidth)
        _settings.setValue("launcherFixedTileHeight", launcherFixedTileHeight)
        _settings.setValue("launcherFrameWidth",      launcherFrameWidth)
        _settings.setValue("launcherFrameHeight",     launcherFrameHeight)
        _settings.setValue("launcherFrameWidthVert",  launcherFrameWidthVert)
        _settings.setValue("launcherFrameHeightVert", launcherFrameHeightVert)
        _settings.setValue("launcherBorderRadius",    launcherBorderRadius)
        _settings.setValue("launcherBorderWidth",     launcherBorderWidth)
        _settings.setValue("launcherSearchRadius",    launcherSearchRadius)
        _settings.setValue("launcherListRadius",      launcherListRadius)
        _settings.setValue("launcherInnerBorderWidth",launcherInnerBorderWidth)
        _settings.setValue("launcherInnerPadding",    launcherInnerPadding)
        // Bar autohide + dock runtime state
        _settings.setValue("barAutoHide",      barAutoHide)
        _settings.setValue("barAutoHideDelay", barAutoHideDelay)
        _settings.setValue("dockAutoHide",     dockAutoHide)
        _settings.setValue("dockAutoHideDelay",dockAutoHideDelay)
        _settings.setValue("dockMargin",       dockMargin)
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 1 · General
    // ═══════════════════════════════════════════════════════════════════════

    // ── Bar mode & position ──────────────────────────────────────────────
    //  "bar"    — blurBackground fill + border on whole bar; islands are
    //             transparent pill outlines only (no gradient fill).
    //  "island" — no whole-bar fill; islands have gradient fill + border.
    //  "tri"    — three separate bar-background rects (left / center / right),
    //             each styled like "bar" mode but physically split. Internal
    //             module layout is unchanged; edit options are shared with bar mode.
    property string barMode:     "bar"   // "bar" | "island" | "tri"
    property string barPosition: "top"   // "top" | "bottom" | "left" | "right"

    // ── Bar geometry ─────────────────────────────────────────────────────
    //  barHeight   = reserved screen strip (PanelWindow exclusion zone)
    //  moduleHeight = visual island/pill height (≤ barHeight)
    //    Gap = (barHeight − moduleHeight) / 2 → "floating pill" look
    property int barHeight:    34   // px — reserved screen strip
    property int moduleHeight: 20   // px — visual island/pill height

    //  Outer margins from screen edges:
    property int outerMarginTop:    2   // px — gap from screen top
    property int outerMarginBottom: 0   // px — gap from screen bottom
    property int outerMarginSide:   6   // px — gap from left & right screen edges

    //  Far-edge padding: extra inset from the barBg L/R edges to the first/last
    //  module group. Adds inner breathing room in "bar" mode.
    property int barEdgePaddingLeft:  2   // px
    property int barEdgePaddingRight: 2   // px

    // ── Radii ────────────────────────────────────────────────────────────
    property int barRadius:    20   // px — whole-bar corner radius (bar mode)
    property int islandRadius: 20   // px — island pill corner radius

    // ── Island border ────────────────────────────────────────────────────
    property int  islandBorder:      0     // px — 0 to remove
    property real islandBorderAlpha: 0.22  // 0–1

    // ── Main bar border (bar mode only) ──────────────────────────────────
    property int  barBorderWidth: 2    // px — 0 to hide
    property real barBorderAlpha: 1.0  // opacity

    // ── Island background opacity ─────────────────────────────────────────
    //  moduleBgOpacity  — flat tint alpha in bar mode (also used by islandBgOpacityBar)
    //  islandBgOpacityIsland — gradient alpha in island mode
    property string islandBgStyle:  "flat"    // "flat" | "gradient" — island pill fill style
    property string barRectBgStyle: "glass"   // "glass" | "gradient" — outer bar/tri rect fill

    property real moduleBgOpacity:       0.5   // 0.0 transparent → 1.0 opaque
    property real islandBgOpacityIsland: 1.0
    property real islandBgAlpha:         0.7   // legacy alias
    readonly property real islandBgOpacityBar: moduleBgOpacity

    // ── Island spacing ────────────────────────────────────────────────────
    property int islandSpacing: 4   // px — gap between all top-level items

    // ── Module spacing & padding ─────────────────────────────────────────
    //  THREE-TIER MODEL
    //  islandSpacing  → between top-level groups / standalone islands
    //  groupedSpacing → between modules inside one island
    //  wsSpacing      → between workspace buttons (0 = truly no gap)
    //  modPadH/V      → per-side padding inside each module container
    property int modPadH:        5   // px — per-side H padding in each module
    property int modPadV:        2   // px — per-side V padding in each module
    property int groupedSpacing: 0   // px — gap between modules within a group

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 2 · Icons
    // ═══════════════════════════════════════════════════════════════════════

    // ── Fonts ────────────────────────────────────────────────────────────
    readonly property string fontFamily: "Symbols Nerd Font Mono"
    readonly property string labelFont:  "JetBrainsMono Nerd Font"
    readonly property int    fontWeight: Font.Normal

    // ── Glyph / icon sizes ───────────────────────────────────────────────
    //  glyphSize      — generic NF glyphs, cava bars, misc icons
    //  infoGlyphSize  — icon glyph before clock, date, weather text
    //  wsGlyphSize    — workspace button icons (set separately in Tab 3)
    //  mediaGlyphSize — media player toggle button icon (󰝚)
    property int glyphSize:      12   // px
    property int infoGlyphSize:  12   // px — clock / date / weather icon
    property int mediaGlyphSize: 12   // px — media player toggle glyph

    //  Text (label) sizes:
    //  infoFontSize      — time, date, weather value, battery %
    //  mediaInfoFontSize — track / artist in media module
    //  labelFontSize     — active-window title, short labels
    property int infoFontSize:      12   // px
    property int mediaInfoFontSize: 10   // px
    property int labelFontSize:     10   // px

    //  Convenience aliases (keep older modules unchanged):
    readonly property int fontSize:      glyphSize
    readonly property int mediaFontSize: mediaInfoFontSize

    // ── Palette colors ───────────────────────────────────────────────────
    //  glyphColor  → all NF glyphs (ws dots, cava, generic icons)
    //  textColor   → info text (time, date, weather value, battery %)
    //  activeColor → active workspace, accent highlights
    //  dimColor    → empty workspaces, secondary info
    readonly property color glyphColor:  Theme.cPrimary
    readonly property color textColor:   Theme.cInverseSurface
    readonly property color activeColor: Theme.cPrimary
    readonly property color dimColor:    Theme.cOnSurfVar

    // ── Per-module color overrides ───────────────────────────────────────
    property color batteryIconColor:     Theme.cPrimary
    property color batteryTextColor:     Theme.cInverseSurface
    property color batteryChargingColor: Theme.cPrimary
    property color batteryLowColor:      Theme.cErr
    property color clockIconColor:       Theme.cPrimary
    property color clockTextColor:       Theme.cInverseSurface
    property color dateIconColor:        Theme.cPrimary
    property color dateTextColor:        Theme.cInverseSurface
    property color mediaGlyphColor:      Theme.cPrimary
    property color powerGlyphColor:      Theme.cPrimary
    property color windowTextColor:      Theme.cInverseSurface
    property real  ccGlyphOpacity:        1.0
    readonly property color ccGlyphColor: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, ccGlyphOpacity)

    // ── Battery radial indicator ─────────────────────────────────────────
    property bool batteryRadialVisible: true
    property int  batteryRadialSize:    14   // px diameter
    property int  batteryRadialWidth:   2    // px stroke

    // ── Control-center / startmenu glyphs ────────────────────────────────
    property string ccGlyph:       ""     // nf-linux-hyprland
    property string powerGlyph:    ""     // nf-fa-chevron_circle_down
    property bool   ccTransparentBg: true

    // ── Icon-text gap ─────────────────────────────────────────────────────
    readonly property int iconTextGap: 2   // px — between glyph icon and label

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 3 · Workspaces
    // ═══════════════════════════════════════════════════════════════════════

    // ── Icon mode ────────────────────────────────────────────────────────
    //  "dot"    — wsDotActive / wsDotPersistent / wsDotEmpty per state
    //  "number" — workspace number as text
    //  "icon"   — wsIcons array; falls back to state dots on empty entry
    property string wsIconMode: "icon"

    property string wsDotActive:     "󰮯"
    property string wsDotPersistent: "󰺕"
    property string wsDotEmpty:      ""

    property var wsIcons: [
        "",   // ws 1
        "",   // ws 2
        "",   // ws 3
        "",   // ws 4
        "",   // ws 5
        "",   // ws 6  — empty → inherits wsDotPersistent automatically
        "",   // ws 7
        "",   // ws 8
        "",   // ws 9
        ""    // ws 10
    ]

    property var wsSpecialIcons: ({
        "magic":  "󰜮",
        "zellij": "󰆍",
        "lock":   "󰌾"
    })

    // ── Workspace colors ─────────────────────────────────────────────────
    //  Colors are readonly so their Theme.cPrimary binding is never broken.
    //  Sliders write to the opacity properties; colors always follow the live theme.
    property real wsActiveOpacity:     1.0
    property real wsPersistentOpacity: 0.7
    property real wsEmptyOpacity:      0.55
    readonly property color wsActiveColor:     Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, wsActiveOpacity)
    readonly property color wsPersistentColor: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, wsPersistentOpacity)
    readonly property color wsEmptyColor:      Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, wsEmptyOpacity)

    // ── Workspace icon size ───────────────────────────────────────────────
    //  wsGlyphSize controls the font size of workspace button icons.
    //  Set independently from the global glyphSize so ws icons can be
    //  larger/smaller than other glyphs without affecting the whole bar.
    property int wsGlyphSize: 12   // px

    // ── Workspace spacing & padding ───────────────────────────────────────
    //  wsSpacing = gap between buttons; 0 = truly no gap (button sized to glyph)
    property int wsSpacing:     4   // px — between workspace buttons
    property int wsMarginLeft:  0   // px — gap from bar-left edge to first ws
    property int wsMarginRight: 0   // px — gap from bar-right edge to last ws
    property int wsPadLeft:     0   // px — left inside each ws button
    property int wsPadRight:    0   // px — right inside each ws button
    property int wsPadTop:      2   // px — top inside each ws button
    property int wsPadBottom:   2   // px — bottom inside each ws button

    // ── Workspace separators ─────────────────────────────────────────────
    property bool   wsSeparators:        false  // show glyph separator between buttons
    property string wsSeparatorGlyph:    ""
    property real   wsSeparatorOpacity:  0.3
    readonly property color wsSeparatorColor: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, wsSeparatorOpacity)
    property int    wsSeparatorSize:     10    // px — font size of the separator glyph
    property int    wsSeparatorPadLeft:  2     // px — space between left ws button and separator
    property int    wsSeparatorPadRight: 2     // px — space between separator and right ws button

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 4 · Media
    // ═══════════════════════════════════════════════════════════════════════

    property int    mediaThumbSize:     18   // px — album art disc diameter
    property int    mediaPlayPauseSize:  6    // px — play/pause icon
    property string mediaToggleGlyph:  "󰽲"  // nf-md-music_note — GJS toggle & no-art fallback
    // mediaInfoFontSize and mediaGlyphSize are defined in Tab 2 Icons

    //  Media island content-area padding (disc + controls + text group):
    property int mediaPadLeft:   0   // px
    property int mediaPadRight:  0   // px
    property int mediaPadTop:    2   // px
    property int mediaPadBottom: 2   // px

    // ═══════════════════════════════════════════════════════════════════════
    //  System Tray
    // ═══════════════════════════════════════════════════════════════════════

    property int trayIconSz:     18   // px — icon image size
    property int trayItemPadH:    1   // px — horizontal padding inside each tray slot
    property int trayItemPadV:    2   // px — vertical padding inside each tray slot
    property int trayItemSpacing: 0   // px — gap between tray icons

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 5 · Cava
    // ═══════════════════════════════════════════════════════════════════════

    property int cavaWidth: 25      // ASCII bar count (number of columns rendered by cava)
    property real cavaBarSpacing: 0  // px — letter-spacing between bars (0 = no gap; fine increments)

    //  cavaStyle selects a named preset. Set to "" to use cavaBars directly.
    //  Presets:  "dots" | "bars" | "braille_fill" | "braille_hollow" |
    //            "blocks" | "thin_bars"
    property string cavaStyle: "dots"

    readonly property var cavaStyleMap: ({
        "dots":           "⣀⣄⣤⣦⣶⣷⣿",
        "bars":           "▁▂▃▄▅▆▇█",
        "braille_fill":   "⠂⠃⠇⡇⣇⣧⣷⣿",
        "braille_hollow": "⠂⠂⠃⠃⡃⡇⡇⣇",
        "blocks":         "░▒▓█",
        "thin_bars":      "⡀⡄⡆⡇⣇⣧⣷⣿"
    })

    //  cavaBars — raw string; used when cavaStyle === ""
    property string cavaBars: "⣀⣄⣤⣦⣶⣷⣿"

    //  cavaEffectiveBars — resolved bars string (use this in Cava.qml)
    readonly property string cavaEffectiveBars: {
        if (cavaStyle !== "" && typeof cavaStyleMap[cavaStyle] !== "undefined")
            return cavaStyleMap[cavaStyle]
        return cavaBars
    }

    property bool cavaTransparentWhenInactive: true
    property real cavaActiveOpacity:   0.85
    property real cavaInactiveOpacity: 0.0
    // cavaAutoHide: when true and showCava is enabled, cava auto-hides when no
    //   media is detected and auto-shows when media starts playing.
    //   When showCava is false, auto-hide is disabled and cava stays hidden.
    property bool cavaAutoHide: false

    // ── Cava color ───────────────────────────────────────────────────────
    //  Single color: cavaGlyphColor
    //  Gradient (cavaGradientEnabled): cavaGradientStartColor → cavaGradientEndColor
    //
    //  Color mode ("matugen" | "custom") and selected variable name are stored
    //  here in Config so the live Theme bindings are active from bar startup —
    //  not waiting for the CC to open.  The computed color properties below
    //  re-evaluate automatically whenever Theme updates (wallpaper change).

    // Mode + selected variable for each color slot ("matugen" | "custom" | "pywal")
    property string cavaStartMode:      "matugen"
    property string cavaEndMode:        "matugen"
    property string cavaStartVar:       "$primary"     // selected matugen variable
    property string cavaEndVar:         "$scrim"       // selected matugen variable
    property string cavaStartPywalVar:  "$color4"      // selected pywal variable
    property string cavaEndPywalVar:    "$color1"      // selected pywal variable

    // Resolve a matugen "$varname" → the live Theme.cXxx color.
    function _cavaThemeColor(varName) {
        switch (varName) {
            case "$source_color":           return Theme.cSourceColor
            case "$primary":                return Theme.cPrimary
            case "$on_primary":             return Theme.cOnPrimary
            case "$primary_container":      return Theme.cPrimaryContainer
            case "$on_primary_container":   return Theme.cOnPrimaryContainer
            case "$primary_fixed":          return Theme.cPrimaryFixed
            case "$primary_fixed_dim":      return Theme.cPrimaryFixedDim
            case "$inverse_primary":        return Theme.cInversePrimary
            case "$secondary":              return Theme.cSecondary
            case "$on_secondary":           return Theme.cOnSecondary
            case "$secondary_container":    return Theme.cSecondaryContainer
            case "$secondary_fixed_dim":    return Theme.cPrimaryFixedDim
            case "$tertiary":               return Theme.cTertiary
            case "$on_tertiary":            return Theme.cOnSurf
            case "$tertiary_container":     return Theme.cTertiaryContainer
            case "$tertiary_fixed_dim":     return Theme.cTertiary
            case "$background":             return Theme.cBackground
            case "$on_background":          return Theme.cOnBackground
            case "$surface":                return Theme.cSurface
            case "$surface_variant":        return Theme.cSurfVariant
            case "$surface_container":      return Theme.cSurfMid
            case "$surface_container_low":  return Theme.cSurfLow
            case "$surface_container_high": return Theme.cSurfHi
            case "$on_surface":             return Theme.cOnSurf
            case "$on_surface_variant":     return Theme.cOnSurfVar
            case "$inverse_surface":        return Theme.cInverseSurface
            case "$outline":                return Theme.cOutline
            case "$outline_variant":        return Theme.cOutVar
            case "$error":                  return Theme.cErr
            case "$scrim":                  return Theme.cScrim
            case "$shadow":                 return Theme.cShadow
            default:                        return Theme.cPrimary
        }
    }

    // Resolve a pywal "$varname" → color from Theme.walColors map.
    function _cavaPywalColor(varName) {
        if (typeof Theme.walColors === "object" && Theme.walColors !== null) {
            const key = varName.replace(/^\$/, "")
            const val = Theme.walColors[key]
            if (val) return val
        }
        return Theme.cPrimary
    }

    // Computed color properties — reactive to mode/var changes AND Theme updates.
    // matugen mode: references Theme.cXxx via _cavaThemeColor() — fully reactive.
    // pywal mode: references Theme.walColors via _cavaPywalColor() — reactive on wallpaper.
    // custom mode: static color stored directly (set by CC picker or hex entry).
    property color cavaGlyphColor: cavaStartMode === "matugen"
        ? _cavaThemeColor(cavaStartVar)
        : cavaStartMode === "pywal"
            ? _cavaPywalColor(cavaStartPywalVar)
            : _cavaGlyphCustomColor
    property color _cavaGlyphCustomColor: Theme.cPrimary   // overwritten by CC custom pick

    property bool  cavaGradientEnabled:    false

    property color cavaGradientStartColor: cavaStartMode === "matugen"
        ? _cavaThemeColor(cavaStartVar)
        : cavaStartMode === "pywal"
            ? _cavaPywalColor(cavaStartPywalVar)
            : _cavaStartCustomColor
    property color _cavaStartCustomColor: Theme.cPrimary   // overwritten by CC custom pick

    property color cavaGradientEndColor: cavaEndMode === "matugen"
        ? _cavaThemeColor(cavaEndVar)
        : cavaEndMode === "pywal"
            ? _cavaPywalColor(cavaEndPywalVar)
            : _cavaEndCustomColor
    property color _cavaEndCustomColor: Theme.cScrim       // overwritten by CC custom pick

    // Fraction of glyph height at which start→end color splits (0.0–1.0, default 0.5)
    property real  cavaGradientSplit:       0.5

    // ── Persist cava color settings to [cc-cava-colors-v1] in hyprcandy-bar.conf ──
    // Mirrors the same pattern used by the border scripts. Runs after load completes
    // (guarded by _cavaConfWriteReady) so initial property-setting doesn't trigger writes.
    property bool _cavaConfWriteReady: false
    property Timer _cavaConfWriteReadyTimer: Timer {
        interval: 500; repeat: false; running: true
        onTriggered: cfg._cavaConfWriteReady = true
    }

    // Shared bash helper — ensures [cc-cava-colors-v1] section and all 6 keys exist,
    // then overwrites them atomically.
    function _writeCavaColorConf() {
        if (!_cavaConfWriteReady) return
        const sMode = cavaStartMode
        const eMode = cavaEndMode
        const sVar  = sMode === "pywal" ? cavaStartPywalVar : cavaStartVar
        const eVar  = eMode === "pywal" ? cavaEndPywalVar   : cavaEndVar
        const gMode = sMode
        const gVar  = sVar

        // Atomic awk+printf rewrite so $-prefixed var names are never expanded by bash
        const f   = "$HOME/.config/hyprcandy/hyprcandy-bar.conf"
        const sec = "cc-cava-colors-v1"
        const cmd = [
            "bash", "-c",
            `f="${f}"; sec="${sec}"; ` +
            `mkdir -p "$(dirname "$f")"; [ -f "$f" ] || touch "$f"; ` +
            `awk -v s="[$sec]" '/^\\[/{in_s=($0==s)} !in_s{print}' "$f" > "$f.tmp" && mv "$f.tmp" "$f"; ` +
            `printf '[%s]\\nstartMode=%s\\nstartVar=%s\\nendMode=%s\\nendVar=%s\\nglyphMode=%s\\nglyphVar=%s\\n' ` +
            `'${sec}' '${sMode}' '${sVar}' '${eMode}' '${eVar}' '${gMode}' '${gVar}' >> "$f"`
        ]
        _cavaConfWriter.command = cmd
        _cavaConfWriter.running = true
    }

    property var _cavaConfWriter: Process {
        running: false
        onExited: running = false
    }

    // Watchers — fire _writeCavaColorConf whenever any relevant property changes
    onCavaStartModeChanged:     Qt.callLater(_writeCavaColorConf)
    onCavaEndModeChanged:       Qt.callLater(_writeCavaColorConf)
    onCavaStartVarChanged:      Qt.callLater(_writeCavaColorConf)
    onCavaEndVarChanged:        Qt.callLater(_writeCavaColorConf)
    onCavaStartPywalVarChanged: Qt.callLater(_writeCavaColorConf)
    onCavaEndPywalVarChanged:   Qt.callLater(_writeCavaColorConf)

    // ═══════════════════════════════════════════════════════════════════════
    //  Application Launcher (GJS dock app launcher)
    // ═══════════════════════════════════════════════════════════════════════
    //  Values are written to ~/.config/hyprcandy/launcher-config.state
    //  and read by the GJS launcher on startup.

    property real  launcherSearchWidth:       1.0
    property int   launcherIconSize:          48
    property int   launcherTextFontSize:      11
    property int   launcherFixedTileWidth:    90
    property int   launcherFixedTileHeight:   78
    property int   launcherFrameWidth:        500
    property int   launcherFrameHeight:       480
    property int   launcherFrameWidthVert:    380
    property int   launcherFrameHeightVert:   560
    property int   launcherBorderRadius:      20
    property int   launcherBorderWidth:       2
    property int   launcherSearchRadius:      12
    property int   launcherListRadius:        12
    property int   launcherInnerBorderWidth:  1
    property int   launcherInnerPadding:      10

    function _saveLauncherConfig() {
        const state = {
            searchWidthFraction: launcherSearchWidth,
            iconSize:            launcherIconSize,
            textFontSize:        launcherTextFontSize,
            fixedTileWidth:      launcherFixedTileWidth,
            fixedTileHeight:     launcherFixedTileHeight,
            frameWidth:          launcherFrameWidth,
            frameHeight:         launcherFrameHeight,
            frameWidthVert:      launcherFrameWidthVert,
            frameHeightVert:     launcherFrameHeightVert,
            borderRadius:        launcherBorderRadius,
            borderWidth:         launcherBorderWidth,
            searchRadius:        launcherSearchRadius,
            listRadius:          launcherListRadius,
            innerBorderWidth:    launcherInnerBorderWidth,
            innerPadding:        launcherInnerPadding,
        };
        try {
            const path = Qt.resolvedUrl("file://" + HOME + "/.config/hyprcandy/launcher-config.state")
                .toString().replace("file://", "");
            // Use a Process to write — Qt Quick Settings won't write arbitrary JSON
            _launcherConfigProc.command = ["bash", "-c",
                'mkdir -p "$HOME/.config/hyprcandy" && ' +
                'echo \'' + JSON.stringify(state) + '\' > "$HOME/.config/hyprcandy/launcher-config.state"']
            _launcherConfigProc.running = true
        } catch(e) { console.error("Failed to save launcher config:", e) }
    }

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 6 · Background
    // ═══════════════════════════════════════════════════════════════════════
    //
    //  Per-type island background color and opacity.
    //  opacity = -1 → fall back to global moduleBgOpacity.
    //  opacity = 0  → fully transparent (glass only in bar mode).
    //  opacity = 1  → full color.

    property color wsBgColor:   Theme.cOnSecondary
    property real  wsBgOpacity: 0

    property color groupedBgColor:   Theme.cOnSecondary
    property real  groupedBgOpacity: 0

    property color ungroupedBgColor:   Theme.cOnSecondary
    property real  ungroupedBgOpacity: 0

    property color trayBgColor:   Theme.cOnSecondary
    property real  trayBgOpacity: 0

    property color startMenuBgColor:   Theme.cOnSecondary
    property real  startMenuBgOpacity: 0

    property color mediaBgColor:   Theme.cOnSecondary
    property real  mediaBgOpacity: 0

    property color cavaBgColor:   Theme.cOnSecondary
    property real  cavaBgOpacity: 0

    property color distroBgColor:   Theme.cOnSecondary
    property real  distroBgOpacity: 0

    property color activeWindowBgColor:   Theme.cOnSecondary
    property real  activeWindowBgOpacity: 0
    property int   activeWindowMinWidth:  23   // px — kept even when title is empty

    // ═══════════════════════════════════════════════════════════════════════
    //  Module visibility
    // ═══════════════════════════════════════════════════════════════════════

    property bool showCava:          true
    property bool showWeather:       true
    property bool showBattery:       true
    property bool showMediaPlayer:   true
    property bool showIdleInhibitor: true
    property bool showRofi:          true
    property bool showUpdates:       true
    property bool showPowerProfiles: true
    property bool showOverview:      true
    property bool showNotifications: true
    property bool showWallpaper:     true
    property bool showTray:          true
    property bool showBluetooth:     true
    property bool showWindow:        false
    property bool showDistro:        true

    // ═══════════════════════════════════════════════════════════════════════
    //  Behaviour / intervals
    // ═══════════════════════════════════════════════════════════════════════


    // ═══════════════════════════════════════════════════════════════════════
    //  Bar auto-hide  (source of truth for QS bar; also written to
    //  hyprcandy-bar.conf so the GJS dock process can read the same file)
    // ═══════════════════════════════════════════════════════════════════════
    property bool barAutoHide:      false
    property int  barAutoHideDelay: 5       // seconds

    // ═══════════════════════════════════════════════════════════════════════
    //  Dock runtime state (source of truth for CC display; GJS dock reads
    //  hyprcandy-bar.conf directly, but CC persists state here so the
    //  toggles show the correct value when the CC reopens)
    // ═══════════════════════════════════════════════════════════════════════
    property bool   dockAutoHide:      false
    property int    dockAutoHideDelay: 5       // seconds
    property int    dockMargin:        6       // px — screen-edge gap

    readonly property bool wsScrollSwitch:  true
    readonly property int  weatherInterval: 300    // seconds
    readonly property int  wsCount:         5      // persistent workspace slots
    readonly property int  hoverDuration:   300    // ms — hover animation

    // ═══════════════════════════════════════════════════════════════════════
    //  Runtime paths
    // ═══════════════════════════════════════════════════════════════════════

    readonly property string home:        StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string barDir:      home + "/.config/quickshell/bar"
    readonly property string scriptsDir:  home + "/.config/hyprcandy/scripts"
    readonly property string hyprScripts: home + "/.config/hypr/scripts"
    readonly property string candyDir:    home + "/.hyprcandy"
    readonly property string cavaScript:  barDir + "/cava.py"
    // Aliases used by older module references:
    readonly property string candyBarDir:      barDir
    readonly property string candyHyprScripts: hyprScripts

    // ═══════════════════════════════════════════════════════════════════════
    //  Legacy aliases — keep all existing modules compiling unchanged
    // ═══════════════════════════════════════════════════════════════════════

    readonly property int outerMarginEdge:  outerMarginTop
    readonly property int modulePadLeft:    modPadH
    readonly property int modulePadRight:   modPadH
    readonly property int modulePadTop:     modPadV
    readonly property int modulePadBottom:  modPadV
    readonly property int moduleSpacing:    groupedSpacing
    readonly property int btnPadLeft:       modPadH
    readonly property int btnPadRight:      modPadH
    readonly property int btnPadTop:        modPadV
    readonly property int btnPadBottom:     modPadV
    readonly property int moduleHPad:       modPadH
    readonly property int moduleVPad:       modPadV
    readonly property int modulePadH:       modPadH * 2
    readonly property int modulePadV:       modPadV * 2
    readonly property int islandMarginH:    0
    readonly property int islandMarginV:    0
    readonly property int trayIconSize:     15
    readonly property int traySpacing:      4
    readonly property int mediaThumbSz:     mediaThumbSize
    readonly property int wsGlyphSz:        wsGlyphSize
}
