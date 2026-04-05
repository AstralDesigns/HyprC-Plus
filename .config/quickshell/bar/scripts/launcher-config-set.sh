#!/bin/bash
# App Launcher setting writer — updates ~/.config/hyprcandy/launcher-config.state,
# which launcherConfig.js merges over its defaults on every startup.
# After writing, kills the running launcher daemon so the next toggle restarts
# it fresh with the new values baked in as top-level constants.
#
# Usage: launcher-config-set.sh <key> <value>

STATE_FILE="$HOME/.config/hyprcandy/launcher-config.state"

key="$1"
value="$2"

[ -z "$key" ] || [ -z "$value" ] && exit 1

mkdir -p "$(dirname "$STATE_FILE")"

# Read existing state or start fresh
if [ -f "$STATE_FILE" ]; then
    existing=$(cat "$STATE_FILE" 2>/dev/null || echo "{}")
else
    existing="{}"
fi

# Use python3 to safely merge the new key into the JSON state
python3 -c "
import json, sys
data = json.loads(sys.argv[1])
key, val = sys.argv[2], sys.argv[3]
try:
    val = int(val) if '.' not in val else float(val)
except ValueError:
    pass
data[key] = val
print(json.dumps(data, indent=2))
" "$existing" "$key" "$value" > "$STATE_FILE" || exit 1

# Kill the daemon — it will be restarted fresh on the next toggle, picking
# up the new state file. The launcher is always restarted by toggle-app-launcher.sh
# anyway (pkill + re-exec), so this is safe.
pkill -f 'gjs.*app-launcher.js' 2>/dev/null || true
