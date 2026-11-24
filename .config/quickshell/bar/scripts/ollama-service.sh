#!/usr/bin/env bash
set -e

ACTION="${1:-status}"
PORT=11434

is_running() {
    curl -s --connect-timeout 1 "http://localhost:${PORT}/api/version" >/dev/null 2>&1
}

case "$ACTION" in
    status)
        if is_running; then
            echo "active"
        else
            echo "inactive"
        fi
        ;;
    start)
        if is_running; then
            echo "active"
            exit 0
        fi
        mkdir -p "$HOME/.local/share/hyprcandy"
        nohup /usr/bin/ollama serve </dev/null > "$HOME/.local/share/hyprcandy/ollama.log" 2>&1 &
        disown
        for i in {1..20}; do
            if is_running; then
                echo "active"
                exit 0
            fi
            sleep 0.2
        done
        echo "failed"
        exit 1
        ;;
    stop)
        systemctl stop ollama 2>/dev/null || true
        pkill -x ollama 2>/dev/null || true
        pkill -f "ollama serve" 2>/dev/null || true
        echo "inactive"
        ;;
    toggle)
        if is_running; then
            "$0" stop
        else
            "$0" start
        fi
        ;;
    *)
        echo "Usage: $0 {status|start|stop|toggle}"
        exit 1
        ;;
esac
