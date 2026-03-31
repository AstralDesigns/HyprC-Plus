//@ pragma UseQApplication
//@ pragma Env QT_QPA_PLATFORMTHEME=qt6ct
//@ pragma Env QT_QUICK_CONTROLS_STYLE=Basic
//@ pragma Env QS_NO_RELOAD_POPUP=1

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

ShellRoot {
    id: root

    // ── Optional popup overlays (loaded on demand) ─────────────────────────
    Loader { active: PowerMenuState.visible;    source: "PowerMenu.qml"     }
    Loader { active: PowerLauncherState.visible; source: "PowerLauncher.qml" }
    Loader { active: VolumePopupState.visible;   source: "VolumePopup.qml"   }
    Loader { active: NetworkPopupState.visible;  source: "NetworkPopup.qml"  }
    Loader { active: CalendarPopupState.visible; source: "CalendarPopup.qml" }
    Loader { active: TrayMenuState.visible;      source: "TrayMenuPopup.qml" }
    Loader { active: UpdatesPopupState.visible;  source: "UpdatesPopup.qml" }
    Loader { active: ControlCenterState.visible;  source: "ControlCenterPopup.qml" }

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

        // Workspace icon mode: "dot" | "number" | "custom"
        function setWsIconMode(m: string) { Config.wsIconMode = m }
        function cycleWsIconMode() {
            const modes = ["dot", "number", "custom"]
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

        // Control center toggle
        function toggleControlCenter() { ControlCenterState.toggle() }
    }
}
