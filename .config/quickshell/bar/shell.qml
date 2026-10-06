//@ pragma UseQApplication
//@ pragma Env QT_QPA_PLATFORMTHEME=qt6ct
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QS_NO_RELOAD_POPUP=1

// ── WebEngine GPU / hardware-acceleration policy ───────────────────────────
// Ported from the GJS launcher's hybrid-graphics handling, reworked for
// Chromium/QtWebEngine. quickshell qputenv()s these Env pragmas at process
// start — BEFORE QtWebEngine spawns its GPU/WebProcess children — so the
// children inherit them. This is the launcher's own concern, not the
// compositor autostart's (hyprviz.lua), which is why it lives here.
//
// GL backend: NATIVE OpenGL (user-chosen 2026-10, verified rendering fine).
// We previously PINNED ANGLE-on-GL (--use-gl=angle --use-angle=gl) to dodge an
// ANGLE-on-Vulkan DMA-BUF failure (eglCreateImage 0x3009 -> ProduceSkia failed
// -> "RasterDecoderImpl: Context lost" -> blank pages) on this Ivy Bridge +
// AMD-OLAND hybrid. Those pins are now REMOVED to skip ANGLE's translation
// overhead and let Chromium use desktop GL directly.
//   !! If blank pages / context-lost ever come back, re-add `--use-gl=angle
//   --use-angle=gl` to the flags line below -- that is the known-good fix. !!
//
// QSG_RHI_BACKEND controls Qt's OWN scene graph (the QML layer), NOT the
// Chromium compositor; the web content's GL path is governed only by the
// --use-gl/--use-angle flags (absent here = Chromium's own default). Kept at
// opengl (no spaces -- "KEY = val" would set a malformed var and do nothing).
//@ pragma Env QSG_RHI_BACKEND=opengl
//
// Flags: gpu-rasterization + ignore-gpu-blocklist keep the hardware path;
// zero-copy shares GPU buffers (the very DMA-BUF path that failed under ANGLE-
// on-Vulkan -- benign on native GL, but the FIRST thing to drop if blank pages
// return); disable-background-timer-throttling + disable-renderer-backgrounding
// + disable-backgrounding-occluded-windows keep the YouTube ad-skip interval
// and the agent hot while backgrounded, and stop an UNMAPPED launcher window
// (hidden while media plays) from being treated as occluded -- that path
// starves segment requests and the audio cuts out once the buffer drains
// (costs a little idle CPU); no-pings drops link beacon tracking;
// renderer-process-limit=2 caps Chromium renderer processes (the main per-tab
// RAM lever). WebGPU is left ENABLED: the old "Vulkan probe" log spam it caused
// came from the ANGLE-on-Vulkan path, which we no longer use (native GL), so
// enabling it is now silent. The proxy flag (added/removed by `hcproxy
// enable|disable`, never by hand -- those functions grep this file for the
// exact Chromium flag spelling, so do NOT quote that literal here) routes
// websearch through the opt-in hcproxy
// (its lifecycle is tied to the websearch toggle in LauncherWindow.qml
// -- see proxyOptIn; run `hcproxy disable` to strip the flag and stop the
// launcher managing it).
//@ pragma Env QTWEBENGINE_CHROMIUM_FLAGS=--enable-gpu-rasterization --ignore-gpu-blocklist --disable-background-timer-throttling --disable-renderer-backgrounding --disable-backgrounding-occluded-windows --no-pings --renderer-process-limit=2 --proxy-server=http://127.0.0.1:8888 --proxy-server=http://127.0.0.1:8888 --proxy-server=http://127.0.0.1:8888
// (If CDP forensics are ever needed again: re-add
//  //@ pragma Env QTWEBENGINE_REMOTE_DEBUGGING=9223 and use bar/scripts/webtest/.)

