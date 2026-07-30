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
        _lastBarPosition = barPosition
        _cornerSwapReady = true
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
        var oldRadius = 20
        v = _settings.value("barRadius"); if (v !== undefined && v !== null) oldRadius = parseInt(v)
        v = _settings.value("barTopLeftRadius");    barTopLeftRadius = (v !== undefined && v !== null) ? parseInt(v) : oldRadius
        v = _settings.value("barTopRightRadius");   barTopRightRadius = (v !== undefined && v !== null) ? parseInt(v) : oldRadius
        v = _settings.value("barBottomLeftRadius"); barBottomLeftRadius = (v !== undefined && v !== null) ? parseInt(v) : oldRadius
        v = _settings.value("barBottomRightRadius");barBottomRightRadius = (v !== undefined && v !== null) ? parseInt(v) : oldRadius
        v = _settings.value("triLeftTopRightRadius");    triLeftTopRightRadius    = (v !== undefined && v !== null) ? parseInt(v) : barTopRightRadius
        v = _settings.value("triLeftBottomRightRadius"); triLeftBottomRightRadius = (v !== undefined && v !== null) ? parseInt(v) : barBottomRightRadius
        // Legacy: outer left tri corners now share barTopLeft / barBottomLeft
        v = _settings.value("triLeftTopLeftRadius")
        if (v !== undefined && v !== null) barTopLeftRadius = parseInt(v)
        v = _settings.value("triLeftBottomLeftRadius")
        if (v !== undefined && v !== null) barBottomLeftRadius = parseInt(v)
        v = _settings.value("triCenterTopLeftRadius");     triCenterTopLeftRadius     = (v !== undefined && v !== null) ? parseInt(v) : barTopLeftRadius
        v = _settings.value("triCenterTopRightRadius");    triCenterTopRightRadius    = (v !== undefined && v !== null) ? parseInt(v) : barTopRightRadius
        v = _settings.value("triCenterBottomLeftRadius");   triCenterBottomLeftRadius  = (v !== undefined && v !== null) ? parseInt(v) : barBottomLeftRadius
        v = _settings.value("triCenterBottomRightRadius");  triCenterBottomRightRadius = (v !== undefined && v !== null) ? parseInt(v) : barBottomRightRadius
        v = _settings.value("triRightTopLeftRadius");     triRightTopLeftRadius     = (v !== undefined && v !== null) ? parseInt(v) : 20
        v = _settings.value("triRightBottomLeftRadius"); triRightBottomLeftRadius = (v !== undefined && v !== null) ? parseInt(v) : 20
        // Legacy: outer right tri corners now share barTopRight / barBottomRight
        v = _settings.value("triRightTopRightRadius")
        if (v !== undefined && v !== null) barTopRightRadius = parseInt(v)
        v = _settings.value("triRightBottomRightRadius")
        if (v !== undefined && v !== null) barBottomRightRadius = parseInt(v)
        v = _settings.value("shellArmThickness");          if (v !== undefined && v !== null) shellArmThickness          = parseInt(v)
        v = _settings.value("shellInnerRadius");           if (v !== undefined && v !== null) shellInnerRadius           = parseInt(v)
        v = _settings.value("shellModuleSideMargin");      if (v !== undefined && v !== null) shellModuleSideMargin      = parseInt(v)
        v = _settings.value("shellModuleAutoHide");        if (v !== undefined && v !== null) shellModuleAutoHide        = _toBool(v)
        v = _settings.value("shellModuleAutoHideDelay");   if (v !== undefined && v !== null) shellModuleAutoHideDelay   = parseInt(v)
        v = _settings.value("shellCenterJunctionRadius");  if (v !== undefined && v !== null) shellCenterJunctionRadius  = parseInt(v)
        v = _settings.value("islandRadius"); if (v !== undefined && v !== null) islandRadius = v
        v = _settings.value("islandBorder"); if (v !== undefined && v !== null) islandBorder = v
        v = _settings.value("islandBorderAlpha"); if (v !== undefined && v !== null) islandBorderAlpha = v
        v = _settings.value("islandBorderVar"); if (v !== undefined && v !== null) islandBorderVar = v
        v = _settings.value("islandBorderMode"); if (v !== undefined && v !== null) islandBorderMode = v
        v = _settings.value("islandBorderWallustVar"); if (v !== undefined && v !== null) islandBorderWallustVar = v
        v = _settings.value("barBorderWidth"); if (v !== undefined && v !== null) barBorderWidth = v
        v = _settings.value("barBorderAlpha"); if (v !== undefined && v !== null) barBorderAlpha = v
        v = _settings.value("barBorderVar"); if (v !== undefined && v !== null) barBorderVar = v
        v = _settings.value("barBorderMode"); if (v !== undefined && v !== null) barBorderMode = v
        v = _settings.value("barBorderWallustVar"); if (v !== undefined && v !== null) barBorderWallustVar = v
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
        v = _settings.value("mediaCtlSize"); if (v !== undefined && v !== null) mediaCtlSize = v
        v = _settings.value("mediaThumbSize"); if (v !== undefined && v !== null) mediaThumbSize = v
        v = _settings.value("batteryRadialVisible"); if (v !== undefined && v !== null) batteryRadialVisible = _toBool(v)
        v = _settings.value("batteryRadialSize"); if (v !== undefined && v !== null) batteryRadialSize = v
        v = _settings.value("batteryRadialWidth"); if (v !== undefined && v !== null) batteryRadialWidth = v
        v = _settings.value("trayIconSz"); if (v !== undefined && v !== null) trayIconSz = v
        v = _settings.value("trayItemPadH");   if (v !== undefined && v !== null) trayItemPadH   = v
        v = _settings.value("trayItemSpacing"); if (v !== undefined && v !== null) trayItemSpacing = v
        v = _settings.value("ccGlyph"); if (v !== undefined && v !== null) ccGlyph = v
        v = _settings.value("ccGlyphColorA"); if (v !== undefined && v !== null) ccGlyphOpacity = Math.min(1, Math.max(0, parseFloat(v)))
        v = _settings.value("wsCount"); if (v !== undefined && v !== null) wsCount = Math.min(10, Math.max(1, parseInt(v)))
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
        v = _settings.value("cavaStartWallustVar"); if (v !== undefined && v !== null) cavaStartWallustVar = v
        v = _settings.value("cavaEndWallustVar");   if (v !== undefined && v !== null) cavaEndWallustVar   = v
        v = _settings.value("cavaStartCustomColor"); if (v !== undefined && v !== null) _cavaStartCustomColor = v
        v = _settings.value("cavaEndCustomColor");   if (v !== undefined && v !== null) _cavaEndCustomColor   = v
        v = _settings.value("cavaGlyphCustomColor"); if (v !== undefined && v !== null) _cavaGlyphCustomColor = v
        v = _settings.value("wsBgOpacity"); if (v !== undefined && v !== null) wsBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("groupedBgOpacity"); if (v !== undefined && v !== null) groupedBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("ungroupedBgOpacity"); if (v !== undefined && v !== null) ungroupedBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("clockDateBgOpacity");  if (v !== undefined && v !== null) clockDateBgOpacity  = Math.max(0, parseFloat(v))
        v = _settings.value("weatherBatBgOpacity"); if (v !== undefined && v !== null) weatherBatBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("leftGroupBgOpacity");  if (v !== undefined && v !== null) leftGroupBgOpacity  = Math.max(0, parseFloat(v))
        v = _settings.value("rightGroupBgOpacity"); if (v !== undefined && v !== null) rightGroupBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("trayBgOpacity"); if (v !== undefined && v !== null) trayBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("startMenuBgOpacity"); if (v !== undefined && v !== null) startMenuBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("mediaBgOpacity"); if (v !== undefined && v !== null) mediaBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("cavaBgOpacity"); if (v !== undefined && v !== null) cavaBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("distroBgOpacity"); if (v !== undefined && v !== null) distroBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("activeWindowBgOpacity"); if (v !== undefined && v !== null) activeWindowBgOpacity = v
        v = _settings.value("activeWindowMinWidth"); if (v !== undefined && v !== null) activeWindowMinWidth = v
        v = _settings.value("showClock"); if (v !== undefined && v !== null) showClock = _toBool(v)
        v = _settings.value("showDate"); if (v !== undefined && v !== null) showDate = _toBool(v)
        v = _settings.value("showWorkspaces"); if (v !== undefined && v !== null) showWorkspaces = _toBool(v)
        v = _settings.value("showCava"); if (v !== undefined && v !== null) showCava = _toBool(v)
        v = _settings.value("showWeather"); if (v !== undefined && v !== null) showWeather = _toBool(v)
        v = _settings.value("showBattery"); if (v !== undefined && v !== null) showBattery = _toBool(v)
        v = _settings.value("showMediaPlayer"); if (v !== undefined && v !== null) showMediaPlayer = _toBool(v)
        v = _settings.value("showIdleInhibitor"); if (v !== undefined && v !== null) showIdleInhibitor = _toBool(v)
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
        v = _settings.value("barAutoHideDelay"); if (v !== undefined && v !== null) barAutoHideDelay = parseInt(v)
        v = _settings.value("triLeftAutoHide");       if (v !== undefined && v !== null) triLeftAutoHide       = _toBool(v)
        v = _settings.value("triLeftAutoHideDelay");  if (v !== undefined && v !== null) triLeftAutoHideDelay  = parseInt(v)
        v = _settings.value("triCenterAutoHide");     if (v !== undefined && v !== null) triCenterAutoHide     = _toBool(v)
        v = _settings.value("triCenterAutoHideDelay");if (v !== undefined && v !== null) triCenterAutoHideDelay = parseInt(v)
        v = _settings.value("triRightAutoHide");      if (v !== undefined && v !== null) triRightAutoHide      = _toBool(v)
        v = _settings.value("triRightAutoHideDelay"); if (v !== undefined && v !== null) triRightAutoHideDelay = parseInt(v)
        v = _settings.value("dockAutoHide");     if (v !== undefined && v !== null) dockAutoHide     = _toBool(v)
        v = _settings.value("dockAutoHideDelay");if (v !== undefined && v !== null) dockAutoHideDelay= parseInt(v)
        v = _settings.value("dockMargin");       if (v !== undefined && v !== null) dockMargin       = parseInt(v)
        v = _settings.value("desktopIconSize");    if (v !== undefined && v !== null) desktopIconSize    = parseInt(v)
        v = _settings.value("desktopLabelSize");   if (v !== undefined && v !== null) desktopLabelSize   = parseInt(v)
        v = _settings.value("desktopLabelRadius"); if (v !== undefined && v !== null) desktopLabelRadius = parseInt(v)
        v = _settings.value("desktopVisible");     if (v !== undefined && v !== null) desktopVisible     = _toBool(v)
        v = _settings.value("clockTextSize");      if (v !== undefined && v !== null) clockTextSize      = parseInt(v)
        v = _settings.value("clockIconSize");      if (v !== undefined && v !== null) clockIconSize      = parseInt(v)
        v = _settings.value("clockWorldCities");   if (v !== undefined && v !== null) { try { clockWorldCities = JSON.parse(v) } catch(e) {} }
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
        _settings.setValue("barTopLeftRadius",     barTopLeftRadius)
        _settings.setValue("barTopRightRadius",    barTopRightRadius)
        _settings.setValue("barBottomLeftRadius",  barBottomLeftRadius)
        _settings.setValue("barBottomRightRadius", barBottomRightRadius)
        _settings.setValue("triLeftTopRightRadius",    triLeftTopRightRadius)
        _settings.setValue("triLeftBottomRightRadius", triLeftBottomRightRadius)
        _settings.setValue("triLeftTopLeftRadius",    barTopLeftRadius)
        _settings.setValue("triLeftBottomLeftRadius", barBottomLeftRadius)
        _settings.setValue("triCenterTopLeftRadius",     triCenterTopLeftRadius)
        _settings.setValue("triCenterTopRightRadius",    triCenterTopRightRadius)
        _settings.setValue("triCenterBottomLeftRadius",  triCenterBottomLeftRadius)
        _settings.setValue("triCenterBottomRightRadius", triCenterBottomRightRadius)
        _settings.setValue("triRightTopLeftRadius",     triRightTopLeftRadius)
        _settings.setValue("triRightBottomLeftRadius",  triRightBottomLeftRadius)
        _settings.setValue("triRightTopRightRadius",    barTopRightRadius)
        _settings.setValue("triRightBottomRightRadius", barBottomRightRadius)
        _settings.setValue("shellArmThickness",         shellArmThickness)
        _settings.setValue("shellInnerRadius",          shellInnerRadius)
        _settings.setValue("shellCenterJunctionRadius", shellCenterJunctionRadius)
        _settings.setValue("shellModuleSideMargin",     shellModuleSideMargin)
        _settings.setValue("shellModuleAutoHide",       shellModuleAutoHide)
        _settings.setValue("shellModuleAutoHideDelay",  shellModuleAutoHideDelay)
        _settings.setValue("islandRadius", islandRadius)
        _settings.setValue("islandBorder", islandBorder)
        _settings.setValue("islandBorderAlpha", islandBorderAlpha)
        _settings.setValue("islandBorderVar", islandBorderVar)
        _settings.setValue("islandBorderMode", islandBorderMode)
        _settings.setValue("islandBorderWallustVar", islandBorderWallustVar)
        _settings.setValue("barBorderWidth", barBorderWidth)
        _settings.setValue("barBorderAlpha", barBorderAlpha)
        _settings.setValue("barBorderVar", barBorderVar)
        _settings.setValue("barBorderMode", barBorderMode)
        _settings.setValue("barBorderWallustVar", barBorderWallustVar)
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
        _settings.setValue("mediaCtlSize", mediaCtlSize)
        _settings.setValue("mediaThumbSize", mediaThumbSize)
        _settings.setValue("batteryRadialVisible", batteryRadialVisible)
        _settings.setValue("batteryRadialSize", batteryRadialSize)
        _settings.setValue("batteryRadialWidth", batteryRadialWidth)
        _settings.setValue("trayIconSz", trayIconSz)
        _settings.setValue("trayItemPadH",    trayItemPadH)
        _settings.setValue("trayItemSpacing", trayItemSpacing)
        _settings.setValue("ccGlyph", ccGlyph)
        _settings.setValue("ccGlyphColorA", ccGlyphOpacity)
        _settings.setValue("wsCount", wsCount)
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
        _settings.setValue("cavaStartWallustVar",  cavaStartWallustVar)
        _settings.setValue("cavaEndWallustVar",    cavaEndWallustVar)
        _settings.setValue("cavaStartCustomColor", _cavaStartCustomColor)
        _settings.setValue("cavaEndCustomColor",   _cavaEndCustomColor)
        _settings.setValue("cavaGlyphCustomColor", _cavaGlyphCustomColor)
        _settings.setValue("wsBgOpacity", wsBgOpacity)
        _settings.setValue("groupedBgOpacity", groupedBgOpacity)
        _settings.setValue("ungroupedBgOpacity", ungroupedBgOpacity)
        _settings.setValue("clockDateBgOpacity",  clockDateBgOpacity)
        _settings.setValue("weatherBatBgOpacity", weatherBatBgOpacity)
        _settings.setValue("leftGroupBgOpacity",  leftGroupBgOpacity)
        _settings.setValue("rightGroupBgOpacity", rightGroupBgOpacity)
        _settings.setValue("trayBgOpacity", trayBgOpacity)
        _settings.setValue("startMenuBgOpacity", startMenuBgOpacity)
        _settings.setValue("mediaBgOpacity", mediaBgOpacity)
        _settings.setValue("cavaBgOpacity", cavaBgOpacity)
        _settings.setValue("distroBgOpacity", distroBgOpacity)
        _settings.setValue("activeWindowBgOpacity", activeWindowBgOpacity)
        _settings.setValue("activeWindowMinWidth", activeWindowMinWidth)
        _settings.setValue("showClock", showClock)
        _settings.setValue("showDate", showDate)
        _settings.setValue("showWorkspaces", showWorkspaces)
        _settings.setValue("showCava", showCava)
        _settings.setValue("showWeather", showWeather)
        _settings.setValue("showBattery", showBattery)
        _settings.setValue("showMediaPlayer", showMediaPlayer)
        _settings.setValue("showIdleInhibitor", showIdleInhibitor)

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
        _settings.setValue("triLeftAutoHide",        triLeftAutoHide)
        _settings.setValue("triLeftAutoHideDelay",   triLeftAutoHideDelay)
        _settings.setValue("triCenterAutoHide",      triCenterAutoHide)
        _settings.setValue("triCenterAutoHideDelay", triCenterAutoHideDelay)
        _settings.setValue("triRightAutoHide",       triRightAutoHide)
        _settings.setValue("triRightAutoHideDelay",  triRightAutoHideDelay)
        _settings.setValue("dockAutoHide",     dockAutoHide)
        _settings.setValue("dockAutoHideDelay",dockAutoHideDelay)
        _settings.setValue("dockMargin",       dockMargin)
        _settings.setValue("desktopIconSize",    desktopIconSize)
        _settings.setValue("desktopLabelSize",   desktopLabelSize)
        _settings.setValue("desktopLabelRadius", desktopLabelRadius)
        _settings.setValue("desktopVisible",     desktopVisible)
        _settings.setValue("clockTextSize",      clockTextSize)
        _settings.setValue("clockIconSize",      clockIconSize)
        _settings.setValue("clockWorldCities",   JSON.stringify(clockWorldCities))
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
    //  "shell" — 4-sided frame around screen edges, painted by the shellFrame
    //            Canvas inside Bar.qml itself (not a separate window).
    //            Left/right islands float inside the hollow. Center island is
    //            pinned to and protrudes inward from the active arm.
    property string barMode: "bar"   // "bar" | "island" | "tri" | "shell"
    property string barPosition: "top"   // "top" | "bottom" | "left" | "right"

    // ── Bar geometry ─────────────────────────────────────────────────────
    //  barHeight   = reserved screen strip (PanelWindow exclusion zone)
    //  moduleHeight = visual island/pill height (≤ barHeight)
    //    Gap = (barHeight − moduleHeight) / 2 → "floating pill" look
    property int barHeight:    34   // px — reserved screen strip
    property int moduleHeight: 20   // px — visual island/pill height

    //  Outer margins from screen edges:
    // Widget-local — Top/Bottom sliders always match visual edge; values swap on top↔bottom flip.
    property int outerMarginTop:    2   // px — gap from screen top (when bar at top)
    property int outerMarginBottom: 0   // px — gap from screen bottom (when bar at bottom)
    property int outerMarginSide:   6   // px — gap from left & right screen edges

    //  Far-edge padding: extra inset from the barBg L/R edges to the first/last
    //  module group. Adds inner breathing room in "bar" mode.
    property int barEdgePaddingLeft:  2   // px
    property int barEdgePaddingRight: 2   // px

    // ── Radii ────────────────────────────────────────────────────────────
    // Widget-local corners — sliders always match visual TL/TR/BL/BR.
    // On top↔bottom flip, values swap vertically so screen-edge rounding carries over.
    property int barTopLeftRadius:     20
    property int barTopRightRadius:    20
    property int barBottomLeftRadius:  20
    property int barBottomRightRadius: 20
    readonly property int barRadius: barTopLeftRadius
    // tri mode — outer corners share bar TL/BL (left) and TR/BR (right); inner corners independent
    property int triLeftTopRightRadius:    20
    property int triLeftBottomRightRadius: 20
    property int triCenterTopLeftRadius:     20
    property int triCenterTopRightRadius:    20
    property int triCenterBottomLeftRadius:  20
    property int triCenterBottomRightRadius: 20
    property int triRightTopLeftRadius:     20
    property int triRightBottomLeftRadius:  20

    // ── Shell mode properties ─────────────────────────────────────────────
    property int shellArmThickness:         40   // px — frame arm width on all 4 sides
    property int shellInnerRadius:          20   // px — inner corner radius (all 4)
    property int shellCenterJunctionRadius: 20   // px — island junction corner radius
    property int  shellModuleSideMargin:    6    // px — side margin for the module strip in shell mode
    property bool shellModuleAutoHide:      false
    property int  shellModuleAutoHideDelay: 5    // seconds

    property string _lastBarPosition: ""
    property bool   _cornerSwapReady: false

    function _swapBarCornersVertical() {
        const tl = barTopLeftRadius,     tr = barTopRightRadius
        const bl = barBottomLeftRadius,  br = barBottomRightRadius
        barTopLeftRadius = bl;     barTopRightRadius = br
        barBottomLeftRadius = tl;  barBottomRightRadius = tr

        const ctl = triCenterTopLeftRadius,     ctr = triCenterTopRightRadius
        const cbl = triCenterBottomLeftRadius,  cbr = triCenterBottomRightRadius
        triCenterTopLeftRadius = cbl;     triCenterTopRightRadius = cbr
        triCenterBottomLeftRadius = ctl;  triCenterBottomRightRadius = ctr

        const ltr = triLeftTopRightRadius,    lbr = triLeftBottomRightRadius
        triLeftTopRightRadius = lbr;    triLeftBottomRightRadius = ltr

        const rtl = triRightTopLeftRadius,    rbl = triRightBottomLeftRadius
        triRightTopLeftRadius = rbl;    triRightBottomLeftRadius = rtl
    }

    onBarPositionChanged: {
        if (!_cornerSwapReady) return
        const prev = _lastBarPosition
        if ((prev === "top" && barPosition === "bottom")
                || (prev === "bottom" && barPosition === "top")) {
            _swapBarCornersVertical()
            const mt = outerMarginTop, mb = outerMarginBottom
            outerMarginTop = mb
            outerMarginBottom = mt
        }
        _lastBarPosition = barPosition
    }

    property int islandRadius: 20   // px — island pill corner radius

    // ── Island border ────────────────────────────────────────────────────
    property int  islandBorder:      0     // px — 0 to remove
    property real islandBorderAlpha: 0.22  // 0–1
    property string islandBorderVar:        "$outline_variant"  // matugen variable
    property string islandBorderMode:       "matugen"           // "matugen" | "wallust"
    property string islandBorderWallustVar: "$color0"           // wallust color0–color15
    readonly property color islandBorderColor: islandBorderMode === "wallust"
        ? _wallustThemeColor(islandBorderWallustVar)
        : _cavaThemeColor(islandBorderVar)

    // ── Main bar border (bar mode only) ──────────────────────────────────
    property int  barBorderWidth: 2    // px — 0 to hide
    property real barBorderAlpha: 1.0  // opacity
    property string barBorderVar:        "$on_secondary"  // matugen variable
    property string barBorderMode:       "matugen"        // "matugen" | "wallust"
    property string barBorderWallustVar: "$color7"        // wallust color0–color15
    readonly property color barBorderColor: barBorderMode === "wallust"
        ? _wallustThemeColor(barBorderWallustVar)
        : _cavaThemeColor(barBorderVar)

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
    readonly property string styleFont:  "C059"
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
    //  infoFontSize  — time, date, weather value, battery %
    //  labelFontSize — active-window title, short labels
    property int infoFontSize:      12   // px
    property int mediaInfoFontSize: 10   // px — kept for compat (unused in bar media module)
    property int labelFontSize:     10   // px

    //  Convenience aliases (keep older modules unchanged):
    readonly property int fontSize:      glyphSize
    readonly property int mediaFontSize: mediaInfoFontSize

    // ── Palette colors ───────────────────────────────────────────────────
    //  glyphColor  → all NF glyphs (ws dots, cava, generic icons)
    //  textColor   → info text (time, date, weather value, battery %)
    //  activeColor → active workspace, accent highlights
    //  dimColor    → empty workspaces, secondary info
    readonly property color glyphColor:  Qt.rgba(Theme.cWc10.r, Theme.cWc10.g, Theme.cWc10.b, 1.00)
    readonly property color textColor:   Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 1.00)
    readonly property color activeColor: Config.glyphColor
    readonly property color dimColor:    Theme.cOnSurfVar

    // ── Per-module color overrides ───────────────────────────────────────
    property color batteryIconColor:     Config.glyphColor
    property color batteryTextColor:     Config.textColor
    property color batteryChargingColor: Config.glyphColor
    property color batteryLowColor:      Theme.cErr
    property color clockIconColor:       Config.glyphColor
    property color clockTextColor:       Config.textColor
    property color rightGroupColor:      Config.glyphColor

    // ── Clock popup sizing ────────────────────────────────────────────────
    property int clockTextSize: 38   // C059 Bold Italic time font size in ClockPopup
    property int clockIconSize: 32   // Nerd-font clock icon size in ClockPopup

    // ── World clock cities ────────────────────────────────────────────────
    // Each entry: { city: "Display Name", timezone: "IANA/Timezone" }
    // Managed via CC → Bar → Clock sub-tab. Unbounded — add as many as needed.
    property var clockWorldCities: [
        { "city": "London",    "timezone": "Europe/London"    },
        { "city": "New York",  "timezone": "America/New_York" },
        { "city": "Tokyo",     "timezone": "Asia/Tokyo"       },
        { "city": "Dubai",     "timezone": "Asia/Dubai"       }
    ]

    property color dateIconColor:        Config.glyphColor
    property color dateTextColor:        Config.textColor
    property color mediaGlyphColor:      Config.glyphColor
    property color discGlyphColor:       Theme.cSurfaceTint
    property color mediabtGlyphColor:    Qt.rgba(Theme.cInversePrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.80)
    property color powerGlyphColor:      Qt.rgba(Theme.cWc5.r, Theme.cWc5.g, Theme.cWc5.b, 1.00)
    property color windowTextColor:      Theme.cInverseSurface
    property real  ccGlyphOpacity:        1.0
    readonly property color ccGlyphColor: Qt.rgba(Theme.cWc3.r, Theme.cWc3.g, Theme.cWc3.b, ccGlyphOpacity)

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
    readonly property color wsActiveColor:     Qt.rgba(Theme.cWc5.r, Theme.cWc5.g, Theme.cWc5.b, wsActiveOpacity)
    readonly property color wsPersistentColor: Qt.rgba(Theme.cWc3.r, Theme.cWc3.g, Theme.cWc3.b, wsPersistentOpacity)
    readonly property color wsEmptyColor:      Qt.rgba(Theme.cWc4.r, Theme.cWc4.g, Theme.cWc4.b, wsEmptyOpacity)

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
    readonly property color wsSeparatorColor: Qt.rgba(Theme.cWc9.r, Theme.cWc9.g, Theme.cWc9.b, wsSeparatorOpacity)
    property int    wsSeparatorSize:     10    // px — font size of the separator glyph
    property int    wsSeparatorPadLeft:  2     // px — space between left ws button and separator
    property int    wsSeparatorPadRight: 2     // px — space between separator and right ws button

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 4 · Media
    // ═══════════════════════════════════════════════════════════════════════

    property int    mediaThumbSize:     18   // px — album art thumb (auto-hides when no art)
    property int    mediaCtlSize:        11   // px — prev / play-pause / next glyph size
    property string mediaToggleGlyph:  "󰽲"  // nf-md-music_note — GJS toggle button glyph
    // mediaGlyphSize is defined in Tab 2 Icons

    //  Media island content-area padding (disc + controls + text group):
    property int mediaPadLeft:   0   // px
    property int mediaPadRight:  0   // px
    property int mediaPadTop:    2   // px
    property int mediaPadBottom: 2   // px

    // ═══════════════════════════════════════════════════════════════════════
    //  System Tray
    // ═══════════════════════════════════════════════════════════════════════

    property int trayIconSz:     24   // px — icon image size
    property int trayItemPadH:    3   // px — horizontal padding inside each tray slot
    property int trayItemPadV:    2   // px — vertical padding inside each tray slot
    property int trayItemSpacing: 2   // px — gap between tray icons

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
        "dots":           "⣀⣄⣤⣦⣶⣷⣿⣿",
        "bars":           "▁▂▃▄▅▆▇█",
        "braille_fill":   "⠂⠃⠇⡇⣇⣧⣷⣿",
        "braille_hollow": "⠂⠂⠃⠃⡃⡇⡇⣇",
        "blocks":         "░░▒▒▓▓██",
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
    property string cavaStartWallustVar: "$color4"     // selected wallust variable
    property string cavaEndWallustVar:   "$color0"     // selected wallust variable

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

    // Resolve a wallust "$colorN" → the live Theme.cWcN color.
    function _wallustThemeColor(varName) {
        switch (varName) {
            case "$color0":  return Theme.cWc0
            case "$color1":  return Theme.cWc1
            case "$color2":  return Theme.cWc2
            case "$color3":  return Theme.cWc3
            case "$color4":  return Theme.cWc4
            case "$color5":  return Theme.cWc5
            case "$color6":  return Theme.cWc6
            case "$color7":  return Theme.cWc7
            case "$color8":  return Theme.cWc8
            case "$color9":  return Theme.cWc9
            case "$color10": return Theme.cWc10
            case "$color11": return Theme.cWc11
            case "$color12": return Theme.cWc12
            case "$color13": return Theme.cWc13
            case "$color14": return Theme.cWc14
            case "$color15": return Theme.cWc15
            default:         return Theme.cWc7
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
            : cavaStartMode === "wallust"
                ? _wallustThemeColor(cavaStartWallustVar)
                : _cavaGlyphCustomColor
    property color _cavaGlyphCustomColor: Theme.cPrimary   // overwritten by CC custom pick

    property bool  cavaGradientEnabled:    false

    property color cavaGradientStartColor: cavaStartMode === "matugen"
        ? _cavaThemeColor(cavaStartVar)
        : cavaStartMode === "pywal"
            ? _cavaPywalColor(cavaStartPywalVar)
            : cavaStartMode === "wallust"
                ? _wallustThemeColor(cavaStartWallustVar)
                : _cavaStartCustomColor
    property color _cavaStartCustomColor: Theme.cPrimary   // overwritten by CC custom pick

    property color cavaGradientEndColor: cavaEndMode === "matugen"
        ? _cavaThemeColor(cavaEndVar)
        : cavaEndMode === "pywal"
            ? _cavaPywalColor(cavaEndPywalVar)
            : cavaEndMode === "wallust"
                ? _wallustThemeColor(cavaEndWallustVar)
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

    // Split from ungrouped — Clock & Date island / Weather & Battery islands
    property real  clockDateBgOpacity:  ungroupedBgOpacity
    property real  weatherBatBgOpacity: ungroupedBgOpacity

    // Split from grouped — left app-group island / right app-group island
    property real  leftGroupBgOpacity:  groupedBgOpacity
    property real  rightGroupBgOpacity: groupedBgOpacity

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

    property bool showClock:         true
    property bool showDate:          true
    property bool showWorkspaces:    true
    property bool showCava:          true
    property bool showWeather:       true
    property bool showBattery:       true
    property bool showMediaPlayer:   true
    property bool showIdleInhibitor: true
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
    property bool triLeftAutoHide:       false
    property int  triLeftAutoHideDelay:  5
    property bool triCenterAutoHide:     false
    property int  triCenterAutoHideDelay: 5
    property bool triRightAutoHide:      false
    property int  triRightAutoHideDelay: 5
    // Shell module strip auto-hide (separate from the full-bar auto-hide)
    // shellModuleAutoHide / shellModuleAutoHideDelay live above with the shell geometry props

    // ═══════════════════════════════════════════════════════════════════════
    //  Dock runtime state (source of truth for CC display; GJS dock reads
    //  hyprcandy-bar.conf directly, but CC persists state here so the
    //  toggles show the correct value when the CC reopens)
    // ═══════════════════════════════════════════════════════════════════════
    property bool   dockAutoHide:      false
    property int    dockAutoHideDelay: 5       // seconds
    property int    dockMargin:        6       // px — screen-edge gap

    // ── Desktop icon layer ───────────────────────────────────────────────
    property int  desktopIconSize:    36   // px — app icon size
    property int  desktopLabelSize:   11   // pt — label font size
    property int  desktopLabelRadius: 10   // px — label background corner radius
    property bool desktopVisible:     true // show/hide desktop icon layer

    // ═══════════════════════════════════════════════════════════════════════
    //  Hyprland compositor defaults  (from hyprviz.conf)
    //  These are used as slider starting values until the user has saved
    //  independent values into hyprcandy-bar.conf [hyprland] section.
    // ═══════════════════════════════════════════════════════════════════════
    readonly property real hyprDefaultOpacity:    0.90   // active_opacity / inactive_opacity
    readonly property int  hyprDefaultBlurSize:   2      // blur { size = 2 }
    readonly property int  hyprDefaultBlurPasses: 4      // blur { passes = 4 }
    readonly property int  hyprDefaultGapsIn:     4      // gaps_in = 4
    readonly property int  hyprDefaultGapsOut:    9      // gaps_out = 9
    readonly property int  hyprDefaultBorderW:    3      // border_size = 3
    readonly property int  hyprDefaultBorderR:    20     // rounding = 20

    readonly property bool wsScrollSwitch:  true
    readonly property int  weatherInterval: 300    // seconds
    property int  wsCount:         5      // persistent workspace slots (1–10)
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
    readonly property int trayIconSize:     24
    readonly property int traySpacing:      2
    readonly property int mediaThumbSz:     mediaThumbSize
    readonly property int wsGlyphSz:        wsGlyphSize
}
