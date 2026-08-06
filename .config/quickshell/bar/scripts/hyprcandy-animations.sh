#!/usr/bin/env bash
# HyprCandy control-center animation preset helper.
# Lists and applies ~/.config/hypr/conf/animations/*.conf presets without rofi.

set -euo pipefail

ANIMATIONS_DIR="${HYPRCANDY_ANIMATIONS_DIR:-$HOME/.config/hypr/conf/animations}"
ANIMATION_LUA="${HYPRCANDY_ANIMATION_LUA:-$HOME/.config/hypr/animations.lua}"
ANIMATION_STATE="${HYPRCANDY_ANIMATION_STATE:-$HOME/.config/hypr/animations-current}"

notify_user() {
    command -v notify-send >/dev/null 2>&1 && notify-send "$@" || true
}

# Canonical descriptions retained from the old rofi animations.sh module.
description_for() {
    case "$1" in
        classic.conf)     printf '%s\n' "Classic smooth animations" ;;
        diablo-1.conf)    printf '%s\n' "Diablo style variant 1" ;;
        diablo-2.conf)    printf '%s\n' "Diablo style variant 2" ;;
        disable.conf)     printf '%s\n' "Disable all animations" ;;
        dynamic.conf)     printf '%s\n' "Dynamic responsive animations" ;;
        end4.conf)        printf '%s\n' "End4 animation preset" ;;
        fast.conf)        printf '%s\n' "Fast and snappy animations" ;;
        high.conf)        printf '%s\n' "High performance animations" ;;
        ja.conf)          printf '%s\n' "Smooth transitions" ;;
        LimeFrenzy.conf)  printf '%s\n' "Lime Frenzy energetic style" ;;
        me-1.conf)        printf '%s\n' "Custom ME variant 1" ;;
        me-2.conf)        printf '%s\n' "Custom ME variant 2" ;;
        minimal-1.conf)   printf '%s\n' "Minimal animations variant 1" ;;
        minimal-2.conf)   printf '%s\n' "Minimal animations variant 2" ;;
        moving.conf)      printf '%s\n' "Moving elements focus" ;;
        optimized.conf)   printf '%s\n' "Optimized for performance" ;;
        silent.conf)      printf '%s\n' "Silent minimal animations" ;;
        standard.conf)    printf '%s\n' "Standard Hyprland animations" ;;
        theme.conf)       printf '%s\n' "Theme-based animations" ;;
        vertical.conf)    printf '%s\n' "Vertical workspace switching" ;;
        *)
            local stem pretty
            stem="${1%.conf}"
            pretty="${stem//-/ }"
            pretty="${pretty//_/ }"
            printf '%s\n' "${pretty^} animation preset"
            ;;
    esac
}

label_for() {
    local stem="$1"
    stem="${stem%.conf}"
    printf '%s\n' "$stem"
}

current_animation() {
    if [[ -s "$ANIMATION_STATE" ]]; then
        cat "$ANIMATION_STATE"
    else
        printf '%s\n' "LimeFrenzy.conf"
    fi
}

list_animations() {
    local current file base desc label
    current="$(current_animation)"

    [[ -d "$ANIMATIONS_DIR" ]] || return 0

    while IFS= read -r file; do
        base="$(basename "$file")"
        [[ "$base" == *.conf ]] || continue
        desc="$(description_for "$base")"
        label="$(label_for "$base")"
        # filename|label|description|current
        printf '%s|%s|%s|%s\n' "$base" "$label" "$desc" "$([[ "$base" == "$current" ]] && printf true || printf false)"
    done < <(find "$ANIMATIONS_DIR" -maxdepth 1 -type f -name '*.conf' -printf '%f\n' | sort -f | sed "s#^#$ANIMATIONS_DIR/#")
}

