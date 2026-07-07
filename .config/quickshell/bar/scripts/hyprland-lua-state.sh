#!/bin/bash
# HyprCandyPlus Hyprland Lua mutable state helper.
# Stores values in ~/.config/hyprcandy/hyprcandy-bar.conf for Quickshell
# and renders ~/.config/hypr/hyprviz-state.lua for Hyprland 0.55+ Lua configs.

set -euo pipefail

STATE_CONF="${HYPRCANDY_HYPR_STATE_CONF:-$HOME/.config/hyprcandy/hyprcandy-bar.conf}"
LUA_STATE="${HYPRCANDY_HYPR_LUA_STATE:-$HOME/.config/hypr/hyprviz-state.lua}"
LUA_BASE="${HYPRCANDY_HYPR_BASE_LUA:-$HOME/.config/hypr/hyprviz.lua}"
LEGACY_CONF="${HYPRCANDY_HYPR_LEGACY_CONF:-$HOME/.config/hypr/hyprviz.conf}"

mkdir -p "$(dirname "$STATE_CONF")" "$(dirname "$LUA_STATE")"

ensure_section() {
    touch "$STATE_CONF"
    grep -q '^\[hyprland\]' "$STATE_CONF" 2>/dev/null || printf '\n[hyprland]\n' >> "$STATE_CONF"
}

read_state() {
    local key="$1"
    awk -F= -v key="$key" '
        /^\[hyprland\]/{s=1; next}
        /^\[/{s=0}
        s && $1==key {v=substr($0, index($0,"=")+1)}
        END{if (v != "") print v}
    ' "$STATE_CONF" 2>/dev/null || true
}

write_state() {
    local key="$1" value="$2" tmp
    ensure_section
    tmp="$(mktemp)"
    awk -v key="$key" -v val="$value" '
        BEGIN{section=0; done=0}
        /^\[hyprland\]/{section=1; print; next}
        /^\[/{if(section && !done){print key "=" val; done=1}; section=0; print; next}
        section && $0 ~ "^" key "=" {if(!done){print key "=" val; done=1}; next}
        {print}
        END{if(section && !done) print key "=" val}
    ' "$STATE_CONF" > "$tmp"
    mv "$tmp" "$STATE_CONF"
}

num_or_empty() {
    local value="${1:-}"
    [[ "$value" =~ ^-?[0-9]+([.][0-9]+)?$ ]] && printf '%s\n' "$value"
}

clamp_int() {
    local value="$1" min="$2" max="$3" fallback="$4"
    value="$(printf '%s' "$value" | grep -oE '^-?[0-9]+' | head -1 || true)"
    [ -n "$value" ] || value="$fallback"
    [ "$value" -lt "$min" ] 2>/dev/null && value="$min"
    [ "$value" -gt "$max" ] 2>/dev/null && value="$max"
    printf '%s\n' "$value"
}

clamp_float() {
    local value="$1" min="$2" max="$3" fallback="$4"
    value="$(printf '%s' "$value" | grep -oE '^[0-9]+([.][0-9]+)?' | head -1 || true)"
    [ -n "$value" ] || value="$fallback"
    awk -v v="$value" -v min="$min" -v max="$max" 'BEGIN{if(v<min)v=min;if(v>max)v=max;printf "%.2f", v}'
}

legacy_default() {
    local key="$1" value=""
    case "$key" in
        opacity)
            value="$(grep -m1 'active_opacity[[:space:]]*=' "$LEGACY_CONF" 2>/dev/null | grep -oE '[0-9]+([.][0-9]+)?' | head -1 || true)"
            printf '%s\n' "${value:-1.00}" ;;
        blur_size)
            value="$(awk '/blur[[:space:]]*= *\{|blur[[:space:]]*\{/{b=1;next} b&&/}/{b=0} b&&/size[[:space:]]*=/{match($0,/[0-9]+/);print substr($0,RSTART,RLENGTH);exit}' "$LEGACY_CONF" 2>/dev/null || true)"
            printf '%s\n' "${value:-6}" ;;
        blur_passes)
            value="$(awk '/blur[[:space:]]*= *\{|blur[[:space:]]*\{/{b=1;next} b&&/}/{b=0} b&&/passes[[:space:]]*=/{match($0,/[0-9]+/);print substr($0,RSTART,RLENGTH);exit}' "$LEGACY_CONF" 2>/dev/null || true)"
            printf '%s\n' "${value:-2}" ;;
        gaps_in)
            value="$(grep -m1 'gaps_in[[:space:]]*=' "$LEGACY_CONF" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
            printf '%s\n' "${value:-4}" ;;
        gaps_out)
            value="$(grep -m1 'gaps_out[[:space:]]*=' "$LEGACY_CONF" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
            printf '%s\n' "${value:-12}" ;;
        border_size)
            value="$(grep -m1 'border_size[[:space:]]*=' "$LEGACY_CONF" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
            printf '%s\n' "${value:-3}" ;;
        rounding)
            value="$(grep -m1 'rounding[[:space:]]*=' "$LEGACY_CONF" 2>/dev/null | grep -oE '[0-9]+' | head -1 || true)"
            printf '%s\n' "${value:-8}" ;;
        active_border)
            value="$(awk -F= '/col\.active_border[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$LEGACY_CONF" 2>/dev/null || true)"
            printf '%s\n' "${value:-\$inverse_primary}" ;;
        inactive_border)
            value="$(awk -F= '/col\.inactive_border[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit}' "$LEGACY_CONF" 2>/dev/null || true)"
            printf '%s\n' "${value:-\$background}" ;;
        kb_layout)
            value="$(grep -m1 'kb_layout[[:space:]]*=' "$LEGACY_CONF" 2>/dev/null | sed 's/.*= *//' | awk '{print $1}' || true)"
            printf '%s\n' "${value:-us}" ;;
        xray) echo "false" ;;
        *) echo "" ;;
    esac
}

