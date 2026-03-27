# Quickshell Notification + Bluetooth Agent

## Files
- `shell.qml`        — Main Quickshell entry point (notification center)
- `notify-daemon.py` — Claims `org.freedesktop.Notifications` DBus name
- `bt-agent.py`      — BlueZ Agent1 + OBEX Agent1 (pair prompts, file transfer)
- `install.sh`       — One-time setup script

## What this replaces
- **swaync** — notification daemon & history tray
- **bluetoothctl agent** — manual pairing agent
- **obexd auto-accept** — replaced with interactive prompts

## Features
- Live toast stack (top-right, clears waybar)
- 5s auto-dismiss for normal, permanent for critical & prompts
- Slide-in animation, urgency accent bar, countdown progress bar
- Notification history tray (IPC: `qs ipc call notifications toggle`)
- **Bluetooth pairing prompts** — passkey confirm, PIN entry, authorize
- **File transfer prompts** — Accept / Decline with filename + size
- BT agent makes adapter Discoverable + Pairable on startup
- Removes stale pairing state on failed pair so re-pair works cleanly
- Matugen live color theming (same MatugenColors.qml cache as startmenu)

## Install
```bash
bash ~/.config/quickshell/notifications/install.sh
```

## Hyprland autostart
```ini
exec-once = pkill -x swaync; pkill -x dunst; sleep 0.3; qs -c ~/.config/quickshell/notifications
```

## Waybar integration (notification badge)
Add to your waybar config's custom module:
```json
"custom/notifs": {
    "exec": "qs ipc call notifications toggle",
    "on-click": "qs ipc call notifications toggle",
    "format": "󰂞"
}
```