// ── Qt logging filter (keep errors, drop benign chatter) ────────────────────
// qt.svg: Humanity icon theme probing a printer.svg that isn't installed.
// qt.qpa.services: duplicate portal app-ID registration under our Wayland setup.
// scene: the launcher-tab FileView read (a transient /run IPC file that is
//   unlinked right after each read, so "File does not exist" is expected) and
//   the compositor's occasional null-texture debug. None are actionable.
// *.debug=false drops DEBUG lines (e.g. "Compositor returned null texture").
// NOTE: the two "MESA-INTEL: Ivy Bridge Vulkan support is incomplete" lines come
// straight from Mesa to stderr (not a Qt category) so QT_LOGGING_RULES cannot
// filter them; they are harmless and unrelated to the GL compositing path.
//@ pragma Env QT_LOGGING_RULES=*.debug=false;qt.svg.enabled=false;qt.qpa.services.enabled=false;scene.enabled=false

// VA-API video-decode driver. This Ivy Bridge iGPU is only driven by the
// classic "i965" backend; without a hint Chromium/VA-API probes the newer
// iHD driver first, which fails to init on Gen7 and spams
// "libva error: /usr/lib/dri/iHD_drv_video.so init failed". Pinning i965
// (confirmed present via vainfo) selects the working driver and silences it.
//@ pragma Env LIBVA_DRIVER_NAME=i965

// ── glibc heap-arena cap (RSS / thread-count trim) ──────────────────────────
// A long-lived, many-threaded process gets one malloc arena per competing thread
// up to 8 * CPU-cores; each arena reserves its own heap, so idle arenas show up
// as resident memory and as kernel-side per-arena bookkeeping. Capping arenas at
// 4 makes glibc funnel allocations onto fewer heaps that are reused instead of
// growing, lowering steady-state RSS of this process (Qt/QML + quickshell; the
// Chromium child processes manage their own allocators). Pure allocator tuning --
// no functional or rendering change.
//@ pragma Env MALLOC_ARENA_MAX=4

pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Sync settings after Config initializes, and seed the qt6ct icon theme
    // so the watcher below never sees a false "first change" on startup.
    Component.onCompleted: {
        if (Config._settings) Config._settings.sync()
    }

    // ── Cava hot-reload via /tmp/qs-cava-size ─────────────────────────────
    //  Write a new integer bar-count to this file to hot-reload cava at the
    //  new width without a manual restart.  Example:
    //      echo "30" > /tmp/qs-cava-size
    //  Flow: file changes → reload() re-reads it → onLoaded parses the int →
    //  saves to Settings → Quickshell.reload(false) restarts QML + cava fresh.
    //  The  n === Config.cavaWidth  guard prevents an infinite reload loop
    //  (after reload the file still holds the same value but Config is already
    //  initialised from the persisted setting, so the guard exits early).
    Process {
        id: cavaSizeWatch
        command: ["bash", "-c",
            "F=/tmp/qs-cava-size; " +
            "LOCK=/tmp/qs-cava-size.lock; " +
            "exec 200>\"$LOCK\"; " +
            "if ! flock -n 200; then exit 0; fi; " +
            "while true; do " +
            "  if [ -f \"$F\" ]; then " +
            "    inotifywait -q -e modify,close_write \"$F\" 2>/dev/null || sleep 1; " +
            "    [ -f \"$F\" ] && cat \"$F\"; " +
            "  else " +
            "    inotifywait -q -e create -m /tmp --include 'qs-cava-size' 2>/dev/null || sleep 2; " +
            "  fi; " +
            "done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const raw = line.trim()
                if (!raw) return
                const n = parseInt(raw, 10)
                if (isNaN(n) || n < 1 || n > 300) return
                if (n === Config.cavaWidth) return
                Config.cavaWidth = n
                Config._settings.setValue("cavaWidth", n)
                Config._settings.sync()
                Quickshell.reload(false)
            }
        }
        Component.onCompleted: running = true
    }

    // ── License gate: auto-open CC on activation tab when not activated ──────
    // Short delay lets the bar fully render before the CC appears, so the
    // user sees the bar briefly before the activation prompt slides in.
    Timer {
        id: _licStartupTimer
        interval: 800
        repeat: false
        running: !LicenseState.activated
        onTriggered: {
            if (!LicenseState.activated) ControlCenterState.toggle()
        }
    }

    // ── Optional popup overlays (loaded on demand) ─────────────────────────
    Loader { active: LicenseState.activated && PowerMenuState.visible;    source: "PowerMenu.qml"     }
    Loader { active: LicenseState.activated && PowerLauncherState.visible; source: "PowerLauncher.qml" }
    Loader { active: LicenseState.activated && VolumePopupState.visible;   source: "VolumePopup.qml"   }
    Loader { active: LicenseState.activated && NetworkPopupState.visible;  source: "NetworkPopup.qml"  }
    Loader { active: LicenseState.activated && CalendarPopupState.visible; source: "CalendarPopup.qml" }
    Loader { active: LicenseState.activated && (ClockPopupState.visible || ClockPopupState.widgetVisible); source: "ClockPopup.qml" }
    Loader { active: LicenseState.activated && (MediaPlayerPopupState.visible || MediaPlayerPopupState.widgetVisible); source: "MediaPlayerPopup.qml" }
    Loader { active: LicenseState.activated && TrayMenuState.visible;      source: "TrayMenuPopup.qml" }
    // Wrapped in a Loader so wallpaper changes can fully destroy+recreate
    // it, forcing Qt to re-apply the new QT color palette for native menus.
    property bool _sysTrayActive: true
    Loader {
        active: root._sysTrayActive
        source: "SysTrayPopup.qml"
    }
    UpdatesPopup {}

    // ── qt6ct icon_theme watcher — full DesktopLayer kill+restart ──────────
    // Only restarts when icon_theme value actually changes, not on every
    // qt6ct.conf write (e.g. wallpaper/color changes also touch this file).
    property bool   _desktopActive:   true
    property string _lastIconTheme:   ""

    FileView {
        id: qt6ctWatch
        path: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "") + "/.config/qt6ct/qt6ct.conf"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const match = text().match(/^icon_theme\s*=\s*(.+)$/m)
            const theme = match ? match[1].trim() : ""
            if (theme === "" || theme === root._lastIconTheme) return
            root._lastIconTheme = theme
            _desktopHide.restart()
        }
        Component.onCompleted: {
            // Seed _lastIconTheme at startup so the first read never triggers a restart
            reload()
        }
    }

    Timer {
        id: _desktopHide
        interval: 3000
        repeat:   false
        onTriggered: {
            root._desktopActive = false
            _desktopRestartTimer.restart()
        }
    }
    Timer {
        id: _desktopRestartTimer
        interval: 300
        repeat:   false
        onTriggered: root._desktopActive = true
    }

    // ── Wallpaper color watcher — reload SysTray for QT native menu colors ── 
    // pywal writes ~/.cache/wal/colors-hyprland.conf on every wallpaper change.
    // Toggling _sysTrayActive destroys and recreates SysTrayPopup so Qt picks
    // up the new palette for its native right-click popup menus.
    FileView {
        path: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")
              + "/.cache/wal/colors-hyprland.conf"
        watchChanges: true
        onFileChanged: {
            root._sysTrayActive = false
            _sysTrayRestartTimer.restart()
        }
    }
    Timer {
        id: _sysTrayRestartTimer
        interval: 500
        repeat:   false
        onTriggered: root._sysTrayActive = true
    }

    // Wrapped in a Loader so _desktopActive can fully destroy+recreate it
    // on icon_theme changes. DesktopLayer internally gates PanelWindow.visible
    // on Config.desktopVisible, so the "Show Icons" toggle still works fine.
    Loader {
        active: root._desktopActive
        source: "DesktopLayer.qml"
    }
    // ── Phase-0 QtWebEngine layer-surface spike (env-gated, dormant by default) ──
    Loader { active: Quickshell.env("HYPRCANDY_QS_WEBENGINE_SMOKE") === "1"; source: "WebEngineTest.qml" }

    // ── qs dock (GJS hyprcandydock port) — one instance per screen ────────
    // Shares _desktopActive with DesktopLayer: destroyed + recreated whenever
    // qt6ct icon_theme changes, so Quickshell.iconPath re-resolves against the
    // new theme (otherwise the dock keeps stale paths from boot).
    Loader {
        active: DockState.visible && root._desktopActive
        sourceComponent: Variants {
            model: Quickshell.screens
            DockWindow {
                required property var modelData
                screen: modelData
            }
        }
    }

    // ── qs app launcher (GJS app-launcher.js port) ─────────────────────
    // Persistent across hide/show: gated on _desktopActive (not on launcher
    // visibility), so keeping the window — and its single shared WebEngineView —
    // alive means the web-search and agent pages keep running instead of
    // reloading (the agent app never re-boots and resets its provider/model, and
    // open tabs stay warm). Backend warm-up is deferred to the window's first
    // show (see LauncherWindow), so an always-loaded window never starts
    // docker/uvicorn while the launcher is shut.
    // Sharing _desktopActive with DesktopLayer/DockWindow means an icon_theme
    // change (qt6ct watcher) destroys + recreates the launcher too, so its app
    // icons re-resolve via Quickshell.iconPath against the new theme. That reload
    // is rare and, like the dock, briefly reboots the web view — acceptable.
    Loader { id: launcherLoader; active: root._desktopActive; source: "LauncherWindow.qml" }

    Loader { active: ControlCenterState.visible;  source: "ControlCenterPopup.qml" }
    Loader { active: LicenseState.activated && (WeatherPopupState.visible || WeatherPopupState.widgetVisible); source: "WeatherPopup.qml" }
    Loader { active: LicenseState.activated && (SystemMonitorPopupState.visible || SystemMonitorPopupState.widgetVisible); source: "SystemMonitorPopup.qml" }
    Loader { active: LicenseState.activated && (NotificationsState.historyVisible || NotificationsState.notifications.length > 0); source: "NotificationsPopup.qml" }
    Loader { active: StartMenuState.menuVisible;    source: "StartMenuPopup.qml"    }
    Loader { active: LicenseState.activated && ScreenshotPopupState.visible; source: "ScreenshotPopup.qml" }
    Loader { active: LicenseState.activated && RecorderPopupState.visible; source: "RecorderPopup.qml" }
    Loader { active: LicenseState.activated && CaptureMenuState.visible; source: "CaptureMenuPopup.qml" }
    Loader { active: WorkspacesPopupState.visible; source: "WorkspacesPopup.qml" }
    Loader { active: WorkspacesPopupState.tileTooltipVisible; source: "WorkspaceTileTooltip.qml" }

    // ── Idle-inhibitor anchor — always mapped so the Wayland protocol object
    //    survives bar autohide (bar.visible = false unmaps the bar surface).
    InhibitorAnchor {}

    // ── Smooth pre-lock blur transition overlay ─────────────────────────────
    LockTransitionOverlay {}


    // ── One bar instance per monitor ────────────────────────────────────────
    Variants {
        id: barVariants
        model: Quickshell.screens
        Bar {
            required property var modelData
            screen: modelData
        }
    }

    // ── IPC handlers (callable via: qs ipc call bar <fn>) ──────────────────
    IpcHandler {
        target: "bar"

        // Popup toggles — all gated on activation
        function togglePowerMenu()      { if (LicenseState.activated) PowerMenuState.toggle() }
        function toggleVolume()         { if (LicenseState.activated) VolumePopupState.toggle() }
        function toggleNetwork()        { if (LicenseState.activated) NetworkPopupState.toggle() }
        function toggleCalendar()       { if (LicenseState.activated) CalendarPopupState.toggle() }
        function toggleSystemMonitor()  { if (LicenseState.activated) SystemMonitorPopupState.toggle() }
        function toggleWeatherPopup()   { if (LicenseState.activated) WeatherPopupState.toggle() }

        // Cycle bar position: top → right → bottom → left → top
        // Affects all bar instances on the focused monitor
        function cyclePosition() {
            const order = ["top", "right", "bottom", "left"]
            const cur   = Config.barPosition
            const next  = order[(order.indexOf(cur) + 1) % order.length]
            Config.barPosition = next
        }

        // Jump to a specific position
        function setPosition(pos: string) { Config.barPosition = pos }

        // Toggle bar mode: "bar" (blur) ↔ "island" (0.4 solid)
        function toggleMode() {
            Config.barMode = Config.barMode === "bar" ? "island" : "bar"
        }
        function setMode(m: string) { Config.barMode = m }

        // Toggle visibility on focused monitor
        function toggleVisibility() {
            for (let i = 0; i < barVariants.instances.length; i++) {
                const b = barVariants.instances[i]
                if (Hyprland.monitorFor(b.screen)?.id === Hyprland.focusedMonitor?.id)
                    b.visible = !b.visible
            }
        }

        // Workspace icon mode: "number" | "icon"
        function setWsIconMode(m: string) { Config.wsIconMode = m }
        function cycleWsIconMode() {
            const modes = ["number", "icon"]
            Config.wsIconMode = modes[(modes.indexOf(Config.wsIconMode) + 1) % modes.length]
        }

        // Control-center glyph
        function setCcGlyph(g: string) { Config.ccGlyph = g }

        // Module visibility toggles
        function toggleCava()          { Config.showCava          = !Config.showCava }
        function toggleWeather()       { Config.showWeather       = !Config.showWeather }
        function toggleBattery()       { Config.showBattery       = !Config.showBattery }
        function toggleMediaPlayer()   { Config.showMediaPlayer   = !Config.showMediaPlayer }
        function toggleIdleInhibitor() { Config.showIdleInhibitor = !Config.showIdleInhibitor }
        function toggleTray()          { Config.showTray          = !Config.showTray }
        function toggleWindow()        { Config.showWindow        = !Config.showWindow }

        // Cava hot-reload — equivalent to writing /tmp/qs-cava-size but callable
        // directly via IPC:  qs ipc call bar reloadCava
        // Useful after manually updating Config.cavaWidth from another tool.
        function reloadCava() { Quickshell.reload(false) }

        // Control center toggle
        function refreshDesktop() { DesktopPinnedState.forceRefresh() }
        function toggleControlCenter() { ControlCenterState.toggle() }

        // Notifications toggle — gated on activation
        function toggleNotifications() { if (LicenseState.activated) NotificationsState.toggle() }
        function openNotifications()   { if (LicenseState.activated) NotificationsState.open() }
        function closeNotifications()  { if (LicenseState.activated) NotificationsState.close() }
        function dndToggle()           { if (LicenseState.activated) NotificationsState.dndToggle() }
        function dndOn()               { if (LicenseState.activated) NotificationsState.dndOn() }
        function dndOff()              { if (LicenseState.activated) NotificationsState.dndOff() }

        // Start menu — ungated so network/bluetooth always accessible pre-activation
        function toggleStartMenu() { StartMenuState.toggle() }
        function openStartMenu()   { StartMenuState.open() }
        function closeStartMenu()  { StartMenuState.close() }
        // Capture menu (Screenshot / Recorder chooser)
        function toggleCaptureMenu() { if (LicenseState.activated) CaptureMenuState.toggle() }
        function toggleCapture()     { if (LicenseState.activated) CaptureMenuState.toggle() }
        // Screenshot
        function toggleScreenshot() { if (LicenseState.activated) ScreenshotPopupState.toggle() }
        // Recorder
        function toggleRecorder()   { if (LicenseState.activated) (RecorderPopupState.isRecording ? RecorderPopupState.stopRecording() : RecorderPopupState.toggle()) }

        // ── qs dock + launcher (GJS port) ─────────────────────────────────
        function toggleDock()          { DockState.toggle() }
        function openDock()            { DockState.open() }
        function closeDock()           { DockState.close() }
        function setDockPosition(pos: string) { DockState.setPosition(pos) }
        function cycleDockPosition()   { DockState.cyclePosition() }
        function toggleLauncher()      { if (LicenseState.activated) HCCLauncherState.toggle() }
        // No tab arg -> toggle (hyprviz.lua SUPER+A); with a tab -> open it.
        function openLauncher(tab: string) { if (!LicenseState.activated) return; tab ? HCCLauncherState.open(tab) : HCCLauncherState.toggle() }
        function closeLauncher()       { HCCLauncherState.close() }
    }
}
