#!/usr/bin/env bash
#
# idle-inhibitor.sh — Persistent idle-inhibitor for waybar custom module
#
# Usage:
#   idle-inhibitor.sh status   → emit JSON for waybar (called by "exec")
#   idle-inhibitor.sh toggle   → toggle inhibition state and re-signal waybar
#
# State is persisted in ~/.config/hyprcandy/idle-inhibitor.state
# so that if waybar is restarted (e.g. after being hidden) it always
# restores the last user-chosen state without requiring a fresh toggle.
#
# The module uses SIGRTMIN+10 (signal 10 in waybar config) to tell waybar
# to re-exec the status command after a toggle.
#
# Icons (Nerd Font):
#   Enabled  → 󰅶  (caffeine / mdi:coffee)
#   Disabled → 󰾪  (mdi:coffee-off)

STATE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hyprcandy"
STATE_FILE="$STATE_DIR/idle-inhibitor.state"
PID_FILE="$STATE_DIR/idle-inhibitor.pid"

ICON_ON="󰅶 "
ICON_OFF="󰾪 "
TOOLTIP_ON="Caffeine Mode On"
TOOLTIP_OFF="Caffeine Mode Off"

# ── helpers ──────────────────────────────────────────────────────────────────

mkdir -p "$STATE_DIR"

_read_state() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        # Default: disabled on first-ever run
        echo "disabled"
    fi
}

_write_state() {
    echo "$1" > "$STATE_FILE"
}

_kill_inhibitor() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
        rm -f "$PID_FILE"
    fi
    # Also kill any stray systemd-inhibit we may have launched
    pkill -f "systemd-inhibit.*idle-inhibitor" 2>/dev/null || true
}

_start_inhibitor() {
    _kill_inhibitor
    # systemd-inhibit keeps the idle inhibitor alive as a background process.
    # It will be reaped automatically when the PID is killed.
    systemd-inhibit \
        --what=idle \
        --who="waybar-idle-inhibitor" \
        --why="Caffeine Mode" \
        --mode=block \
        sleep infinity &
    echo $! > "$PID_FILE"
    disown
}

_emit_status() {
    local state
    state=$(_read_state)

    if [[ "$state" == "enabled" ]]; then
        printf '{"text":"%s","tooltip":"%s","class":"activated"}\n' \
            "$ICON_ON" "$TOOLTIP_ON"
    else
        printf '{"text":"%s","tooltip":"%s","class":"deactivated"}\n' \
            "$ICON_OFF" "$TOOLTIP_OFF"
    fi
}

# ── main ──────────────────────────────────────────────────────────────────────

case "${1:-status}" in

    status)
        # On startup, restore the saved state so waybar always matches it.
        state=$(_read_state)
        if [[ "$state" == "enabled" ]]; then
            # Inhibitor may have been killed when waybar was hidden — restart it.
            if ! { [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; }; then
                _start_inhibitor
            fi
        fi
        _emit_status
        ;;

    toggle)
        state=$(_read_state)
        if [[ "$state" == "enabled" ]]; then
            _kill_inhibitor
            _write_state "disabled"
        else
            _start_inhibitor
            _write_state "enabled"
        fi
        # Tell waybar to re-run the exec command for this module
        pkill -SIGRTMIN+10 waybar
        ;;

    *)
        echo "Usage: $0 {status|toggle}" >&2
        exit 1
        ;;
esac
