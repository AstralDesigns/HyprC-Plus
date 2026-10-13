#!/bin/bash
# devfix.sh — free a zombie-held DevTools port (default 9223).
#
# Why this exists: QTWEBENGINE_REMOTE_DEBUGGING binds at browser-core startup.
# Helper processes forked from the core (wallpaper loops: inotifywait, sleep,
# playerctl, bash) INHERIT the LISTEN socket fd and keep the port occupied
# after the core dies, so the next qs silently fails to bind and every CDP
# probe hangs on the ghost socket (TimeoutError on /json/list).
#
# Usage: bash devfix.sh [port]
# Then FULLY restart qs (the core only binds at launch).
set -u
PORT="${1:-9223}"

if curl -s --noproxy '*' -m 2 "http://127.0.0.1:$PORT/json/version" >/dev/null; then
    echo "port $PORT is healthy (real DevTools answering); nothing to do."
    exit 0
fi

PIDS=$(ss -ltnp 2>/dev/null | grep ":$PORT " \
       | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)

if [ -z "$PIDS" ]; then
    echo "port $PORT has no listener at all — just restart qs to bind it."
    exit 0
fi

PIDLIST=$(echo "$PIDS" | tr '\n' ',' | sed 's/,$//')
echo "zombie holder(s) on $PORT (unresponsive but occupying the fd):"
ps -o pid,etimes,args -p "$PIDLIST" --no-headers || true
echo "killing them (wallpaper loops respawn WITHOUT the inherited fd)..."
kill $PIDS 2>/dev/null
sleep 1
if ss -ltnp 2>/dev/null | grep -q ":$PORT "; then
    echo "still held after SIGTERM — escalating to SIGKILL..."
    P2=$(ss -ltnp | grep ":$PORT " | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
    kill -9 $P2 2>/dev/null
    sleep 1
fi
still=$(ss -ltnp 2>/dev/null | grep -c ":$PORT " || true)
if [ "$still" = "0" ]; then
    echo "port $PORT is free now. FULLY restart qs so the browser core binds it."
else
    echo "WARNING: something still listens on $PORT:"
    ss -ltnp | grep ":$PORT "
fi
