#!/bin/bash
# Bluetooth pairing agent helper script
# Handles external pairing requests and forwards to QuickShell via IPC

set -euo pipefail

# IPC socket path
QS_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/quickshell-ipc"

# Function to send IPC message to QuickShell
send_ipc() {
    local target="$1"
    local method="$2"
    shift 2
    echo "{\"target\":\"$target\",\"method\":\"$method\",\"args\":$*}" | socat - UNIX-CONNECT:"$QS_SOCKET" 2>/dev/null || true
}

# Function to handle pairing request
handle_pair_request() {
    local mac="$1"
    local name="$2"
    
    # Send notification to QuickShell
    send_ipc "notifications" "add" \
        "[\"Pairing Request\",\"$name ($mac) wants to pair\",\"󰂱\",\"critical\",[\"accept\",\"reject\"]]"
    
    # Also send to bluetooth module
    send_ipc "bluetooth" "handleExternalPair" \
        "[\"$mac\",\"$name\"]"
}

# Function to handle file transfer request
handle_file_request() {
    local mac="$1"
    local name="$2"
    local file="$3"
    
    send_ipc "notifications" "add" \
        "[\"File Transfer\",\"$name ($mac) wants to send $file\",\"󰶫\",\"normal\",[\"accept\",\"reject\"]]"
    
    send_ipc "bluetooth" "handleFileTransfer" \
        "[\"$mac\",\"$name\",\"$file\"]"
}

# Main agent loop
bluetoothctl agent << 'EOF' | while read -r line; do
    case "$line" in
        "RequestPinCode"*)
            mac=$(echo "$line" | sed 's/RequestPinCode //')
            name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Alias:" | cut -d' ' -f2- || echo "$mac")
            handle_pair_request "$mac" "$name"
            ;;
        "RequestConfirmation"*)
            mac=$(echo "$line" | sed 's/RequestConfirmation //')
            name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Alias:" | cut -d' ' -f2- || echo "$mac")
            handle_pair_request "$mac" "$name"
            ;;
        "Authorize"*)
            mac=$(echo "$line" | sed 's/Authorize //')
            name=$(bluetoothctl info "$mac" 2>/dev/null | grep "Alias:" | cut -d' ' -f2- || echo "$mac")
            send_ipc "notifications" "add" \
                "[\"Authorization Required\",\"$name ($mac) requests connection\",\"󰂱\",\"normal\",[\"authorize\",\"deny\"]]"
            ;;
    esac
done
EOF
