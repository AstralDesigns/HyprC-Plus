#!/usr/bin/env bash
# wallpaper-cycle.sh
# Cycles through wallpapers using awww. Reads/writes ~/.config/wallpaper/wallpaper.ini

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
fill = fill
sort = name
subfolders = False
show_hidden = False
awww_transition_type = any
awww_transition_step = 90
awww_transition_angle = 0
awww_transition_duration = 2
awww_transition_fps = 60
EOF
  echo "Created default config at $WP_CONFIG — set folder= before cycling."
  exit 0
fi

# ── Patch any missing keys into existing ini ──────────────────────────────────
write_default monitors          All
write_default fill              fill
write_default sort              name
write_default subfolders        False
write_default show_hidden       False
write_default awww_transition_type     any
write_default awww_transition_step     90
write_default awww_transition_angle    0
write_default awww_transition_duration 2
write_default awww_transition_fps      60

# ── Read values from config.ini ───────────────────────────────────────────────
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
TRANSITION_TYPE="$(get_ini_value awww_transition_type)"
TRANSITION_STEP="$(get_ini_value awww_transition_step)"
TRANSITION_ANGLE="$(get_ini_value awww_transition_angle)"
TRANSITION_DURATION="$(get_ini_value awww_transition_duration)"
TRANSITION_FPS="$(get_ini_value awww_transition_fps)"

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

# ── Find the next wallpaper ───────────────────────────────────────────────────
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

echo "Current : $CURRENT"
echo "Next    : $NEXT"

# ── Ensure awww daemon is running ─────────────────────────────────────────────
if ! awww query &>/dev/null; then
  echo "Starting awww daemon..."
  awww-daemon &
  sleep 0.5
fi

# ── Apply wallpaper ───────────────────────────────────────────────────────────
awww img "$NEXT" \
  --transition-type     "${TRANSITION_TYPE:-any}" \
  --transition-step     "${TRANSITION_STEP:-90}" \
  --transition-angle    "${TRANSITION_ANGLE:-0}" \
  --transition-duration "${TRANSITION_DURATION:-2}" \
  --transition-fps      "${TRANSITION_FPS:-60}"

# ── Update wallpaper.ini with the new wallpaper path ─────────────────────────
NEXT_STORED="${NEXT/$HOME/\~}"
if grep -qE "^\s*wallpaper\s*=" "$WP_CONFIG"; then
  sed -i "s|^wallpaper\s*=.*|wallpaper = $NEXT_STORED|" "$WP_CONFIG"
else
  sed -i "/^\[Settings\]/a wallpaper = $NEXT_STORED" "$WP_CONFIG"
fi

echo "Config updated → wallpaper = $NEXT_STORED"

# ── Trigger color regeneration ────────────────────────────────────────────────
[[ -x "$INTEGRATION" ]] && nohup "$INTEGRATION" >/dev/null 2>&1 &
