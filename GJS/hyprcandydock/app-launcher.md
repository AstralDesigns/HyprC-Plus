# GJS/hyprcandydock/app-launcher.js

**Overview**

`app-launcher.js` is the HyprCandy application launcher, written in GJS (GNOME JavaScript) for GTK4 with Layer Shell support. It replaces `rofi -show drun` as the app-launching interface triggered by the `hyprcandydock` start button. The file is ~8 000 lines long and runs as a persistent daemon process.

**Architecture**

- **`AppLauncherWindow`** (`GObject.registerClass`) — the main GTK4 `Gtk.Window` subclass. Owns the UI, CSS, keyboard shortcuts, context menus, tabs, and Layer Shell positioning.
- **`LauncherApp`** (`GObject.registerClass` extending `Gtk.Application`) — the daemon application. Manages window lifecycle, fade-in/fade-out animations, and signal-driven toggling (`SIGUSR1` = toggle, `SIGUSR2` = hot-reload CSS).
- **Module-level helpers** — pure functions for spawning apps, reading config files, querying running windows, building the app list, and managing favourites/groups.

**Key Responsibilities**

| Area | Details |
|------|---------|
| **Positioning** | Reads `dock.pos` (0–3) and anchors the launcher 2–3 px from the dock edge, centred on the perpendicular axis via `Gtk4LayerShell` in `OVERLAY` layer with `ON_DEMAND` keyboard mode. |
| **App Discovery** | Builds a sorted list from `Gio.AppInfo.get_all()`, including a manual scan of `~/Desktop/` for Steam game shortcuts. Each entry carries `name`, `iconName`, `className`, `desktopId`, `wmClass`, `exec`, and `steamAppId`. |
| **Running Apps** | Queries `hyprctl clients -j` with an 800 ms TTL cache. Matches running windows to app entries by class name; includes a Steam game heuristic (`steam_app_<id>`). |
| **Search** | Filterable search bar that narrows the icon grid in real time. Enter launches the first match. |
| **Context Menu** | Right-click on an app tile shows: focus/switch to each running instance, "New Window", a separator, and "Pin to Dock / Unpin from Dock". |
| **Favourites & Groups** | Users can favourite apps (`~/.config/hyprcandy-launcher-favorites`) and organise them into named groups (`~/.config/hyprcandy-launcher-groups`). |
| **Pinning** | Reads/writes `~/.config/pinned` and `~/.config/desktop-pinned`. After any pin-state change, sends `pkill -12 -f "gjs dock-main.js"` so the dock hot-reloads immediately. |
| **Styling** | Dynamically builds GTK CSS using the same matugen colour variables as the dock (`@blur_background`, `@primary`, `@on_secondary`, `@inverse_primary`, etc.). Supports live hot-reload via `Gio.FileMonitor` on `gtk-4.0/colors.css`. |
| **Web Search Tab** | Integrates a SearXNG-powered web search tab using `Soup.Session` for native JSON API calls. Supports tabbed browsing, bookmarks, and an inline WebKit view. |
| **Agent / LLM Integration** | Serves the React-based agent UI from a local loopback HTTP server (`127.0.0.1:17842`). Manages Llama.cpp model state, workspace shell warm-up, and a Python runtime backend. |
| **Hybrid Graphics** | Detects GPU topology via `/sys/class/drm` and `SwitcherooControl` DBus. Sets `DRI_PRIME`, `__NV_PRIME_RENDER_OFFLOAD`, or `LIBVA_DRIVER_NAME` as appropriate. Falls back to safe WebKit parameters on CPU-only or problematic legacy Intel GPUs. |
| **Credentials** | Uses GNOME Secrets (`libsecret`) via `CredentialsManager` to securely store service/account credentials. |
| **Persistent Web State** | Saves/restores web-tab state (search queries, bookmarks, open tabs) in `~/.cache/hyprcandy/launcher_web_state.json`. |
| **Keyboard** | Arrow-key navigation through the `FlowBox`, Enter to launch, Escape to close. |
| **Signals** | `SIGUSR1` (10) toggles visibility; `SIGUSR2` (12) hot-reloads CSS and injects theme changes into the agent WebView. |

**Configuration Files Read/Written**

- `dock.pos` — dock position index
- `~/.config/pinned` — dock-pinned app class names
- `~/.config/desktop-pinned` — desktop-pinned app desktop IDs
- `~/.config/hyprcandy-launcher-favorites` — favourited app class names
- `~/.config/hyprcandy-launcher-groups` — JSON map of group name → class names
- `~/.config/workspace-startup-state.json` — workspace shell startup toggle
- `~/.cache/hyprcandy/launcher_web_state.json` — persisted web-tab state
- `~/.cache/hyprcandy/launcher.state` — `"closed"` marker for dock autohide

**Toggle & Signals**

- **Toggle script**: `toggle-app-launcher.sh` (kills if running, spawns if not)
- **Signals sent by the launcher**: `pkill -12 -f "gjs dock-main.js"` after pin-state changes so the dock hot-reloads pinned apps.

**Dependencies**

- GJS with GTK4, Gdk, Gio, GLib, GObject, WebKit6, Soup3, Secret
- `Gtk4LayerShell` (for Layer Shell positioning)
- `hyprctl` (for running-app queries and dock thickness)
- `xdg-open` / `Gio.AppInfo` (for launching apps and URLs)
- `libsecret` (for credentials storage)
