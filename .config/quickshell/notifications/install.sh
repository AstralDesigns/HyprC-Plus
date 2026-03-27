#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Quickshell Notification + BT Agent — installer
#  Run once:  bash ~/.config/quickshell/notifications/install.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "→ Checking Python deps..."
python3 -c "import dbus" 2>/dev/null || {
    echo "  Installing python-dbus..."
    sudo pacman -S --needed --noconfirm python-dbus 2>/dev/null \
    || pip install dbus-python --break-system-packages 2>/dev/null \
    || { echo "  ERROR: install python-dbus manually"; exit 1; }
}
python3 -c "from gi.repository import GLib" 2>/dev/null || {
    echo "  Installing python-gobject..."
    sudo pacman -S --needed --noconfirm python-gobject 2>/dev/null \
    || { echo "  ERROR: install python-gobject manually"; exit 1; }
}
echo "  Python deps OK"

echo "→ Checking bluetooth tools..."
command -v bluetoothctl >/dev/null || { echo "  ERROR: bluetoothctl not found — install bluez"; exit 1; }
# Ensure bluetooth service is running
systemctl is-active --quiet bluetooth || sudo systemctl enable --now bluetooth
echo "  Bluetooth OK"

echo "→ Checking OBEX tools..."
# obexd is part of bluez-obex on Arch
if ! systemctl --user is-active --quiet obex 2>/dev/null; then
    systemctl --user enable --now obex 2>/dev/null || true
fi
echo "  OBEX OK (may need bluez-obex package)"

echo "→ Setting up hyprland autostart..."
HYPR_CONF="$HOME/.config/hypr/hyprland.conf"
EXEC_LINE="exec-once = pkill -x swaync; pkill -x dunst; sleep 0.3; qs -c $HOME/.config/quickshell/notifications"
if [ -f "$HYPR_CONF" ]; then
    if ! grep -q "quickshell/notifications" "$HYPR_CONF"; then
        echo "" >> "$HYPR_CONF"
        echo "# Quickshell notification center (replaces swaync)" >> "$HYPR_CONF"
        echo "$EXEC_LINE" >> "$HYPR_CONF"
        echo "  Added to hyprland.conf"
    else
        echo "  Already in hyprland.conf"
    fi
fi

echo "→ Making scripts executable..."
chmod +x "$SCRIPT_DIR/bt-agent.py" "$SCRIPT_DIR/notify-daemon.py"

echo ""
echo "✓ Done! Reload Quickshell or run:"
echo "  pkill -x swaync; qs -c ~/.config/quickshell/notifications &"
echo ""
echo "  To test: notify-send 'Hello' 'Notification center is working'"
echo ""
echo "  IPC toggle history panel:"
echo "  qs ipc call notifications toggle"
