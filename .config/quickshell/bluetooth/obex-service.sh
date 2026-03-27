#!/bin/bash
# OBEX file transfer service helper
# Monitors for incoming file transfers and forwards to QuickShell

set -euo pipefail

# IPC socket path
QS_SOCKET="${XDG_RUNTIME_DIR:-/tmp}/quickshell-ipc"

# Function to send IPC message
send_ipc() {
    local target="$1"
    local method="$2"
    shift 2
    echo "{\"target\":\"$target\",\"method\":\"$method\",\"args\":$*}" | socat - UNIX-CONNECT:"$QS_SOCKET" 2>/dev/null || true
}

# Function to handle incoming transfer
handle_incoming() {
    local line="$1"
    
    # Parse transfer info
    if [[ "$line" =~ Incoming\ transfer\ from\ (.+)\ \((.+)\) ]]; then
        local name="${BASH_REMATCH[1]}"
        local mac="${BASH_REMATCH[2]}"
        
        send_ipc "notifications" "add" \
            "[\"Incoming File\",\"$name ($mac) wants to send a file\",\"󰶫\",\"normal\",[\"accept\",\"reject\"]]"
        
        send_ipc "bluetooth" "handleIncomingTransfer" \
            "[\"$mac\",\"$name\"]"
    fi
}

# Monitor OBEX service
obexctl << 'EOF' | while read -r line; do
    case "$line" in
        "Incoming"*)
            handle_incoming "$line"
            ;;
        "Transfer"*)
            # Parse transfer progress
            if [[ "$line" =~ Transfer\ ([0-9]+):\ (.+) ]]; then
                local id="${BASH_REMATCH[1]}"
                local status="${BASH_REMATCH[2]}"
                
                send_ipc "bluetooth" "updateTransferStatus" \
                    "[\"$id\",\"$status\"]"
            fi
            ;;
    esac
done
EOF
