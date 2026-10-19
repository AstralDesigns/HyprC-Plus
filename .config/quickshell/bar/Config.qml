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

    // ── Media equalizer (EasyEffects) persistence ────────────────────────
    property var     eqGains   // 10 band gains, dB
    property string  eqPreset
    property bool    eqExpanded

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
        // The shipped config is the single source of truth: every key is read
        // directly (no presence guards, no legacy fallbacks). Only type coercion
        // is applied (the INI backend stores bools/numbers as strings).
        var v
        // Tab 1: General
        v = _settings.value("barMode");            barMode = v
        v = _settings.value("barPosition");        barPosition = v
        v = _settings.value("moduleHeight");       moduleHeight = v
        v = _settings.value("barPad");             barPad = Math.round(+v)
        v = _settings.value("outerMarginTop");     outerMarginTop = v
        v = _settings.value("outerMarginBottom");  outerMarginBottom = v
        v = _settings.value("outerMarginSide");    outerMarginSide = v
        v = _settings.value("triModuleSideMargin"); triModuleSideMargin = parseInt(v)
        v = _settings.value("barEdgePaddingLeft");  barEdgePaddingLeft  = v
        v = _settings.value("barEdgePaddingRight"); barEdgePaddingRight = v
        // Corner radii — each reads its own key.
        v = _settings.value("barTopLeftRadius");     barTopLeftRadius     = parseInt(v)
        v = _settings.value("barTopRightRadius");    barTopRightRadius    = parseInt(v)
        v = _settings.value("barBottomLeftRadius");  barBottomLeftRadius  = parseInt(v)
        v = _settings.value("barBottomRightRadius"); barBottomRightRadius = parseInt(v)
        v = _settings.value("triLeftTopRightRadius");    triLeftTopRightRadius    = parseInt(v)
        v = _settings.value("triLeftBottomRightRadius"); triLeftBottomRightRadius = parseInt(v)
        v = _settings.value("triCenterTopLeftRadius");    triCenterTopLeftRadius    = parseInt(v)
        v = _settings.value("triCenterTopRightRadius");   triCenterTopRightRadius   = parseInt(v)
        v = _settings.value("triCenterBottomLeftRadius"); triCenterBottomLeftRadius = parseInt(v)
        v = _settings.value("triCenterBottomRightRadius");triCenterBottomRightRadius= parseInt(v)
        v = _settings.value("triRightTopLeftRadius");    triRightTopLeftRadius    = parseInt(v)
        v = _settings.value("triRightBottomLeftRadius"); triRightBottomLeftRadius = parseInt(v)
        v = _settings.value("shellArmThickness");          shellArmThickness          = parseInt(v)
        v = _settings.value("shellInnerRadius");           shellInnerRadius           = parseInt(v)
        v = _settings.value("shellModuleSideMargin");      shellModuleSideMargin      = parseInt(v)
        v = _settings.value("shellModuleAutoHide");        shellModuleAutoHide        = _toBool(v)
        v = _settings.value("shellModuleAutoHideDelay");   shellModuleAutoHideDelay   = parseInt(v)
        v = _settings.value("shellCenterJunctionRadius");  shellCenterJunctionRadius  = parseInt(v)
        v = _settings.value("islandRadius"); islandRadius = v
        v = _settings.value("islandBorder"); islandBorder = v
        v = _settings.value("islandBorderAlpha"); islandBorderAlpha = v
        v = _settings.value("borderWs"); borderWs = _toBool(v)
        v = _settings.value("borderClockDate"); borderClockDate = _toBool(v)
        v = _settings.value("borderWeatherBat"); borderWeatherBat = _toBool(v)
        v = _settings.value("borderLeftGroup"); borderLeftGroup = _toBool(v)
        v = _settings.value("borderRightGroup"); borderRightGroup = _toBool(v)
        v = _settings.value("borderStartMenu"); borderStartMenu = _toBool(v)
        v = _settings.value("borderMedia"); borderMedia = _toBool(v)
        v = _settings.value("borderCava"); borderCava = _toBool(v)
        v = _settings.value("borderDistro"); borderDistro = _toBool(v)
        v = _settings.value("borderStartTrash"); borderStartTrash = _toBool(v)
        v = _settings.value("tipPowerProfiles"); tipPowerProfiles = _toBool(v)
        v = _settings.value("tipOverview"); tipOverview = _toBool(v)
        v = _settings.value("tipPower"); tipPower = _toBool(v)
        v = _settings.value("tipSystemTray"); tipSystemTray = _toBool(v)
        v = _settings.value("tipNotifications"); tipNotifications = _toBool(v)
        v = _settings.value("tipMedia"); tipMedia = _toBool(v)
        v = _settings.value("tipWeather"); tipWeather = _toBool(v)
        v = _settings.value("tipBattery"); tipBattery = _toBool(v)
        v = _settings.value("tipClock"); tipClock = _toBool(v)
        v = _settings.value("tipDate"); tipDate = _toBool(v)
        v = _settings.value("tipWallpaper"); tipWallpaper = _toBool(v)
        v = _settings.value("tipUpdates"); tipUpdates = _toBool(v)
        v = _settings.value("tipControlCenter"); tipControlCenter = _toBool(v)
        v = _settings.value("tipIdleInhibitor"); tipIdleInhibitor = _toBool(v)
        v = _settings.value("islandBorderVar"); islandBorderVar = v
        v = _settings.value("islandBorderMode"); islandBorderMode = v
        v = _settings.value("islandBorderWallustVar"); islandBorderWallustVar = v
        v = _settings.value("islandBorderGradient"); islandBorderGradient = _toBool(v)
        v = _settings.value("islandBorderSecondVar"); islandBorderSecondVar = v
        v = _settings.value("islandBorderSecondMode"); islandBorderSecondMode = v
        v = _settings.value("islandBorderSecondWallustVar"); islandBorderSecondWallustVar = v
        v = _settings.value("islandBorderAngle"); islandBorderAngle = parseFloat(v)
        v = _settings.value("barBorderWidth"); barBorderWidth = v
        v = _settings.value("barBorderAlpha"); barBorderAlpha = v
        v = _settings.value("barBorderVar"); barBorderVar = v
        v = _settings.value("barBorderMode"); barBorderMode = v
        v = _settings.value("barBorderWallustVar"); barBorderWallustVar = v
        v = _settings.value("barBorderGradient"); barBorderGradient = _toBool(v)
        v = _settings.value("barBorderSecondVar"); barBorderSecondVar = v
        v = _settings.value("barBorderSecondMode"); barBorderSecondMode = v
        v = _settings.value("barBorderSecondWallustVar"); barBorderSecondWallustVar = v
        v = _settings.value("barBorderAngle"); barBorderAngle = parseFloat(v)
        v = _settings.value("islandBgStyle");  islandBgStyle  = v
        v = _settings.value("barRectBgStyle"); barRectBgStyle = v
        v = _settings.value("moduleBgOpacity"); moduleBgOpacity = v
        v = _settings.value("islandBgOpacityIsland"); islandBgOpacityIsland = v
        v = _settings.value("islandSpacing"); islandSpacing = v
        v = _settings.value("modPadH"); modPadH = v
        v = _settings.value("modPadV"); modPadV = v
        v = _settings.value("groupedSpacing"); groupedSpacing = v
        v = _settings.value("glyphSize"); glyphSize = v
        v = _settings.value("infoGlyphSize"); infoGlyphSize = v
        v = _settings.value("mediaGlyphSize"); mediaGlyphSize = v
        v = _settings.value("weatherIconSize"); weatherIconSize = v
        v = _settings.value("infoFontSize");   infoFontSize   = v
        v = _settings.value("labelFontSize");  labelFontSize  = v
        v = _settings.value("mediaCtlSize"); mediaCtlSize = v
        v = _settings.value("mediaThumbSize"); mediaThumbSize = v
        v = _settings.value("batteryRadialVisible"); batteryRadialVisible = _toBool(v)
        v = _settings.value("batteryRadialSize"); batteryRadialSize = v
        v = _settings.value("batteryRadialWidth"); batteryRadialWidth = v
        v = _settings.value("trayIconSz"); trayIconSz = v
        v = _settings.value("trayItemPadH");   trayItemPadH   = v
        v = _settings.value("trayItemSpacing"); trayItemSpacing = v
        v = _settings.value("ccGlyph"); ccGlyph = v
        v = _settings.value("ccGlyphColorA"); ccGlyphOpacity = Math.min(1, Math.max(0, parseFloat(v)))
        v = _settings.value("wsCount"); wsCount = Math.min(10, Math.max(1, parseInt(v)))
        v = _settings.value("barMonitors")
        try {
            const parsed = typeof v === "string" ? JSON.parse(v) : v
            if (Array.isArray(parsed) && parsed.length > 0) barMonitors = parsed
        } catch (e) {
            barMonitors = [0]
        }
        v = _settings.value("wsIconMode"); wsIconMode = v
        v = _settings.value("wsGlyphSize"); wsGlyphSize = v
        v = _settings.value("wsSpacing"); wsSpacing = v
        v = _settings.value("wsMarginLeft"); wsMarginLeft = v
        v = _settings.value("wsMarginRight"); wsMarginRight = v
        v = _settings.value("wsPadLeft"); wsPadLeft = v
        v = _settings.value("wsPadRight"); wsPadRight = v
        v = _settings.value("wsPadTop"); wsPadTop = v
        v = _settings.value("wsPadBottom"); wsPadBottom = v
        v = _settings.value("wsSeparators"); wsSeparators = _toBool(v)
        v = _settings.value("wsSeparatorSize"); wsSeparatorSize = v
        v = _settings.value("wsSeparatorPadLeft"); wsSeparatorPadLeft = v
        v = _settings.value("wsSeparatorPadRight"); wsSeparatorPadRight = v
        v = _settings.value("wsSeparatorGlyph"); wsSeparatorGlyph = v
        v = _settings.value("wsDotActive"); wsDotActive = v
        v = _settings.value("wsDotPersistent"); wsDotPersistent = v
        v = _settings.value("wsDotEmpty"); wsDotEmpty = v
        v = _settings.value("wsIcons"); try { wsIcons = JSON.parse(v) } catch(e) {}
        v = _settings.value("wsActiveOpacity");     wsActiveOpacity     = v
        v = _settings.value("wsPersistentOpacity"); wsPersistentOpacity = v
        v = _settings.value("wsEmptyOpacity");      wsEmptyOpacity      = v
        v = _settings.value("wsSeparatorOpacity");  wsSeparatorOpacity  = v
        v = _settings.value("mediaInfoFontSize"); mediaInfoFontSize = v
        v = _settings.value("mediaPadLeft"); mediaPadLeft = v
        v = _settings.value("mediaPadRight"); mediaPadRight = v
        v = _settings.value("mediaPadTop"); mediaPadTop = v
        v = _settings.value("mediaPadBottom"); mediaPadBottom = v
        v = _settings.value("cavaWidth"); cavaWidth = v
        v = _settings.value("cavaBarSpacing"); cavaBarSpacing = v
        v = _settings.value("cavaStyle"); cavaStyle = v
        v = _settings.value("cavaWaveThickness"); cavaWaveThickness = v
        v = _settings.value("cavaWaveSmooth"); cavaWaveSmooth = _toBool(v)
        v = _settings.value("cavaTransparentWhenInactive"); cavaTransparentWhenInactive = _toBool(v)
        v = _settings.value("eqGains"); try { eqGains = JSON.parse(v) } catch(e) {}
        v = _settings.value("eqPreset"); eqPreset = v
        v = _settings.value("eqExpanded"); eqExpanded = _toBool(v)
        v = _settings.value("cavaActiveOpacity"); cavaActiveOpacity = v
        v = _settings.value("cavaInactiveOpacity"); cavaInactiveOpacity = v
        v = _settings.value("cavaAutoHide"); cavaAutoHide = _toBool(v)
        v = _settings.value("cavaGradientEnabled"); cavaGradientEnabled = _toBool(v)
        v = _settings.value("cavaGradientSplit"); cavaGradientSplit = parseFloat(v)
        v = _settings.value("cavaStartMode"); cavaStartMode = v
        v = _settings.value("cavaEndMode");   cavaEndMode   = v
        v = _settings.value("cavaStartVar");  cavaStartVar  = v
        v = _settings.value("cavaEndVar");    cavaEndVar    = v
        v = _settings.value("cavaStartPywalVar"); cavaStartPywalVar = v
        v = _settings.value("cavaEndPywalVar");   cavaEndPywalVar   = v
        v = _settings.value("cavaStartWallustVar"); cavaStartWallustVar = v
        v = _settings.value("cavaEndWallustVar");   cavaEndWallustVar   = v
        v = _settings.value("cavaStartCustomColor"); _cavaStartCustomColor = v
        v = _settings.value("cavaEndCustomColor");   _cavaEndCustomColor   = v
        v = _settings.value("cavaGlyphCustomColor"); _cavaGlyphCustomColor = v
        v = _settings.value("wsBgOpacity"); wsBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("groupedBgOpacity"); groupedBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("ungroupedBgOpacity"); ungroupedBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("clockDateBgOpacity");  clockDateBgOpacity  = Math.max(0, parseFloat(v))
        v = _settings.value("weatherBatBgOpacity"); weatherBatBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("leftGroupBgOpacity");  leftGroupBgOpacity  = Math.max(0, parseFloat(v))
        v = _settings.value("rightGroupBgOpacity"); rightGroupBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("trayBgOpacity"); trayBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("startMenuBgOpacity"); startMenuBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("mediaBgOpacity"); mediaBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("cavaBgOpacity"); cavaBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("distroBgOpacity"); distroBgOpacity = Math.max(0, parseFloat(v))
        v = _settings.value("activeWindowBgOpacity"); activeWindowBgOpacity = v
        v = _settings.value("activeWindowMinWidth"); activeWindowMinWidth = v
        v = _settings.value("showClock"); showClock = _toBool(v)
        v = _settings.value("showDate"); showDate = _toBool(v)
        v = _settings.value("showWorkspaces"); showWorkspaces = _toBool(v)
        v = _settings.value("showCava"); showCava = _toBool(v)
        v = _settings.value("showWeather"); showWeather = _toBool(v)
        v = _settings.value("showBattery"); showBattery = _toBool(v)
        v = _settings.value("showMediaPlayer"); showMediaPlayer = _toBool(v)
        v = _settings.value("showIdleInhibitor"); showIdleInhibitor = _toBool(v)
        v = _settings.value("showUpdates"); showUpdates = _toBool(v)
        v = _settings.value("showPowerProfiles"); showPowerProfiles = _toBool(v)
        v = _settings.value("showOverview"); showOverview = _toBool(v)
        v = _settings.value("showNotifications"); showNotifications = _toBool(v)
        v = _settings.value("showWallpaper"); showWallpaper = _toBool(v)
        v = _settings.value("showTray"); showTray = _toBool(v)
        v = _settings.value("showBluetooth"); showBluetooth = _toBool(v)
        //v = _settings.value("showWindow"); showWindow = v
        v = _settings.value("showDistro"); showDistro = _toBool(v)
        // ── Launcher (GJS app-launcher) ───────────────────────────────────
        v = _settings.value("launcherSearchWidth");    launcherSearchWidth    = v
        v = _settings.value("launcherIconSize");       launcherIconSize       = v
        v = _settings.value("launcherTextFontSize");   launcherTextFontSize   = v
        v = _settings.value("launcherFixedTileWidth"); launcherFixedTileWidth = v
        v = _settings.value("launcherFixedTileHeight");launcherFixedTileHeight= v
        v = _settings.value("launcherFrameWidth");     launcherFrameWidth     = v
        v = _settings.value("launcherFrameHeight");    launcherFrameHeight    = v
        v = _settings.value("launcherFrameWidthVert"); launcherFrameWidthVert = v
        v = _settings.value("launcherFrameHeightVert");launcherFrameHeightVert= v
        v = _settings.value("launcherBorderRadius");   launcherBorderRadius   = v
        v = _settings.value("launcherBorderWidth");    launcherBorderWidth    = v
        v = _settings.value("launcherSearchRadius");   launcherSearchRadius   = v
        v = _settings.value("launcherListRadius");     launcherListRadius     = v
        v = _settings.value("launcherInnerBorderWidth"); launcherInnerBorderWidth = v
        v = _settings.value("launcherInnerPadding");   launcherInnerPadding   = v
        // Bar autohide + dock runtime state
        v = _settings.value("barAutoHide");      barAutoHide      = _toBool(v)
        v = _settings.value("barAutoHideDelay"); barAutoHideDelay = parseInt(v)
        v = _settings.value("triLeftAutoHide");       triLeftAutoHide       = _toBool(v)
        v = _settings.value("triLeftAutoHideDelay");  triLeftAutoHideDelay  = parseInt(v)
        v = _settings.value("triCenterAutoHide");     triCenterAutoHide     = _toBool(v)
        v = _settings.value("triCenterAutoHideDelay");triCenterAutoHideDelay = parseInt(v)
        v = _settings.value("triRightAutoHide");      triRightAutoHide      = _toBool(v)
        v = _settings.value("triRightAutoHideDelay"); triRightAutoHideDelay = parseInt(v)
        v = _settings.value("dockAutoHide");     dockAutoHide     = _toBool(v)
        v = _settings.value("dockAutoHideDelay");dockAutoHideDelay= parseInt(v)
        v = _settings.value("dockMargin");       dockMargin       = parseInt(v)
        // ── Dock appearance (qs-native dock — source of truth, replaces GJS config.js) ──
        v = _settings.value("dockIconSize");       dockIconSize       = parseInt(v)
        v = _settings.value("dockStartIconSize");  dockStartIconSize  = parseInt(v)
        v = _settings.value("dockTrashIconSize");  dockTrashIconSize  = parseInt(v)
        v = _settings.value("dockButtonSpacing");  dockButtonSpacing  = parseInt(v)
        v = _settings.value("dockInnerPadding");   dockInnerPadding   = parseInt(v)
        v = _settings.value("dockPadding");        dockPadding        = parseInt(v)
        v = _settings.value("dockRadius");         dockRadius         = parseInt(v)
        v = _settings.value("dockTopLeftRadius");    dockTopLeftRadius    = parseInt(v)
        v = _settings.value("dockTopRightRadius");   dockTopRightRadius   = parseInt(v)
        v = _settings.value("dockBottomLeftRadius"); dockBottomLeftRadius = parseInt(v)
        v = _settings.value("dockBottomRightRadius");dockBottomRightRadius= parseInt(v)
        v = _settings.value("dockBorderWidth");    dockBorderWidth    = parseInt(v)
        v = _settings.value("dockBorderAlpha");    dockBorderAlpha    = v
        v = _settings.value("dockBorderColorVar"); dockBorderColorVar = v
        v = _settings.value("dockBackgroundStyle");dockBackgroundStyle= v
        v = _settings.value("dockPosition");       dockPosition       = v
        v = _settings.value("dockStartIcon");      dockStartIcon      = v
        v = _settings.value("dockLayer");          dockLayer          = v
        v = _settings.value("dockReserveSpace");   dockReserveSpace   = _toBool(v)
        // dockVisible is special: shell.qml gates the dock Loader on it, so an
        // ABSENT key (fresh install / not-yet-migrated device) must read as
        // visible. _toBool(null) would otherwise yield false and destroy the
        // DockWindow + its reveal hotspot with no way back. An explicit stored
        // value (true OR false) still wins, keeping the INI authoritative.
        v = _settings.value("dockVisible", true);   dockVisible        = _toBool(v)
        v = _settings.value("desktopIconSize");    desktopIconSize    = parseInt(v)
        v = _settings.value("desktopLabelSize");   desktopLabelSize   = parseInt(v)
        v = _settings.value("desktopLabelRadius"); desktopLabelRadius = parseInt(v)
        v = _settings.value("desktopVisible");     desktopVisible     = _toBool(v)
        v = _settings.value("clockTextSize");      clockTextSize      = parseInt(v)
        v = _settings.value("clockIconSize");      clockIconSize      = parseInt(v)
        v = _settings.value("clockWorldCities");   try { clockWorldCities = JSON.parse(v) } catch(e) {}
    }

    function _saveSettings() {
        _settings.setValue("barMode", barMode)
        _settings.setValue("barPosition", barPosition)
        _settings.setValue("barPad", barPad)
        _settings.setValue("moduleHeight", moduleHeight)
        _settings.setValue("outerMarginTop", outerMarginTop)
        _settings.setValue("outerMarginBottom", outerMarginBottom)
        _settings.setValue("outerMarginSide", outerMarginSide)
        _settings.setValue("triModuleSideMargin", triModuleSideMargin)
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
        _settings.setValue("borderWs", borderWs)
        _settings.setValue("borderClockDate", borderClockDate)
        _settings.setValue("borderWeatherBat", borderWeatherBat)
        _settings.setValue("borderLeftGroup", borderLeftGroup)
        _settings.setValue("borderRightGroup", borderRightGroup)
        _settings.setValue("borderStartMenu", borderStartMenu)
        _settings.setValue("borderMedia", borderMedia)
        _settings.setValue("borderCava", borderCava)
        _settings.setValue("borderDistro", borderDistro)
        _settings.setValue("borderStartTrash", borderStartTrash)
        _settings.setValue("tipPowerProfiles", tipPowerProfiles)
        _settings.setValue("tipOverview", tipOverview)
        _settings.setValue("tipPower", tipPower)
        _settings.setValue("tipSystemTray", tipSystemTray)
        _settings.setValue("tipNotifications", tipNotifications)
        _settings.setValue("tipMedia", tipMedia)
        _settings.setValue("tipWeather", tipWeather)
        _settings.setValue("tipBattery", tipBattery)
        _settings.setValue("tipClock", tipClock)
        _settings.setValue("tipDate", tipDate)
        _settings.setValue("tipWallpaper", tipWallpaper)
        _settings.setValue("tipUpdates", tipUpdates)
        _settings.setValue("tipControlCenter", tipControlCenter)
        _settings.setValue("tipIdleInhibitor", tipIdleInhibitor)
        _settings.setValue("islandBorderVar", islandBorderVar)
        _settings.setValue("islandBorderMode", islandBorderMode)
        _settings.setValue("islandBorderWallustVar", islandBorderWallustVar)
        _settings.setValue("islandBorderGradient", islandBorderGradient)
        _settings.setValue("islandBorderSecondVar", islandBorderSecondVar)
        _settings.setValue("islandBorderSecondMode", islandBorderSecondMode)
        _settings.setValue("islandBorderSecondWallustVar", islandBorderSecondWallustVar)
        _settings.setValue("islandBorderAngle", islandBorderAngle)
        _settings.setValue("barBorderWidth", barBorderWidth)
        _settings.setValue("barBorderAlpha", barBorderAlpha)
        _settings.setValue("barBorderVar", barBorderVar)
        _settings.setValue("barBorderMode", barBorderMode)
        _settings.setValue("barBorderWallustVar", barBorderWallustVar)
        _settings.setValue("barBorderGradient", barBorderGradient)
        _settings.setValue("barBorderSecondVar", barBorderSecondVar)
        _settings.setValue("barBorderSecondMode", barBorderSecondMode)
        _settings.setValue("barBorderSecondWallustVar", barBorderSecondWallustVar)
        _settings.setValue("barBorderAngle", barBorderAngle)
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
        _settings.setValue("weatherIconSize", weatherIconSize)
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
        _settings.setValue("barMonitors", JSON.stringify(barMonitors))
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
        _settings.setValue("cavaWaveThickness", cavaWaveThickness)
        _settings.setValue("cavaWaveSmooth", cavaWaveSmooth)
        _settings.setValue("cavaTransparentWhenInactive", cavaTransparentWhenInactive)
        _settings.setValue("eqGains", JSON.stringify(eqGains))
        _settings.setValue("eqPreset", eqPreset)
        _settings.setValue("eqExpanded", eqExpanded)
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
        // ── Dock appearance (qs-native dock) ──
        _settings.setValue("dockIconSize",        dockIconSize)
        _settings.setValue("dockStartIconSize",   dockStartIconSize)
        _settings.setValue("dockTrashIconSize",   dockTrashIconSize)
        _settings.setValue("dockButtonSpacing",   dockButtonSpacing)
        _settings.setValue("dockInnerPadding",    dockInnerPadding)
        _settings.setValue("dockPadding",         dockPadding)
        _settings.setValue("dockRadius",          dockRadius)
        _settings.setValue("dockTopLeftRadius",   dockTopLeftRadius)
        _settings.setValue("dockTopRightRadius",  dockTopRightRadius)
        _settings.setValue("dockBottomLeftRadius",dockBottomLeftRadius)
        _settings.setValue("dockBottomRightRadius",dockBottomRightRadius)
        _settings.setValue("dockBorderWidth",     dockBorderWidth)
        _settings.setValue("dockBorderAlpha",     dockBorderAlpha)
        _settings.setValue("dockBorderColorVar",  dockBorderColorVar)
        _settings.setValue("dockBackgroundStyle", dockBackgroundStyle)
        _settings.setValue("dockPosition",        dockPosition)
        _settings.setValue("dockStartIcon",       dockStartIcon)
        _settings.setValue("dockLayer",           dockLayer)
        _settings.setValue("dockReserveSpace",    dockReserveSpace)
        _settings.setValue("dockVisible",         dockVisible)
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
    property string barMode   // "bar" | "island" | "tri" | "shell"
    property string barPosition   // "top" | "bottom" | "left" | "right"

    // ── Bar geometry ─────────────────────────────────────────────────────
    //  barPad       = uniform inset on every side of the bar ("bar") and of the
    //                 3 islands ("tri"/"shell"). Replaces the old Bar Height pad
    //                 + the Edge Pad L/R sliders. "island" mode keeps its own
    //                 edge spacing and is driven only by the derived strip.
    //  moduleHeight = visual island/pill height
    //  barHeight    = reserved screen strip (PanelWindow exclusion zone),
    //                 DERIVED = moduleHeight + 2*barPad. All consumers (popups,
    //                 reserved zone, island heights) keep reading barHeight.
    property int barPad    // px — per-side padding ("Bar Pad" slider)
    property int moduleHeight   // px — visual island/pill height
    readonly property int barHeight: moduleHeight + 2 * barPad   // derived strip

    //  Outer margins from screen edges:
    // Widget-local — Top/Bottom sliders always match visual edge; values swap on top↔bottom flip.
    property int outerMarginTop   // px — gap from screen top (when bar at top)
    property int outerMarginBottom   // px — gap from screen bottom (when bar at bottom)
    property int outerMarginSide   // px — gap from left & right screen edges — used by "bar" & "island" modes
    property int triModuleSideMargin   // px — side margin for the left/right tri islands (split from outerMarginSide)

    //  Resolved side margin for the active bar mode — popups (and the tri/shell
    //  islands themselves) should read this instead of outerMarginSide directly,
    //  so both track whichever mode is active off the SAME module-margin value
    //  (no separate popup-only slider). In shell mode the island content edge is
    //  offset by the frame arm (shellArmThickness) PLUS the module side margin, so
    //  popups add the arm term too, keeping them aligned to the island edge.
    readonly property real popupSideMargin: barMode === "tri"   ? triModuleSideMargin
        : barMode === "shell" ? shellArmThickness + shellModuleSideMargin
        : outerMarginSide

    //  Far-edge padding: extra inset from the barBg L/R edges to the first/last
    //  module group. Adds inner breathing room in "bar" mode.
    property int barEdgePaddingLeft   // px
    property int barEdgePaddingRight   // px

    // ── Radii ────────────────────────────────────────────────────────────
    // Widget-local corners — sliders always match visual TL/TR/BL/BR.
    // On top↔bottom flip, values swap vertically so screen-edge rounding carries over.
    property int barTopLeftRadius
    property int barTopRightRadius
    property int barBottomLeftRadius
    property int barBottomRightRadius
    readonly property int barRadius: barTopLeftRadius
    // tri mode — outer corners share bar TL/BL (left) and TR/BR (right); inner corners independent
    property int triLeftTopRightRadius
    property int triLeftBottomRightRadius
    property int triCenterTopLeftRadius
    property int triCenterTopRightRadius
    property int triCenterBottomLeftRadius
    property int triCenterBottomRightRadius
    property int triRightTopLeftRadius
    property int triRightBottomLeftRadius

    // ── Shell mode properties ─────────────────────────────────────────────
    property int shellArmThickness   // px — frame arm width on all 4 sides
    property int shellInnerRadius   // px — inner corner radius (all 4)
    property int shellCenterJunctionRadius   // px — island junction corner radius
    property int  shellModuleSideMargin    // px — side margin for the module strip in shell mode
    property bool shellModuleAutoHide
    property int  shellModuleAutoHideDelay    // seconds

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

    property int islandRadius   // px — island pill corner radius

    // ── Island border ────────────────────────────────────────────────────
    property int  islandBorder     // px — 0 to remove
    property real islandBorderAlpha  // 0–1
    property string islandBorderVar  // matugen variable
    property string islandBorderMode           // "matugen" | "wallust"
    property string islandBorderWallustVar           // wallust color0–color15
    readonly property color islandBorderColor: islandBorderMode === "wallust"
        ? _wallustThemeColor(islandBorderWallustVar)
        : _cavaThemeColor(islandBorderVar)
    // island border gradient: a second colour + angle, rendered by the
    //  GradientBorder Canvas overlay when <prefix>BorderGradient is on.
    property bool   islandBorderGradient
    property string islandBorderSecondVar
    property string islandBorderSecondMode
    property string islandBorderSecondWallustVar
    readonly property color islandBorderColor2: islandBorderSecondMode === "wallust"
        ? _wallustThemeColor(islandBorderSecondWallustVar)
        : _cavaThemeColor(islandBorderSecondVar)
    property real   islandBorderAngle

    // ── Per-island border on/off toggles — each gates whether that
    //  island draws the border; all share the global islandBorder width
    //  (Island B-W) and islandBorderAlpha (Island B-α) above.
    property bool borderWs
    property bool borderClockDate
    property bool borderWeatherBat
    property bool borderLeftGroup
    property bool borderRightGroup
    property bool borderStartMenu
    property bool borderMedia
    property bool borderCava
    property bool borderDistro
    property bool borderStartTrash

    // ── Bar-module hover tooltips — each gates whether that module shows its
    //  hover tooltip (driven by BarTipState). The tooltip text lives in the
    //  module itself; these toggles only turn the popup on/off per module.
    property bool tipPowerProfiles
    property bool tipOverview
    property bool tipPower
    property bool tipSystemTray
    property bool tipNotifications
    property bool tipMedia
    property bool tipWeather
    property bool tipBattery
    property bool tipClock
    property bool tipDate
    property bool tipWallpaper
    property bool tipUpdates
    property bool tipControlCenter
    property bool tipIdleInhibitor

    // ── Main bar border (bar mode only) ──────────────────────────────────
    property int  barBorderWidth    // px — 0 to hide
    property real barBorderAlpha  // opacity
    property string barBorderVar  // matugen variable
    property string barBorderMode        // "matugen" | "wallust"
    property string barBorderWallustVar        // wallust color0–color15
    readonly property color barBorderColor: barBorderMode === "wallust"
        ? _wallustThemeColor(barBorderWallustVar)
        : _cavaThemeColor(barBorderVar)
    // bar border gradient: a second colour + angle, rendered by the
    //  GradientBorder Canvas overlay when <prefix>BorderGradient is on.
    property bool   barBorderGradient
    property string barBorderSecondVar
    property string barBorderSecondMode
    property string barBorderSecondWallustVar
    readonly property color barBorderColor2: barBorderSecondMode === "wallust"
        ? _wallustThemeColor(barBorderSecondWallustVar)
        : _cavaThemeColor(barBorderSecondVar)
    property real   barBorderAngle

    // ── Island background opacity ─────────────────────────────────────────
    //  moduleBgOpacity  — flat tint alpha in bar mode (also used by islandBgOpacityBar)
    //  islandBgOpacityIsland — gradient alpha in island mode
    property string islandBgStyle    // "flat" | "gradient" — island pill fill style
    property string barRectBgStyle   // "glass" | "gradient" — outer bar/tri rect fill

    property real moduleBgOpacity   // 0.0 transparent → 1.0 opaque
    property real islandBgOpacityIsland
    property real islandBgAlpha:         0.7   // legacy alias
    readonly property real islandBgOpacityBar: moduleBgOpacity

    // ── Island spacing ────────────────────────────────────────────────────
    property int islandSpacing   // px — gap between all top-level items

    // ── Module spacing & padding ─────────────────────────────────────────
    //  THREE-TIER MODEL
    //  islandSpacing  → between top-level groups / standalone islands
    //  groupedSpacing → between modules inside one island
    //  wsSpacing      → between workspace buttons (0 = truly no gap)
    //  modPadH/V      → per-side padding inside each module container
    property int modPadH   // px — per-side H padding in each module
    property int modPadV   // px — per-side V padding in each module
    property int groupedSpacing   // px — gap between modules within a group

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
    property int glyphSize   // px
    property int infoGlyphSize   // px — clock / date / weather icon
    property int mediaGlyphSize   // px — media player toggle glyph
    property int weatherIconSize  // px - weather bar module icon (was infoGlyphSize+2)

    //  Text (label) sizes:
    //  infoFontSize  — time, date, weather value, battery %
    //  labelFontSize — active-window title, short labels
    property int infoFontSize   // px
    property int mediaInfoFontSize   // px — kept for compat (unused in bar media module)
    property int labelFontSize   // px

    //  Convenience aliases (keep older modules unchanged):
    readonly property int fontSize:      glyphSize
    readonly property int mediaFontSize: mediaInfoFontSize

    // ── Palette colors ───────────────────────────────────────────────────
    //  glyphColor  → all NF glyphs (ws dots, cava, generic icons)
    //  textColor   → info text (time, date, weather value, battery %)
    //  activeColor → active workspace, accent highlights
    //  dimColor    → empty workspaces, secondary info
    readonly property color glyphColor:  Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, 1.00)
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
    property int clockTextSize   // C059 Bold Italic time font size in ClockPopup
    property int clockIconSize   // Nerd-font clock icon size in ClockPopup

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
    property color powerGlyphColor:      Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 1.00)
    property color windowTextColor:      Theme.cInverseSurface
    property real  ccGlyphOpacity
    readonly property color ccGlyphColor: Qt.rgba(Theme.cWc13.r, Theme.cWc13.g, Theme.cWc13.b, ccGlyphOpacity)

    // ── Battery radial indicator ─────────────────────────────────────────
    property bool batteryRadialVisible
    property int  batteryRadialSize   // px diameter
    property int  batteryRadialWidth    // px stroke

    // ── Control-center / startmenu glyphs ────────────────────────────────
    property string ccGlyph     // nf-linux-hyprland
    property string powerGlyph:    ""     // nf-fa-chevron_circle_down
    property bool   ccTransparentBg: true

    // ── Icon-text gap ─────────────────────────────────────────────────────
    readonly property int iconTextGap: 2   // px — between glyph icon and label

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 3 · Workspaces
    // ═══════════════════════════════════════════════════════════════════════

    // ── Bar Monitor Display ───────────────────────────────────────────────
    // Selected monitor indices for bar display (defaults to main monitor [0] when multiple exist)
    property var barMonitors: [0]

    // ── Icon mode ────────────────────────────────────────────────────────
    //  "dot"    — wsDotActive / wsDotPersistent / wsDotEmpty per state
    //  "number" — workspace number as text
    //  "icon"   — wsIcons array; falls back to state dots on empty entry
    property string wsIconMode

    property string wsDotActive
    property string wsDotPersistent
    property string wsDotEmpty

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
    property real wsActiveOpacity
    property real wsPersistentOpacity
    property real wsEmptyOpacity
    readonly property color wsActiveColor:     Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, wsActiveOpacity)
    readonly property color wsPersistentColor: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, wsPersistentOpacity)
    readonly property color wsEmptyColor:      Qt.rgba(Theme.cWc10.r, Theme.cWc10.g, Theme.cWc10.b, wsEmptyOpacity)

    // ── Workspace icon size ───────────────────────────────────────────────
    //  wsGlyphSize controls the font size of workspace button icons.
    //  Set independently from the global glyphSize so ws icons can be
    //  larger/smaller than other glyphs without affecting the whole bar.
    property int wsGlyphSize   // px

    // ── Workspace spacing & padding ───────────────────────────────────────
    //  wsSpacing = gap between buttons; 0 = truly no gap (button sized to glyph)
    property int wsSpacing   // px — between workspace buttons
    property int wsMarginLeft   // px — gap from bar-left edge to first ws
    property int wsMarginRight   // px — gap from bar-right edge to last ws
    property int wsPadLeft   // px — left inside each ws button
    property int wsPadRight   // px — right inside each ws button
    property int wsPadTop   // px — top inside each ws button
    property int wsPadBottom   // px — bottom inside each ws button

    // ── Workspace separators ─────────────────────────────────────────────
    property bool   wsSeparators  // show glyph separator between buttons
    property string wsSeparatorGlyph
    property real   wsSeparatorOpacity
    readonly property color wsSeparatorColor: Qt.rgba(Theme.cSurfaceTint.r, Theme.cSurfaceTint.g, Theme.cSurfaceTint.b, wsSeparatorOpacity)
    property int    wsSeparatorSize    // px — font size of the separator glyph
    property int    wsSeparatorPadLeft     // px — space between left ws button and separator
    property int    wsSeparatorPadRight     // px — space between separator and right ws button

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 4 · Media
    // ═══════════════════════════════════════════════════════════════════════

    property int    mediaThumbSize   // px — album art thumb (auto-hides when no art)
    property int    mediaCtlSize   // px — prev / play-pause / next glyph size
    property string mediaToggleGlyph:  "󰽲"  // nf-md-music_note — GJS toggle button glyph
    // mediaGlyphSize is defined in Tab 2 Icons

    //  Media island content-area padding (disc + controls + text group):
    property int mediaPadLeft   // px
    property int mediaPadRight   // px
    property int mediaPadTop   // px
    property int mediaPadBottom   // px

    // ═══════════════════════════════════════════════════════════════════════
    //  System Tray
    // ═══════════════════════════════════════════════════════════════════════

    property int trayIconSz   // px — icon image size
    property int trayItemPadH   // px — horizontal padding inside each tray slot
    property int trayItemPadV:    2   // px — vertical padding inside each tray slot
    property int trayItemSpacing   // px — gap between tray icons

    // ═══════════════════════════════════════════════════════════════════════
    //  TAB 5 · Cava
    // ═══════════════════════════════════════════════════════════════════════

    property int cavaWidth      // ASCII bar count (number of columns rendered by cava)
    property real cavaBarSpacing  // px — letter-spacing between bars (0 = no gap; fine increments)

    //  cavaStyle selects a preset — either an ASCII glyph ramp (cavaStyleMap)
    //  or a Canvas paint style (cavaPaintMap). Set to "" to use cavaBars.
    //  ASCII presets are amplitude RAMPS (index 0 = quiet -> last = loud); one
    //  glyph is picked per band, so the string must grow monotonically in
    //  density/height. Paint presets are drawn live by bar/scripts/cavapaint.js.
    property string cavaStyle

    readonly property var cavaStyleMap: ({
        "dots":           "⣀⣄⣤⣦⣶⣷⣿⣿",
        "bars":           "▁▂▃▄▅▆▇█",
        "braille_fill":   "⠂⠃⠇⡇⣇⣧⣷⣿",
        "braille_hollow": "⠂⠂⠃⠃⡃⡇⡇⣇",
        "blocks":         "░░▒▒▓▓██",
        "thin_bars":      "⡀⡄⡆⡇⣇⣧⣷⣿",
        "braille_soft":   "⣀⣀⣄⣤⣦⣶⣷⣿", // smooth flowing braille ramp
    })

    //  Canvas paint styles - keys are the picker labels, values the onPaint
    //  id handled by cavapaint.js. All drawn live from the same per-band
    //  signal: envelope, silhouette, bars and a dot-matrix.
    readonly property var cavaPaintMap: ({
        "mirror":  "mirror",   // symmetric envelope + translucent fill
        "area":    "area",     // filled silhouette (wave line + fill)
        "columns": "bars",     // vertical bars rising from the floor
        "matrix":  "dots"      // LED dot-matrix columns
    })

    //  true when the selected cavaStyle is a Canvas paint style (else ascii)
    readonly property bool cavaIsPaint: typeof cavaPaintMap[cavaStyle] !== "undefined"

    //  cavaBars — raw string; used when cavaStyle === ""
    property string cavaBars: "⣀⣄⣤⣦⣶⣷⣿"

    //  Paint renderer params (shared by every Canvas style)
    property int  cavaWaveThickness     // px - stroke width / dot size scale
    property bool cavaWaveSmooth  // smooth curves vs straight segments

    //  cavaEffectiveBars — resolved bars string (use this in Cava.qml)
    readonly property string cavaEffectiveBars: {
        if (cavaStyle !== "" && typeof cavaStyleMap[cavaStyle] !== "undefined")
            return cavaStyleMap[cavaStyle]
        return cavaBars
    }

    property bool cavaTransparentWhenInactive
    property real cavaActiveOpacity
    property real cavaInactiveOpacity
    // cavaAutoHide: when true and showCava is enabled, cava auto-hides when no
    //   media is detected and auto-shows when media starts playing.
    //   When showCava is false, auto-hide is disabled and cava stays hidden.
    property bool cavaAutoHide

    // ── Cava color ───────────────────────────────────────────────────────
    //  Single color: cavaGlyphColor
    //  Gradient (cavaGradientEnabled): cavaGradientStartColor → cavaGradientEndColor
    //
    //  Color mode ("matugen" | "custom") and selected variable name are stored
    //  here in Config so the live Theme bindings are active from bar startup —
    //  not waiting for the CC to open.  The computed color properties below
    //  re-evaluate automatically whenever Theme updates (wallpaper change).

    // Mode + selected variable for each color slot ("matugen" | "custom" | "pywal")
    property string cavaStartMode
    property string cavaEndMode
    property string cavaStartVar     // selected matugen variable
    property string cavaEndVar       // selected matugen variable
    property string cavaStartPywalVar      // selected pywal variable
    property string cavaEndPywalVar      // selected pywal variable
    property string cavaStartWallustVar     // selected wallust variable
    property string cavaEndWallustVar     // selected wallust variable

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
    property color _cavaGlyphCustomColor   // overwritten by CC custom pick

    property bool  cavaGradientEnabled

    property color cavaGradientStartColor: cavaStartMode === "matugen"
        ? _cavaThemeColor(cavaStartVar)
        : cavaStartMode === "pywal"
            ? _cavaPywalColor(cavaStartPywalVar)
            : cavaStartMode === "wallust"
                ? _wallustThemeColor(cavaStartWallustVar)
                : _cavaStartCustomColor
    property color _cavaStartCustomColor   // overwritten by CC custom pick

    property color cavaGradientEndColor: cavaEndMode === "matugen"
        ? _cavaThemeColor(cavaEndVar)
        : cavaEndMode === "pywal"
            ? _cavaPywalColor(cavaEndPywalVar)
            : cavaEndMode === "wallust"
                ? _wallustThemeColor(cavaEndWallustVar)
                : _cavaEndCustomColor
    property color _cavaEndCustomColor       // overwritten by CC custom pick

    // Fraction of glyph height at which start→end color splits (0.0–1.0, default 0.5)
    property real  cavaGradientSplit

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

    property real  launcherSearchWidth
    property int   launcherIconSize
    property int   launcherTextFontSize
    property int   launcherFixedTileWidth
    property int   launcherFixedTileHeight
    property int   launcherFrameWidth
    property int   launcherFrameHeight
    property int   launcherFrameWidthVert
    property int   launcherFrameHeightVert
    property int   launcherBorderRadius
    property int   launcherBorderWidth
    property int   launcherSearchRadius
    property int   launcherListRadius
    property int   launcherInnerBorderWidth
    property int   launcherInnerPadding

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
    property real  wsBgOpacity

    property color groupedBgColor:   Theme.cOnSecondary
    property real  groupedBgOpacity

    property color ungroupedBgColor:   Theme.cOnSecondary
    property real  ungroupedBgOpacity

    // Split from ungrouped — Clock & Date island / Weather & Battery islands
    property real  clockDateBgOpacity
    property real  weatherBatBgOpacity

    // Split from grouped — left app-group island / right app-group island
    property real  leftGroupBgOpacity
    property real  rightGroupBgOpacity

    property color trayBgColor:   Theme.cOnSecondary
    property real  trayBgOpacity

    property color startMenuBgColor:   Theme.cSurfaceTint
    property real  startMenuBgOpacity

    property color mediaBgColor:   Theme.cOnSecondary
    property real  mediaBgOpacity

    property color cavaBgColor:   Theme.cOnSecondary
    property real  cavaBgOpacity

    property color distroBgColor:   Theme.cOnSecondary
    property real  distroBgOpacity

    property color activeWindowBgColor:   Theme.cOnSecondary
    property real  activeWindowBgOpacity
    property int   activeWindowMinWidth   // px — kept even when title is empty

    // ═══════════════════════════════════════════════════════════════════════
    //  Module visibility
    // ═══════════════════════════════════════════════════════════════════════

    property bool showClock
    property bool showDate
    property bool showWorkspaces
    property bool showCava
    property bool showWeather
    property bool showBattery
    property bool showMediaPlayer
    property bool showIdleInhibitor
    property bool showUpdates
    property bool showPowerProfiles
    property bool showOverview
    property bool showNotifications
    property bool showWallpaper
    property bool showTray
    property bool showBluetooth
    property bool showWindow
    property bool showDistro

    // ═══════════════════════════════════════════════════════════════════════
    //  Behaviour / intervals
    // ═══════════════════════════════════════════════════════════════════════


    // ═══════════════════════════════════════════════════════════════════════
    //  Bar auto-hide  (source of truth for QS bar; also written to
    //  hyprcandy-bar.conf so the GJS dock process can read the same file)
    // ═══════════════════════════════════════════════════════════════════════
    property bool barAutoHide
    property int  barAutoHideDelay       // seconds
    property bool triLeftAutoHide
    property int  triLeftAutoHideDelay
    property bool triCenterAutoHide
    property int  triCenterAutoHideDelay
    property bool triRightAutoHide
    property int  triRightAutoHideDelay
    // Shell module strip auto-hide (separate from the full-bar auto-hide)
    // shellModuleAutoHide / shellModuleAutoHideDelay live above with the shell geometry props

    // ═══════════════════════════════════════════════════════════════════════
    //  Dock (qs-native dock window) — appearance + behaviour.
    //  These are now the single source of truth for the dock: the GJS dock's
    //  config.js @HCD sed/respawn plumbing is retired. Values persist in
    //  [qs-bar-config-v1] of ~/.config/hyprcandy/hyprcandy-bar.conf.
    // ═══════════════════════════════════════════════════════════════════════
    property bool   dockAutoHide
    property int    dockAutoHideDelay       // seconds
    property int    dockMargin       // px — screen-edge gap
    property int    dockIconSize      // px — app icon size
    property int    dockStartIconSize      // px - start badge glyph
    property int    dockTrashIconSize      // px - trash badge glyph
    property int    dockButtonSpacing       // px — gap between dock buttons
    property int    dockInnerPadding      // px — padding inside dock rect
    property int    dockPadding       // px — legacy extra padding
    property int    dockRadius      // px — default corner radius
    property int    dockTopLeftRadius
    property int    dockTopRightRadius
    property int    dockBottomLeftRadius
    property int    dockBottomRightRadius
    property int    dockBorderWidth       // px — dock rect border
    property real   dockBorderAlpha    // 0–1
    property string dockBorderColorVar  // matugen var, $ optional
    property string dockBackgroundStyle        // "glass" | "gradient"
    property string dockPosition         // bottom|left|right|top
    property string dockStartIcon               // glyph override (empty → 󰚾)
    property string dockLayer            // "top" | "overlay"
    property bool   dockReserveSpace            // exclusive zone on/off
    property bool   dockVisible             // shown / user-hidden (replaces legacy dock.state)
    // Resolved border color — accepts "on_secondary" or "$on_secondary".
    readonly property color dockBorderColor: _cavaThemeColor(
        dockBorderColorVar.startsWith("$") ? dockBorderColorVar : "$" + dockBorderColorVar)

    // ── Desktop icon layer ───────────────────────────────────────────────
    property int  desktopIconSize   // px — app icon size
    property int  desktopLabelSize   // pt — label font size
    property int  desktopLabelRadius   // px — label background corner radius
    property bool desktopVisible // show/hide desktop icon layer

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
    property int  wsCount      // persistent workspace slots (1–10)
    readonly property int  hoverDuration:   300    // ms — hover animation

    // ═══════════════════════════════════════════════════════════════════════
    //  Runtime paths
    // ═══════════════════════════════════════════════════════════════════════

    // StandardPaths returns a file:// URI — strip the scheme so the value is
    // usable as a plain path in Process argv (python3/sh receive it raw).
    readonly property string home:        StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")
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
