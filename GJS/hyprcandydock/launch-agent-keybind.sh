#!/usr/bin/env bash
set -eu

HERE="$(cd "$(dirname "$0")" && pwd)"
TOGGLE="$HERE/toggle-app-launcher.sh"
ELECTRON="$HERE/start-electron-agent.sh"
URL="http://127.0.0.1:17842/index.html"

if ! ss -ltn 2>/dev/null | grep -q '127\.0\.0\.1:17842'; then
    "$TOGGLE"
fi

for _ in $(seq 1 50); do
    if curl --silent --fail --max-time 1 "$URL" >/dev/null 2>&1; then
        exec "$ELECTRON" "$URL"
    fi
    sleep 0.1
done

echo "HyprCandy agent server did not become ready on 127.0.0.1:17842" >&2
exit 1