write_animation_lua() {
    local selected_file="$1"
    local preset="$ANIMATIONS_DIR/$selected_file"
    local tmp

    # Accept only bare .conf filenames; never allow path traversal from QML/user input.
    if [[ "$selected_file" != "$(basename "$selected_file")" || "$selected_file" != *.conf ]]; then
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
    tmp="$(mktemp)"

    {
        echo "-- HyprCandy selected animation preset."
        echo "-- Generated from ~/.config/hypr/conf/animations/$selected_file by hyprcandy-animations.sh."
        echo "-- This file is loaded by hyprland.lua after hyprviz.lua."
        echo
    } > "$tmp"

    awk '
        /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
        /^[[:space:]]*animations[[:space:]]*\{/ { in_block=1; next }
        in_block && /^[[:space:]]*}/ { in_block=0; next }
        in_block {
            sub(/^[[:space:]]*/, "")
            if ($0 ~ /^enabled[[:space:]]*=/) {
                v=$0; sub(/^enabled[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v)
                printf "hl.config({ animations = { enabled = %s } })\n", (v=="1"?"true":"false")
            } else if ($0 ~ /^bezier[[:space:]]*=/) {
                v=$0; sub(/^bezier[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v)
                split(v, parts, ",")
                name = parts[1]; sub(/^[[:space:]]*/, "", name); sub(/[[:space:]]*$/, "", name)
                p1 = parts[2]; sub(/^[[:space:]]*/, "", p1); sub(/[[:space:]]*$/, "", p1)
                p2 = parts[3]; sub(/^[[:space:]]*/, "", p2); sub(/[[:space:]]*$/, "", p2)
                p3 = parts[4]; sub(/^[[:space:]]*/, "", p3); sub(/[[:space:]]*$/, "", p3)
                p4 = parts[5]; sub(/^[[:space:]]*/, "", p4); sub(/[[:space:]]*$/, "", p4)
                printf "hl.curve(\"%s\", { type = \"bezier\", points = { {%s, %s}, {%s, %s} } })\n", name, p1, p2, p3, p4
            } else if ($0 ~ /^animation[[:space:]]*=/) {
                v=$0; sub(/^animation[[:space:]]*=[[:space:]]*/, "", v); gsub(/[[:space:]]+$/, "", v)
                split(v, parts, ",")
                name = parts[1]; sub(/^[[:space:]]*/, "", name); sub(/[[:space:]]*$/, "", name)
                en = parts[2]; sub(/^[[:space:]]*/, "", en); sub(/[[:space:]]*$/, "", en)
                spd = parts[3]; sub(/^[[:space:]]*/, "", spd); sub(/[[:space:]]*$/, "", spd)
                crv = parts[4]; sub(/^[[:space:]]*/, "", crv); sub(/[[:space:]]*$/, "", crv)
                stl = parts[5]; sub(/^[[:space:]]*/, "", stl); sub(/[[:space:]]*$/, "", stl)
                printf "hl.animation({ leaf = \"%s\", enabled = %s, speed = %s, bezier = \"%s\"%s })\n", name, (en=="1"?"true":"false"), spd, crv, (stl!=""?", style = \"" stl "\"":"")
            }
        }
    ' "$preset" >> "$tmp"

    {
        echo
        echo "return true"
    } >> "$tmp"

    mv "$tmp" "$ANIMATION_LUA"
    printf '%s\n' "$selected_file" > "$ANIMATION_STATE"
}

apply_animation() {
    local selected_file="$1"
    write_animation_lua "$selected_file"
    notify_user "Animation Updated" "Changed to: $selected_file" -i preferences-desktop-effects
    hyprctl reload >/dev/null 2>&1 || true

    case "$selected_file" in
        disable.conf)   notify_user "Animations Disabled" "All animations have been turned off" -i dialog-information ;;
        fast.conf)      notify_user "Fast Animations" "Quick and snappy animations enabled" -i preferences-desktop-effects ;;
        minimal-*.conf) notify_user "Minimal Animations" "Subtle and clean animations enabled" -i preferences-desktop-effects ;;
        dynamic.conf)   notify_user "Dynamic Animations" "Responsive and adaptive animations enabled" -i preferences-desktop-effects ;;
        *)              notify_user "Animation Changed" "New animation profile loaded: ${selected_file%.conf}" -i preferences-desktop-effects ;;
    esac
    printf 'ok|%s\n' "$selected_file"
}

usage() {
    cat <<EOF
Usage: ${0##*/} COMMAND [animation.conf]

Commands:
  list                 Print filename|label|description|current rows for .conf presets
  current              Print the current animation filename
  apply animation.conf Apply one animation preset and reload Hyprland
EOF
}

case "${1:-list}" in
    list)    list_animations ;;
    current) current_animation ;;
    apply)   [[ -n "${2:-}" ]] || { usage >&2; exit 2; }; apply_animation "$2" ;;
    *)       usage >&2; exit 2 ;;
esac
