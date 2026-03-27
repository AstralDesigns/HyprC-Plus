# Bluetooth Manager for QuickShell

A comprehensive Bluetooth management system for QuickShell with robust pairing, file transfer handling, and notifications.

## Features

- **Robust Pairing Logic**: Handles external pairing requests with proper notifications
- **File Transfer Management**: Accept/reject prompts for incoming files
- **Universal Notifications**: Integration with notification center using matugen theming
- **Process Isolation**: Prevents shell reloads on process exit
- **Auto-recovery**: Automatic restart of services on unexpected exit

## Components

### 1. Main Bluetooth Manager (`shell.qml`)
- Full-featured Bluetooth management UI
- Device discovery, pairing, and connection management
- Real-time notifications for pairing requests and file transfers
- Integration with universal notification center

### 2. Universal Notification Center (`../notifications/shell.qml`)
- Standalone notification system with matugen theming
- IPC interface for other modules
- Do Not Disturb mode
- Auto-dismiss based on urgency
- Action buttons for interactive notifications

### 3. Helper Scripts
- `pair-agent.sh`: Handles external pairing requests
- `obex-service.sh`: Monitors file transfers
- Both scripts forward events to QuickShell via IPC

## Usage

### Launch Services
```bash
# Start Bluetooth manager
qs -c bluetooth

# Start notification center (for standalone use)
qs -c notifications

# Start helper services (run in background)
/home/king/.config/quickshell/bluetooth/pair-agent.sh &
/home/king/.config/quickshell/bluetooth/obex-service.sh &
```

### IPC Interface

#### Bluetooth Module
```javascript
// Toggle visibility
qs-ipc bluetooth toggle

// Add device
qs-ipc bluetooth addDevice "AA:BB:CC:DD:EE:FF" "Device Name"

// Handle external pairing
qs-ipc bluetooth handleExternalPair '["AA:BB:CC:DD:EE:FF","Device Name"]'
```

#### Notification Center
```javascript
// Add notification
qs-ipc notifications add '["Title","Message","icon","urgency",["action1","action2"]]'

// Clear all
qs-ipc notifications clear

// Toggle Do Not Disturb
qs-ipc notifications toggleDnd
```

## Troubleshooting

### Pairing Issues
1. Ensure Bluetooth adapter is powered on
2. Check if device is discoverable
3. Verify agent is registered: `bluetoothctl list-agents`
4. Restart services if pairing fails

### File Transfer Issues
1. Ensure OBEX service is running: `systemctl --user status obex`
2. Check if receive mode is enabled
3. Verify file permissions in download directory

### Notification Issues
1. Check IPC socket: `ls -la $XDG_RUNTIME_DIR/quickshell-ipc`
2. Verify notification center is running
3. Check Do Not Disturb mode

## Dependencies

- `bluetoothctl` - BlueZ command-line tool
- `obexctl` - OBEX file transfer tool
- `socat` - IPC communication (optional, for external scripts)
- QuickShell with Wayland support

## Configuration

### Matugen Colors
All modules automatically load matugen colors from:
```
${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/wallpaper/MatugenColors.qml
```

### Settings
- Bluetooth settings are stored in QuickShell settings
- Notification preferences persist across sessions

## Security Notes

- Pairing uses KeyboardOnly agent for security
- File transfers require explicit approval
- All IPC communications are local-only
- No persistent storage of sensitive data

## Integration with Other Modules

The notification center can be used by any QuickShell module via IPC:

```javascript
// In any QML module
IpcHandler {
    target: "notifications"
    function show(title, message) {
        add(title, message, "󰋙", "normal", [])
    }
}
```

## File Structure
```
/home/king/.config/quickshell/
├── bluetooth/
│   ├── shell.qml              # Main Bluetooth manager
│   ├── pair-agent.sh          # External pairing handler
│   ├── obex-service.sh        # File transfer monitor
│   └── README.md              # This file
├── notifications/
│   └── shell.qml              # Universal notification center
└── startmenu/
    └── shell.qml              # Updated with Bluetooth controls
```
