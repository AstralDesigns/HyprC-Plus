#!/usr/bin/env bash
# candylock.sh — launch the unified candylock
# Use this as your lock command in swayidle / Hyprland bindl

set -euo pipefail

CONFDIR="$HOME/.config/quickshell/lockscreens"
# Active lockscreen theme (folder under CONFDIR), chosen by the CC Lockscreen tab.
CURRENT="$(cat "$CONFDIR/lockscreens-current" 2>/dev/null || echo candylock)"
# Pre-seed active wallpaper path so candylock renders wallpaper synchronously on frame 0
if [ -f "$HOME/.config/wallpaper/wallpaper.ini" ]; then
    WP=$(sed -n 's/^wallpaper[[:space:]]*=[[:space:]]*//p' "$HOME/.config/wallpaper/wallpaper.ini" | head -n1 | sed "s|^~|$HOME|")
    [ -n "$WP" ] && export CANDYLOCK_WALLPAPER="$WP"
fi

# Signal bar to immediately fade in the smooth blur overlay
touch /tmp/qs-candylock-trans.lock 2>/dev/null || true

# Rebuild pam_auth if source is newer than binary or binary missing
if [ "$CONFDIR/$CURRENT/pam_auth.c" -nt "$CONFDIR/$CURRENT/pam_auth" ] 2>/dev/null || \
   [ ! -x "$CONFDIR/$CURRENT/pam_auth" ]; then
    gcc -O2 -o "$CONFDIR/$CURRENT/pam_auth" "$CONFDIR/$CURRENT/pam_auth.c" -lpam
fi

# Kill any stale instance
if pgrep -f "qs -p .*lockscreens/" >/dev/null 2>&1; then
    pkill -f "qs -p .*lockscreens/" 2>/dev/null || true
    sleep 0.05
fi

# Hand notification DBus to candylock (bar must not reclaim while locked)
# shell:bar/NotificationsState.qml
source "$HOME/.config/hyprcandy/scripts/candylock-notif-handoff.sh"
candylock_notif_acquire

cleanup() {
    rm -f /tmp/qs-candylock-trans.lock 2>/dev/null || true
    candylock_notif_release
}
trap cleanup EXIT INT TERM

# Start (blocks until unlocked)
qs -p "$CONFDIR/$CURRENT"
