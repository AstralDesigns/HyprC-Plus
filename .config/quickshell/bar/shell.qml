//@ pragma UseQApplication
//@ pragma Env QT_QPA_PLATFORMTHEME=qt6ct
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QS_NO_RELOAD_POPUP=1

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // Sync settings after Config initializes
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
    FileView {
        id: cavaSizeWatch
        path: "/tmp/qs-cava-size"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const raw = text().trim()
            if (!raw) return
            const n = parseInt(raw, 10)
            if (isNaN(n) || n < 1 || n > 300) return
            if (n === Config.cavaWidth) return   // already at this width — skip
            Config.cavaWidth = n
            Config._settings.setValue("cavaWidth", n)
            Config._settings.sync()
            Quickshell.reload(false)
        }
    }

    // ── Optional popup overlays (loaded on demand) ─────────────────────────
    Loader { active: PowerMenuState.visible;    source: "PowerMenu.qml"     }
    Loader { active: PowerLauncherState.visible; source: "PowerLauncher.qml" }
    Loader { active: VolumePopupState.visible;   source: "VolumePopup.qml"   }
    Loader { active: NetworkPopupState.visible;  source: "NetworkPopup.qml"  }
    Loader { active: CalendarPopupState.visible; source: "CalendarPopup.qml" }
    Loader { active: TrayMenuState.visible;      source: "TrayMenuPopup.qml" }
    SysTrayPopup {}
    UpdatesPopup {}
    DesktopLayer {}
    Loader { active: ControlCenterState.visible;  source: "ControlCenterPopup.qml" }
    Loader { active: WeatherPopupState.visible;        source: "WeatherPopup.qml"        }
    Loader { active: SystemMonitorPopupState.visible;  source: "SystemMonitorPopup.qml"  }
    Loader { active: NotificationsState.historyVisible || NotificationsState.notifications.length > 0; source: "NotificationsPopup.qml" }
    Loader { active: StartMenuState.menuVisible;    source: "StartMenuPopup.qml"    }

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

        // Popup toggles
        function togglePowerMenu()  { PowerMenuState.toggle() }
        function toggleVolume()     { VolumePopupState.toggle() }
        function toggleNetwork()    { NetworkPopupState.toggle() }
        function toggleCalendar()   { CalendarPopupState.toggle() }

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

        // Notifications toggle (in-process, no separate qs config needed)
        function toggleNotifications() { NotificationsState.toggle() }
        function openNotifications()   { NotificationsState.open() }
        function closeNotifications()  { NotificationsState.close() }
        function dndToggle()           { NotificationsState.dndToggle() }
        function dndOn()               { NotificationsState.dndOn() }
        function dndOff()              { NotificationsState.dndOff() }

        // Start menu toggle (in-process)
        function toggleStartMenu() { StartMenuState.toggle() }
        function openStartMenu()   { StartMenuState.open() }
        function closeStartMenu()  { StartMenuState.close() }
    }
}
