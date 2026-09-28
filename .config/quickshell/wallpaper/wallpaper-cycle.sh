#!/usr/bin/env bash
# wallpaper-cycle.sh
# Cycles through wallpapers using awww. Reads/writes ~/.config/wallpaper/wallpaper.ini
#
# Transition/resize settings are kept in sync by shell.qml (which writes them
# to wallpaper.ini whenever the picker settings change). This means the cycle
# script always uses exactly what the wallpaper picker is configured to use.

# ── Config path ───────────────────────────────────────────────────────────────
WP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper/wallpaper.ini"
INTEGRATION="${XDG_CONFIG_HOME:-$HOME/.config}/hyprcandy/hooks/wallpaper_integration.sh"

# ── Write key if missing from ini ─────────────────────────────────────────────
write_default() {
  local key="$1" val="$2"
  if ! grep -qE "^\s*${key}\s*=" "$WP_CONFIG" 2>/dev/null; then
    echo "${key} = ${val}" >> "$WP_CONFIG"
  fi
}

# ── Bootstrap config if missing ───────────────────────────────────────────────
if [[ ! -f "$WP_CONFIG" ]]; then
  mkdir -p "$(dirname "$WP_CONFIG")"
  cat > "$WP_CONFIG" <<'EOF'
[Settings]
folder = ~/Pictures
wallpaper =
monitors = All
sort = name
subfolders = False
show_hidden = False
awww_transition_type = any
awww_transition_step = 90
awww_transition_angle = 0
awww_transition_duration = 2
awww_transition_fps = 60
awww_resize = crop
EOF
  echo "Created default config at $WP_CONFIG — set folder= before cycling."
  exit 0
fi

# ── Patch any missing keys into existing ini ──────────────────────────────────
write_default monitors              All
write_default sort                  name
write_default subfolders            False
write_default show_hidden           False
write_default awww_transition_type  any
write_default awww_transition_step  90
write_default awww_transition_angle 0
write_default awww_transition_duration 2
write_default awww_transition_fps   60
write_default awww_resize           crop

# ── Migrate legacy 'fill' key → 'awww_resize' then remove it ─────────────────
if grep -qE "^\s*fill\s*=" "$WP_CONFIG" 2>/dev/null; then
  LEGACY_FILL="$(grep -E "^\s*fill\s*=" "$WP_CONFIG" | head -n1 | sed 's/[^=]*=\s*//' | xargs)"
  case "${LEGACY_FILL,,}" in
    fill|crop) MIGRATED_RESIZE="crop" ;;
    fit)       MIGRATED_RESIZE="fit" ;;
    stretch)   MIGRATED_RESIZE="stretch" ;;
    no|none)   MIGRATED_RESIZE="no" ;;
    *)         MIGRATED_RESIZE="crop" ;;
  esac
  # Write migrated value into awww_resize if not already set to a real value
  sed -i "s|^\s*awww_resize\s*=.*|awww_resize = $MIGRATED_RESIZE|" "$WP_CONFIG"
  # Remove legacy fill key
  sed -i "/^\s*fill\s*=/d" "$WP_CONFIG"
  echo "Migrated legacy 'fill = $LEGACY_FILL' → 'awww_resize = $MIGRATED_RESIZE'"
fi

# ── Read values from wallpaper.ini ────────────────────────────────────────────
get_ini_value() {
  local key="$1"
  grep -E "^\s*${key}\s*=" "$WP_CONFIG" \
    | head -n1 \
    | sed 's/[^=]*=\s*//' \
    | sed "s|~|$HOME|g" \
    | xargs
}

FOLDER="$(get_ini_value folder)"
CURRENT="$(get_ini_value wallpaper)"
SUBFOLDERS="$(get_ini_value subfolders)"
SHOW_HIDDEN="$(get_ini_value show_hidden)"
SORT="$(get_ini_value sort)"
MONITORS="$(get_ini_value monitors)"
TRANSITION_TYPE="$(get_ini_value awww_transition_type)"
TRANSITION_STEP="$(get_ini_value awww_transition_step)"
TRANSITION_ANGLE="$(get_ini_value awww_transition_angle)"
TRANSITION_DURATION="$(get_ini_value awww_transition_duration)"
TRANSITION_FPS="$(get_ini_value awww_transition_fps)"
AWWW_RESIZE="$(get_ini_value awww_resize)"

# ── Validate folder ───────────────────────────────────────────────────────────
if [[ ! -d "$FOLDER" ]]; then
  echo "Error: wallpaper folder not found: $FOLDER"
  exit 1
fi

# ── Collect wallpapers (no eval — use array-based find) ───────────────────────
FIND_ARGS=("$FOLDER")
[[ "${SUBFOLDERS,,}" != "true" ]] && FIND_ARGS+=("-maxdepth" "1")
FIND_ARGS+=("-type" "f")
[[ "${SHOW_HIDDEN,,}" != "true" ]] && FIND_ARGS+=("!" "-name" ".*")
FIND_ARGS+=("(" "-iname" "*.jpg" "-o" "-iname" "*.jpeg" "-o" "-iname" "*.png"
                "-o" "-iname" "*.webp" "-o" "-iname" "*.gif" "-o" "-iname" "*.bmp" ")")
