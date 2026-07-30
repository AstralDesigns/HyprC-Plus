//@ pragma UseQApplication
//@ pragma Env QT_QPA_PLATFORMTHEME=qt6ct
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QS_NO_RELOAD_POPUP=1

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
        path: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.config/qt6ct/qt6ct.conf"
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
        path: StandardPaths.writableLocation(StandardPaths.HomeLocation)
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
    Loader { active: ControlCenterState.visible;  source: "ControlCenterPopup.qml" }
    Loader { active: LicenseState.activated && (WeatherPopupState.visible || WeatherPopupState.widgetVisible); source: "WeatherPopup.qml" }
    Loader { active: LicenseState.activated && (SystemMonitorPopupState.visible || SystemMonitorPopupState.widgetVisible); source: "SystemMonitorPopup.qml" }
    Loader { active: LicenseState.activated && (NotificationsState.historyVisible || NotificationsState.notifications.length > 0); source: "NotificationsPopup.qml" }
    Loader { active: StartMenuState.menuVisible;    source: "StartMenuPopup.qml"    }
    Loader { active: LicenseState.activated && ScreenshotPopupState.visible; source: "ScreenshotPopup.qml" }

    // ── Idle-inhibitor anchor — always mapped so the Wayland protocol object
    //    survives bar autohide (bar.visible = false unmaps the bar surface).
    InhibitorAnchor {}


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
        function togglePowerMenu()  { if (LicenseState.activated) PowerMenuState.toggle() }
        function toggleVolume()     { if (LicenseState.activated) VolumePopupState.toggle() }
        function toggleNetwork()    { if (LicenseState.activated) NetworkPopupState.toggle() }
        function toggleCalendar()   { if (LicenseState.activated) CalendarPopupState.toggle() }

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
        // Screenshot
        function toggleScreenshot() { if (LicenseState.activated) ScreenshotPopupState.toggle() }
    }
}
