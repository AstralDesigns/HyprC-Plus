#!/usr/bin/env bash
# HyprCandy control-center animation preset helper.
# Lists and applies ~/.config/hypr/conf/animations/*.lua presets without rofi.
#
# Presets are now authored directly in Hyprland's Lua format, so "apply" is a
# plain copy of the chosen preset onto ~/.config/hypr/animations.lua (the file
# hyprland.lua dofiles). No conf->lua translation happens here anymore.

set -euo pipefail

ANIMATIONS_DIR="${HYPRCANDY_ANIMATIONS_DIR:-$HOME/.config/hypr/conf/animations}"
ANIMATION_LUA="${HYPRCANDY_ANIMATION_LUA:-$HOME/.config/hypr/animations.lua}"
ANIMATION_STATE="${HYPRCANDY_ANIMATION_STATE:-$HOME/.config/hypr/animations-current}"

notify_user() {
    command -v notify-send >/dev/null 2>&1 && notify-send "$@" || true
}

# Canonical descriptions retained from the old rofi animations.sh module.
# Keyed by preset stem so the map survives the conf -> lua extension change.
description_for() {
    local stem="${1%.lua}"; stem="${stem%.conf}"
    case "$stem" in
        classic)    printf '%s\n' "Classic smooth animations" ;;
        diablo-1)   printf '%s\n' "Diablo style variant 1" ;;
        diablo-2)   printf '%s\n' "Diablo style variant 2" ;;
        disable)    printf '%s\n' "Disable all animations" ;;
        dynamic)    printf '%s\n' "Dynamic responsive animations" ;;
        end4)       printf '%s\n' "End4 animation preset" ;;
        fast)       printf '%s\n' "Fast and snappy animations" ;;
        high)       printf '%s\n' "High performance animations" ;;
        ja)         printf '%s\n' "Smooth transitions" ;;
        LimeFrenzy) printf '%s\n' "Lime Frenzy energetic style" ;;
        me-1)       printf '%s\n' "Custom ME variant 1" ;;
        me-2)       printf '%s\n' "Custom ME variant 2" ;;
        minimal-1)  printf '%s\n' "Minimal animations variant 1" ;;
        minimal-2)  printf '%s\n' "Minimal animations variant 2" ;;
        moving)     printf '%s\n' "Moving elements focus" ;;
        optimized)  printf '%s\n' "Optimized for performance" ;;
        silent)     printf '%s\n' "Silent minimal animations" ;;
        standard)   printf '%s\n' "Standard Hyprland animations" ;;
        theme)      printf '%s\n' "Theme-based animations" ;;
        vertical)   printf '%s\n' "Vertical workspace switching" ;;
        *)
            local pretty="${stem//-/ }"; pretty="${pretty//_/ }"
            printf '%s\n' "${pretty^} animation preset"
            ;;
    esac
}

label_for() {
    local stem="${1%.lua}"; stem="${stem%.conf}"
    printf '%s\n' "$stem"
}

current_animation() {
    if [[ -s "$ANIMATION_STATE" ]]; then
        cat "$ANIMATION_STATE"
    else
        printf '%s\n' "LimeFrenzy.lua"
    fi
}

list_animations() {
    local current file base desc label
    current="$(current_animation)"

    [[ -d "$ANIMATIONS_DIR" ]] || return 0

    while IFS= read -r file; do
        base="$(basename "$file")"
        [[ "$base" == *.lua ]] || continue
        desc="$(description_for "$base")"
        label="$(label_for "$base")"
        # filename|label|description|current
        printf '%s|%s|%s|%s\n' "$base" "$label" "$desc" "$([[ "$base" == "$current" ]] && printf true || printf false)"
    done < <(find "$ANIMATIONS_DIR" -maxdepth 1 -type f -name '*.lua' -printf '%f\n' | sort -f | sed "s#^#$ANIMATIONS_DIR/#")
}

apply_animation() {
    local selected_file="$1"
    local preset="$ANIMATIONS_DIR/$selected_file"

    # Accept only bare .lua filenames; never allow path traversal from QML/user input.
    if [[ "$selected_file" != "$(basename "$selected_file")" || "$selected_file" != *.lua ]]; then
        echo "Error: Invalid animation filename: $selected_file" >&2
        notify_user "Animation Error" "Invalid animation selection" -i dialog-error
        exit 1
    fi

    if [[ ! -f "$preset" ]]; then
        echo "Error: Animation file not found: $preset" >&2
        notify_user "Animation Error" "Animation file not found: $selected_file" -i dialog-error
        exit 1
    fi

    mkdir -p "$(dirname "$ANIMATION_LUA")" "$(dirname "$ANIMATION_STATE")"

    # Preset is already valid Lua -> copy it over the active file atomically and
    # record the chosen name for the Control Center to display.
    local tmp
    tmp="$(mktemp)"
    cp "$preset" "$tmp"
    mv "$tmp" "$ANIMATION_LUA"
    printf '%s\n' "$selected_file" > "$ANIMATION_STATE"

    hyprctl reload >/dev/null 2>&1 || true

    notify_user "Animation Updated" "Changed to: $(label_for "$selected_file")" -i preferences-desktop-effects
    printf 'ok|%s\n' "$selected_file"
}

usage() {
    cat <<EOF
Usage: ${0##*/} COMMAND [animation.lua]

Commands:
  list                 Print filename|label|description|current rows for .lua presets
  current              Print the current animation filename
  apply animation.lua  Copy one Lua animation preset into animations.lua and reload Hyprland
EOF
}

case "${1:-list}" in
    list)    list_animations ;;
    current) current_animation ;;
    apply)   [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; apply_animation "$2" ;;
    *)       usage >&2; exit 2 ;;
esac
