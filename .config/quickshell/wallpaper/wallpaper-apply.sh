#!/usr/bin/env bash
# wallpaper-apply.sh
# Called by the Quickshell wallpaper picker.
# Usage: wallpaper-apply.sh <path> <type> <step> <angle> <duration> <fps> <resize> <output>
#
# Place at: ~/.config/quickshell/wallpaper/wallpaper-apply.sh
# Make executable: chmod +x ~/.config/quickshell/wallpaper/wallpaper-apply.sh

WALLPAPER="$1"
TRANS_TYPE="${2:-any}"
TRANS_STEP="${3:-90}"
TRANS_ANGLE="${4:-0}"
TRANS_DURATION="${5:-2}"
TRANS_FPS="${6:-60}"
RESIZE="${7:-crop}"
OUTPUT="${8:-all}"

if [[ -z "$WALLPAPER" || ! -f "$WALLPAPER" ]]; then
    echo "wallpaper-apply: invalid path: '$WALLPAPER'" >&2
    exit 1
fi

# ── Ensure awww daemon is running ─────────────────────────────────────────────
if ! awww query &>/dev/null; then
    echo "wallpaper-apply: starting awww-daemon..." >&2
    awww-daemon &
    sleep 0.6
fi

# ── Prepare output arguments ──────────────────────────────────────────────────
AWWW_ARGS=()
if [[ -n "$OUTPUT" && "$OUTPUT" != "all" && "$OUTPUT" != "All" ]]; then
    AWWW_ARGS+=(--outputs "$OUTPUT")
fi

# ── Apply ─────────────────────────────────────────────────────────────────────
awww img "$WALLPAPER" \
    --transition-type     "$TRANS_TYPE"     \
    --transition-step     "$TRANS_STEP"     \
    --transition-angle    "$TRANS_ANGLE"    \
    --transition-duration "$TRANS_DURATION" \
    --transition-fps      "$TRANS_FPS"      \
    --resize "$RESIZE" \
    "${AWWW_ARGS[@]}"

STATUS=$?
if [[ $STATUS -ne 0 ]]; then
    echo "wallpaper-apply: awww img failed (exit $STATUS)" >&2
    exit $STATUS
fi

# ── Persist to ~/.config/wallpaper/wallpaper.ini & monitors.json ──────────────
WP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper/wallpaper.ini"
MON_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper/monitors.json"
STORED="${WALLPAPER/$HOME/\~}"
DIR_PATH="$(dirname "$WALLPAPER")"
DIR_STORED="${DIR_PATH/$HOME/\~}"

mkdir -p "$(dirname "$WP_CONFIG")"

if [[ ! -f "$WP_CONFIG" ]]; then
    printf '[Settings]\n' > "$WP_CONFIG"
fi

if [[ -n "$OUTPUT" && "$OUTPUT" != "all" && "$OUTPUT" != "All" ]]; then
    MON_KEY="wallpaper_${OUTPUT}"
    if grep -qE "^${MON_KEY}[[:space:]]*=" "$WP_CONFIG"; then
        sed -i "s|^${MON_KEY}[[:space:]]*=.*|${MON_KEY} = $STORED|" "$WP_CONFIG"
    else
        echo "${MON_KEY} = $STORED" >> "$WP_CONFIG"
    fi
    python3 -c "
import json, os
p = os.path.expanduser('$MON_CONFIG')
data = {}
if os.path.exists(p):
    try:
        with open(p) as f: data = json.load(f)
    except: pass
data['$OUTPUT'] = '$WALLPAPER'
with open(p, 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null || true
else
    if grep -qE '^wallpaper[[:space:]]*=' "$WP_CONFIG"; then
        sed -i "s|^wallpaper[[:space:]]*=.*|wallpaper = $STORED|" "$WP_CONFIG"
    else
        echo "wallpaper = $STORED" >> "$WP_CONFIG"
    fi
    python3 -c "
import json, os
p = os.path.expanduser('$MON_CONFIG')
data = {}
if os.path.exists(p):
    try:
        with open(p) as f: data = json.load(f)
    except: pass
data['all'] = '$WALLPAPER'
with open(p, 'w') as f: json.dump(data, f, indent=2)
" 2>/dev/null || true
fi

if grep -qE '^folder[[:space:]]*=' "$WP_CONFIG"; then
    sed -i "s|^folder[[:space:]]*=.*|folder = $DIR_STORED|" "$WP_CONFIG"
else
    echo "folder = $DIR_STORED" >> "$WP_CONFIG"
fi

echo "wallpaper-apply: set → $STORED (output: $OUTPUT)"

# ── Trigger matugen color regeneration ────────────────────────────────────────
INTEGRATION="${XDG_CONFIG_HOME:-$HOME/.config}/hyprcandy/hooks/wallpaper_integration.sh"
if [[ -x "$INTEGRATION" ]] ;then
    nohup "$INTEGRATION" >/dev/null 2>&1 && sleep 10 && nohup "$INTEGRATION" >/dev/null 2>&1 &
else
    pkill -f /usr/bin/bash "$INTEGRATION"
    sleep 0.5
    nohup "$INTEGRATION" >/dev/null 2>&1 && sleep 10 && nohup "$INTEGRATION" >/dev/null 2>&1 &
fi
