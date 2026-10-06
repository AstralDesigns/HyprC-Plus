#!/bin/bash
# qsrestart.sh — restart the quickshell bar so the DevTools port binds cleanly.
#
# Why the order matters: the browser core binds QTWEBENGINE_REMOTE_DEBUGGING
# only at startup, and every helper forked from it (wallpaper loops: playerctl,
# inotifywait, sleep, bash) INHERITS the listening fd. If devfix runs while the
# old core is still alive, its loops simply re-fork and re-zombify the port
# (observed twice). Correct sequence: kill core -> kill zombie holders -> start.
#
# Usage: bash qsrestart.sh   (adjust QS_CMD if you launch qs differently)
QS_CMD="${QS_CMD:-qs -c bar}"
DIR="$(cd "$(dirname "$0")" && pwd)"

pkill -f 'qs -c bar' 2>/dev/null
# Wait for full exit + IPC deregistration: starting the new instance while
# the old one still holds the registry yields "already running" -> bar dead
# (hit for real 2026-10-06).
for i in $(seq 1 10); do
    pgrep -f 'qs -c bar' >/dev/null || break
    sleep 1
done
sleep 1.5
bash "$DIR/devfix.sh" 9223
setsid bash -c "$QS_CMD" >/tmp/qs-restart.log 2>&1 < /dev/null &
# Poll: cold QtWebEngine init takes a while; the DevTools port is gone
# (cleanup 2026-10-06), so success = process alive AND the log says the
# configuration loaded.
ok=0
for i in $(seq 1 25); do
    sleep 1
    if pgrep -f 'qs -c bar' >/dev/null && grep -q "Configuration Loaded" /tmp/qs-restart.log 2>/dev/null; then
        ok=1; break
    fi
done
if [ "$ok" = 1 ]; then
    echo "✅ qs up, configuration loaded after ${i}s."
else
    echo "❌ qs not confirmed — check /tmp/qs-restart.log"
fi
