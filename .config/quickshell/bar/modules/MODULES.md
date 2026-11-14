# HyprCandy Quickshell Bar Modules (`modules/`)

This document details the architecture, design, behavior, and implementations of the Quickshell modules located in:
`~/.config/quickshell/bar/modules/`

Each module acts as a self-contained, modular status bar widget imported by `BarWindow.qml` or `VerticalBarWindow.qml`. Modules interact with global states (`Config.qml`, `Theme.qml`, `BarTipState.qml`), Quickshell native APIs (`Quickshell.Hyprland`, `Quickshell.Io`, `Quickshell.Services.SystemTray`), and specialized singleton popup states (`*PopupState.qml`).

---

## Table of Modules

1. [ActiveWindow.qml](#1-activewindowqml)
2. [Battery.qml](#2-batteryqml)
3. [Cava.qml](#3-cavaqml)
4. [Clock.qml](#4-clockqml)
5. [ControlCenter.qml](#5-controlcenterqml)
6. [CpuUsage.qml](#6-cpuusageqml)
7. [DateDisplay.qml](#7-datedisplayqml)
8. [GpuUsage.qml](#8-gpuusageqml)
9. [IdleInhibitor.qml](#9-idleinhibitorqml)
10. [MediaPlayer.qml](#10-mediaplayerqml)
11. [NetworkInfo.qml](#11-networkinfoqml)
12. [Notifications.qml](#12-notificationsqml)
13. [OverviewBtn.qml](#13-overviewbtnqml)
14. [PowerButton.qml](#14-powerbuttonqml)
15. [PowerProfiles.qml](#15-powerprofilesqml)
16. [RamUsage.qml](#16-ramusageqml)
17. [StartMenu.qml](#17-startmenuqml)
18. [SystemTray.qml](#18-systemtrayqml)
19. [Updates.qml](#19-updatesqml)
20. [Volume.qml](#20-volumeqml)
21. [WallpaperBtn.qml](#21-wallpaperbtnqml)
22. [Weather.qml](#22-weatherqml)
23. [Workspaces.qml](#23-workspacesqml)

---

### 1. ActiveWindow.qml
- **Purpose:** Displays the icon and truncated title of the currently focused Hyprland window.
- **Hyprland Integration:** Listens to `Hyprland.focusedWindow` (specifically `title` and `className` / `initialClass`).
- **Icon Resolution:** Invokes an asynchronous Python helper script (`resolve_app_icon.py`) with fallback icon resolution if native XDG icon lookups fail.
- **Interactions:**
  - **Left Click:** Launches or toggles the application launcher dashboard (`LauncherWindow`).
  - **Right Click:** Launches a desktop application switcher or overview dispatch.
  - **Hover:** Displays a tooltip (`BarTipState`) with the full window title.

---

### 2. Battery.qml
- **Purpose:** Monitors battery level, charging/discharging state, and AC adapter connectivity.
- **Hardware Sensing:** Reads directly from `/sys/class/power_supply/` (or via `upower`). Dynamically hides itself if no battery device is found (e.g., on desktop machines).
- **Visuals:** Shows an animated or state-based Nerd Font icon corresponding to remaining charge percentage (10% increments) and charging state (`󰂄`, `󰁹`, etc.).
- **Interactions:**
  - **Left Click:** Toggles `SystemMonitorPopupState` (or opens system power management settings).
  - **Right Click:** Toggles the persistent system monitor widget on the desktop.
  - **Hover:** Displays detailed remaining time and percentage in `BarTipState`.

---

### 3. Cava.qml
- **Purpose:** Real-time audio spectrum visualizer embedded directly into the status bar.
- **Backend:** Spawns a background `cava` process configured to write raw or character-based bar amplitudes to stdout (`Quickshell.Io.Process`).
- **Rendering:** Uses an HTML5-style QML `Canvas` to render smooth vertical audio spectrum bars with rounded corners, colored dynamically using `Theme.cPrimary` or gradient fills.
- **Interactions:**
  - **Left Click:** Launches or toggles `MediaPlayerPopupState`.
  - **Scroll Wheel:** Adjusts visual sensitivity or master volume.

---

### 4. Clock.qml
- **Purpose:** Digital time display module with customizable formats and time zones.
- **Time Formatting:** Uses a continuous 1-second `Timer` formatted with `Qt.formatDateTime` (supporting 12-hour AM/PM or 24-hour modes per `Config.clock24h`).
- **Interactions:**
  - **Left Click:** Toggles the calendar popup (`CalendarPopupState`).
  - **Right Click:** Toggles the desktop calendar widget.
  - **Hover:** Displays full date, week number, and time zone information.

---

### 5. ControlCenter.qml
- **Purpose:** Action button to toggle the HyprCandy Quick Settings / Control Center panel.
- **Visuals:** Material / Nerd Font settings toggle icon (`󰒓` or `󰮄`) styled with smooth hover animations.
- **Interactions:**
  - **Left Click:** Calls `ControlCenterPopupState.toggle()` to reveal quick toggles (Wi-Fi, Bluetooth, Night Light, DND, volume sliders).

---

### 6. CpuUsage.qml
- **Purpose:** Real-time processor utilization monitor.
- **Data Source:** Reads `/proc/stat` asynchronously via `Quickshell.Io` and calculates the delta between total and idle jiffies.
- **Display Options:** Shows numerical percentage, sparkline graph, or color-coded alert state when usage exceeds configurable warning thresholds.
- **Interactions:**
  - **Left Click:** Opens `ProcessMonitor` or launches external system monitor (`btop` / `htop`).
  - **Right Click:** Toggles desktop resource monitor widget.

---

### 7. DateDisplay.qml
- **Purpose:** Separate date module (frequently placed beside `Clock.qml`).
- **Visuals:** Displays localized date string (e.g., "Tue, Oct 24") using `Config.dateFormat`.
- **Interactions:**
  - **Left Click:** Toggles `CalendarPopupState`.
  - **Right Click:** Toggles the desktop calendar overlay widget.

---

### 8. GpuUsage.qml
- **Purpose:** Monitors discrete/integrated GPU utilization and temperature.
- **Backend:** Detects and queries NVIDIA (`nvidia-smi`), AMD (`rocm-smi` / `/sys/class/drm/card*/device/gpu_busy_percent`), or Intel graphics drivers. Hides automatically if unsupported.
- **Interactions:**
  - **Left Click:** Opens the GPU stats tab in the system monitor.
  - **Hover:** Shows GPU temperature, VRAM usage, and fan speed.

---

### 9. IdleInhibitor.qml
- **Purpose:** Toggles Wayland idle inhibitor / caffeinate state to prevent screen dimming, lockscreen, or sleep during presentations and media playback.
- **Implementation:** Executes `wayland-idle-inhibitor` or toggles `hypridle` process / lock inhibition via shell script.
- **Visuals:** Eye/cup icon (`󰈈` active vs. `󰈉` inactive) with accent highlight when active.

---

### 10. MediaPlayer.qml
- **Purpose:** Status bar media controller and current track metadata display.
- **MPRIS Integration:** Directly binds to Quickshell's MPRIS service or `playerctl` metadata (artist, title, playback status).
- **Controls & Visuals:** Displays play/pause icon, scrolling track title marquee, and optional previous/next buttons.
- **Interactions:**
  - **Left Click:** Toggles `MediaPlayerPopupState` (extended player with album art and seek bar).
  - **Middle Click:** Play / Pause toggle.
  - **Scroll Wheel:** Next / Previous track or player volume adjust.

---

### 11. NetworkInfo.qml
- **Purpose:** Connectivity indicator for Wi-Fi and wired Ethernet networks.
- **Backend:** Monitors NetworkManager (`nmcli`) or reads `/sys/class/net/` interfaces for link status and signal strength.
- **Visuals:** Contextual icons representing Ethernet (`󰈀`), Wi-Fi signal tiers (`󰤯`, `󰤟`, `󰤢`, `󰤥`, `󰤨`), or disconnected state (`󰤮`).
- **Interactions:**
  - **Left Click:** Toggles `NetworkPopupState` (Wi-Fi SSID scanner and connection manager).
  - **Hover:** Displays current SSID, IP address, and bitrate.

---

### 12. Notifications.qml
- **Purpose:** Notification center bell module with unread badge counter and Do-Not-Disturb (DND) status.
- **Backend:** Connected to `NotificationPopupState` and daemon notification count.
- **Visuals:** Bell icon (`󰂚` / `󰂛` for DND) accompanied by a numerical pill badge when pending notifications exist.
- **Interactions:**
  - **Left Click:** Toggles `NotificationPopupState` panel.
  - **Right Click:** Toggles DND mode.

---

### 13. OverviewBtn.qml
- **Purpose:** Quick launcher trigger for the Hyprland workspace overview / mission control view.
- **Dispatch:** Dispatches Hyprland overview shortcut or runs the HyprCandy window overview script.
- **Visuals:** Grid/workspace icon (`󰕰` or `󰄬`).

---

### 14. PowerButton.qml
- **Purpose:** System session management trigger.
- **Visuals:** Standby / power icon (`󰐥`).
- **Interactions:**
  - **Left Click:** Toggles `PowerPopupState` (Sleep, Hibernate, Reboot, Shutdown, Lock, Logout options).
  - **Right Click:** Immediate lock screen toggle.

---

### 15. PowerProfiles.qml
- **Purpose:** System performance profile switcher (Power Saver, Balanced, Performance).
- **Backend:** Interacts with `power-profiles-daemon` via D-Bus / `powerprofilesctl`.
- **Interactions:**
  - **Left Click:** Cycles through available profiles (`power-saver` -> `balanced` -> `performance`).
  - **Hover:** Displays current active profile name.

---

### 16. RamUsage.qml
- **Purpose:** Real-time RAM and Swap memory utilization indicator.
- **Data Source:** Parses `/proc/meminfo` periodically via `Quickshell.Io.Process`.
- **Visuals:** Memory chip icon (`󰍛`) with percentage or gigabytes used/total.
- **Interactions:**
  - **Left Click:** Toggles `SystemMonitorPopupState`.
  - **Right Click:** Toggles desktop RAM widget.

---

### 17. StartMenu.qml
- **Purpose:** The primary desktop start/launcher button (Distro / Candy icon).
- **Visuals:** Configurable distro logo or candy icon (`󰣇`, ``, etc.) with customizable coloring.
- **Interactions:**
  - **Left Click:** Toggles `LauncherWindow.qml` (Application Launcher, AI Agent, Tools).
  - **Right Click:** Launches Quick Settings / Control Center.

---

### 18. SystemTray.qml
- **Purpose:** StatusNotifierItem (SNI) system tray container for background applications.
- **Implementation:** Leverages `Quickshell.Services.SystemTray` to host tray icons (Discord, Steam, OBS, etc.).
- **Interactions:**
  - **Left Click:** Activates application window.
  - **Right Click:** Spawns native D-Bus context menu via `SystemTrayItem.menu`.

---

### 19. Updates.qml
- **Purpose:** Package update indicator for Arch Linux / Pacman / AUR (`checkupdates`, `paru`, `yay`).
- **Data Source:** Background polling process checking for pending repository and AUR updates.
- **Visuals:** Package/download icon (`󰏓`) with count badge. Hidden when no updates are pending.
- **Interactions:**
  - **Left Click:** Launches terminal running system update script (`hyprcandy-update` or `paru -Syu`).
  - **Right Click:** Re-checks for pending updates immediately.

---

### 20. Volume.qml
- **Purpose:** Audio output and input level controller.
- **Backend:** Communicates with PipeWire / WirePlumber (`wpctl`) or PulseAudio (`pactl`).
- **Visuals:** Dynamic volume speaker icons (`󰕿`, `󰖀`, `󰕾`, `󰝟` muted).
- **Interactions:**
  - **Left Click:** Toggles `VolumePopupState` (detailed sink/source selector and application mixer).
  - **Middle Click:** Toggles mute/unmute.
  - **Scroll Wheel:** Increments or decrements volume by configured step (e.g., 2% or 5%).

---

### 21. WallpaperBtn.qml
- **Purpose:** Quick wallpaper selector and Pywal theme regenerator button.
- **Interactions:**
  - **Left Click:** Opens the wallpaper picker / gallery popup.
  - **Right Click:** Cycles randomly to the next wallpaper in `~/Pictures/Wallpapers/` and triggers color scheme re-generation.

---

### 22. Weather.qml
- **Purpose:** Live weather conditions and temperature readout.
- **Backend:** Queries `wttr.in` or OpenWeather API in JSON format via `WeatherPopupState`.
- **Visuals:** Weather Nerd Font glyph (sun, rain, snow, clouds) alongside current temperature.
- **Interactions:**
  - **Left Click:** Toggles `WeatherPopupState` (multi-day forecast, humidity, wind speed, UV index).
  - **Right Click:** Toggles desktop weather widget.
  - **Scroll Wheel:** Toggles between Celsius (°C) and Fahrenheit (°F).

---

### 23. Workspaces.qml
- **Purpose:** Hyprland workspace switcher, monitor tracker, and window status visualizer.
- **Hyprland Integration:** Directly binds to `Quickshell.Hyprland` workspaces model. Tracks active workspace, occupied workspaces, urgent flags, and special workspaces (scratchpad).
- **Display Modes:** Supports multiple presentation styles configured in `Config.qml`:
  - Number mode (`1`, `2`, `3`...)
  - Dot mode (active dot, persistent occupied dots, empty dots)
  - Custom icon mode (application-type icons based on workspace index)
- **Orientations:** Supports both horizontal (top/bottom bars) and vertical (sidebar dock) layouts.
- **Interactions:**
  - **Left Click:** Dispatches `hyprctl dispatch workspace <id>` to switch to target workspace.
  - **Hover:** Triggers workspace preview thumbnail (`WorkspacesPopupState.hoverWorkspace`).
  - **Scroll Wheel:** Cycles sequentially through active workspaces.