get_value() {
    local key="$1" value
    value="$(read_state "$key")"
    [ -n "$value" ] || value="$(legacy_default "$key")"
    printf '%s\n' "$value"
}

lua_string() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

color_expr() {
    local value="$1" name
    value="$(printf '%s' "$value" | xargs)"
    if [[ "$value" =~ ^\$[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        name="${value#\$}"
        printf '%s' "$name"
    elif [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        printf '%s' "$value"
    else
        printf '"%s"' "$(lua_string "$value")"
    fi
}

emit_num_key() {
    local indent="$1" name="$2" value="$3"
    if [ -n "$value" ]; then
        printf '%s%s = %s,\n' "$indent" "$name" "$value"
    fi
    return 0
}

render_lua() {
    local opacity blur_size blur_passes gaps_in gaps_out border_size rounding active_border inactive_border kb_layout xray
    opacity="$(read_state opacity)"
    blur_size="$(read_state blur_size)"
    blur_passes="$(read_state blur_passes)"
    gaps_in="$(read_state gaps_in)"
    gaps_out="$(read_state gaps_out)"
    border_size="$(read_state border_size)"
    rounding="$(read_state rounding)"
    active_border="$(read_state active_border)"
    inactive_border="$(read_state inactive_border)"
    kb_layout="$(read_state kb_layout)"
    xray="$(read_state xray)"

    {
        printf '%s\n' '-- HyprCandyPlus mutable Hyprland Lua state.'
        printf '%s\n' '-- Generated by Quickshell Control Center and helper scripts; edit sliders instead of this file.'
        printf '%s\n\n' '-- Loaded after hyprviz.lua, so keys below override migrated defaults.'
        printf '%s\n' 'hl.config({'
        printf '%s\n' '    general = {'
        emit_num_key '        ' gaps_in "$gaps_in"
        emit_num_key '        ' gaps_out "$gaps_out"
        emit_num_key '        ' border_size "$border_size"
        if [ -n "$active_border" ] || [ -n "$inactive_border" ]; then
            printf '%s\n' '        col = {'
            [ -n "$active_border" ] && printf '            active_border = %s,\n' "$(color_expr "$active_border")"
            [ -n "$inactive_border" ] && printf '            inactive_border = %s,\n' "$(color_expr "$inactive_border")"
            printf '%s\n' '        },'
        fi
        printf '%s\n' '    },'
        printf '%s\n' '    decoration = {'
        emit_num_key '        ' rounding "$rounding"
        if [ -n "$opacity" ]; then
            printf '        active_opacity = %s,\n' "$opacity"
            printf '        inactive_opacity = %s,\n' "$opacity"
        fi
        printf '%s\n' '        blur = {'
        emit_num_key '            ' size "$blur_size"
        emit_num_key '            ' passes "$blur_passes"
        if [ -n "$xray" ]; then
            printf '            xray = %s,\n' "$xray"
        fi
        printf '%s\n' '        },'
        printf '%s\n' '    },'
        if [ -n "$kb_layout" ]; then
            printf '%s\n' '    input = {'
            printf '        kb_layout = "%s",\n' "$(lua_string "$kb_layout")"
            printf '%s\n' '    },'
        fi
        printf '%s\n' '})'
        printf '%s\n' ''
        printf '%s\n' 'hl.layer_rule({'
        printf '%s\n' '    match = {'
        printf '%s\n' '        namespace = ".*",'
        printf '%s\n' '    },'
        if [ -n "$xray" ]; then
            printf '    xray = %s,\n' "$xray"
        fi
        printf '%s\n' '})'
        printf '%s\n' ''
        printf '%s\n' 'return true'
    } > "$LUA_STATE"
}

set_key() {
    local key="$1" value="$2"
    write_state "$key" "$value"
    render_lua
}

adjust_key() {
    local key="$1" delta="$2" min="$3" max="$4" fallback="$5" mode="${6:-int}" current next
    current="$(get_value "$key")"
    [ -n "$current" ] || current="$fallback"
    if [ "$mode" = "float" ]; then
        next="$(awk -v v="$current" -v d="$delta" -v min="$min" -v max="$max" 'BEGIN{r=v+d;if(r<min)r=min;if(r>max)r=max;printf "%.2f", r}')"
    else
        next=$(( ${current%.*} + delta ))
        [ "$next" -lt "$min" ] && next="$min"
        [ "$next" -gt "$max" ] && next="$max"
    fi
    set_key "$key" "$next"
    printf '%s\n' "$next"
}

case "${1:-}" in
    render) render_lua ;;
    get) get_value "${2:?missing key}" ;;
    set)
        key="${2:?missing key}"; value="${3:?missing value}"
        case "$key" in
            opacity) value="$(clamp_float "$value" 0 1 1)" ;;
            blur_size) value="$(clamp_int "$value" 0 50 6)" ;;
            blur_passes) value="$(clamp_int "$value" 0 10 2)" ;;
            gaps_in|gaps_out) value="$(clamp_int "$value" 0 100 0)" ;;
            border_size) value="$(clamp_int "$value" 0 20 3)" ;;
            rounding) value="$(clamp_int "$value" 0 50 8)" ;;
            xray) [[ "$value" == "true" || "$value" == "1" || "$value" == "on" ]] && value="true" || value="false" ;;
        esac
        set_key "$key" "$value"
        printf '%s\n' "$value"
        ;;
    adjust)
        key="${2:?missing key}"; delta="${3:?missing delta}"
        case "$key" in
            opacity) adjust_key opacity "$delta" 0 1 1 float ;;
            blur_size) adjust_key blur_size "$delta" 0 50 6 int ;;
            blur_passes) adjust_key blur_passes "$delta" 0 10 2 int ;;
            gaps_in) adjust_key gaps_in "$delta" 0 100 4 int ;;
            gaps_out) adjust_key gaps_out "$delta" 0 100 12 int ;;
            border_size) adjust_key border_size "$delta" 0 20 3 int ;;
            rounding) adjust_key rounding "$delta" 0 50 8 int ;;
            *) echo "Unknown adjustable key: $key" >&2; exit 2 ;;
        esac
        ;;
    *)
        echo "Usage: $0 render|get KEY|set KEY VALUE|adjust KEY DELTA" >&2
        exit 2
        ;;
esac