FIND_ARGS+=("-print")

mapfile -t WALLPAPERS < <(find "${FIND_ARGS[@]}" | sort)

if [[ ${#WALLPAPERS[@]} -eq 0 ]]; then
  echo "Error: no wallpapers found in $FOLDER"
  exit 1
fi

# ── Sort order ────────────────────────────────────────────────────────────────
case "${SORT,,}" in
  random) WALLPAPERS=( $(printf '%s\n' "${WALLPAPERS[@]}" | shuf) ) ;;
  *) WALLPAPERS=( $(printf '%s\n' "${WALLPAPERS[@]}" | sort) ) ;;
esac

# ── Direction: default is --next ──────────────────────────────────────────────
DIRECTION="${1:---next}"

# ── Find the next / previous wallpaper ────────────────────────────────────────
TARGET=""

if [[ "$DIRECTION" == "--prev" || "$DIRECTION" == "-p" ]]; then
  PREV=""
  for WP in "${WALLPAPERS[@]}"; do
    if [[ "$WP" == "$CURRENT" ]]; then
      break
    fi
    PREV="$WP"
  done
  [[ -z "$PREV" ]] && PREV="${WALLPAPERS[-1]}"
  TARGET="$PREV"
  echo "Direction: prev"
else
  NEXT=""
  FOUND=false
  for WP in "${WALLPAPERS[@]}"; do
    if $FOUND; then
      NEXT="$WP"
      break
    fi
    [[ "$WP" == "$CURRENT" ]] && FOUND=true
  done
  [[ -z "$NEXT" ]] && NEXT="${WALLPAPERS[0]}"
  TARGET="$NEXT"
  echo "Direction: next"
fi

echo "Current : $CURRENT"
echo "Target  : $TARGET"

# ── Ensure awww daemon is running ─────────────────────────────────────────────
if ! awww query &>/dev/null; then
  echo "Starting awww daemon..."
  awww-daemon &
  sleep 0.5
fi

# ── Build awww output argument ────────────────────────────────────────────────
AWWW_ARGS=()
if [[ -n "$MONITORS" && "${MONITORS,,}" != "all" ]]; then
    AWWW_ARGS+=(--outputs "$MONITORS")
fi

# ── Apply wallpaper ───────────────────────────────────────────────────────────
awww img "$TARGET" \
  --transition-type     "${TRANSITION_TYPE:-any}" \
  --transition-step     "${TRANSITION_STEP:-90}" \
  --transition-angle    "${TRANSITION_ANGLE:-0}" \
  --transition-duration "${TRANSITION_DURATION:-2}" \
  --transition-fps      "${TRANSITION_FPS:-60}" \
  --resize              "${AWWW_RESIZE:-crop}" \
  "${AWWW_ARGS[@]}"

STATUS=$?
if [[ $STATUS -ne 0 ]]; then
  echo "wallpaper-cycle: awww img failed (exit $STATUS)" >&2
  exit $STATUS
fi

# ── Update wallpaper.ini with the new wallpaper path ─────────────────────────
TARGET_STORED="${TARGET/$HOME/\~}"
if grep -qE "^\s*wallpaper\s*=" "$WP_CONFIG"; then
  sed -i "s|^wallpaper\s*=.*|wallpaper = $TARGET_STORED|" "$WP_CONFIG"
else
  sed -i "/^\[Settings\]/a wallpaper = $TARGET_STORED" "$WP_CONFIG"
fi

# ── Update monitors.json ──────────────────────────────────────────────────────
MON_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper/monitors.json"
MON_KEY="all"
[[ -n "$MONITORS" && "${MONITORS,,}" != "all" ]] && MON_KEY="$MONITORS"
python3 - <<PYEOF 2>/dev/null || true
import json, os
p = os.path.expanduser("$MON_CONFIG")
data = {}
if os.path.exists(p):
    try:
        with open(p) as f: data = json.load(f)
    except: pass
data["$MON_KEY"] = "$TARGET"
with open(p, "w") as f: json.dump(data, f, indent=2)
PYEOF

echo "Config updated → wallpaper = $TARGET_STORED"

# ── Trigger color regeneration ────────────────────────────────────────────────
if [[ -x "$INTEGRATION" ]]; then
    nohup "$INTEGRATION" >/dev/null 2>&1 && sleep 10 && nohup "$INTEGRATION" >/dev/null 2>&1 &
else
    pkill -f /usr/bin/bash "$INTEGRATION"
    sleep 0.5
    nohup "$INTEGRATION" >/dev/null 2>&1 && sleep 10 && nohup "$INTEGRATION" >/dev/null 2>&1 &
fi
