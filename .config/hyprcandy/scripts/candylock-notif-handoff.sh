#!/usr/bin/env bash
# Notification DBus handoff for candylock — bar must not restart the daemon while locked.
CANDYLOCK_NOTIF_LOCK="${CANDYLOCK_NOTIF_LOCK:-/tmp/candylock-notif.lock}"

candylock_notif_acquire() {
    touch "$CANDYLOCK_NOTIF_LOCK"
    if pgrep -f "notify-daemon.py" >/dev/null 2>&1; then
        pkill -f "notify-daemon.py" 2>/dev/null || true
    fi
}

candylock_notif_release() {
    rm -f "$CANDYLOCK_NOTIF_LOCK"
}
