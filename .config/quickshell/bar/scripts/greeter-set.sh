#!/bin/bash
# HyprCandy greeter setter — single root-side entry point for SDDM theme
# switching and theme.conf key edits (invoked as: sudo -n greeter-set.sh ...).
#
#   greeter-set.sh current <theme-id>          activate a theme (conf.d + symlinks)
#   greeter-set.sh set <key> <value> [state]   edit active theme's theme.conf
#   greeter-set.sh get <key>                   print active theme's value
#   greeter-set.sh active                      print active theme id
#   greeter-set.sh permit                      let the sddm user traverse $HOME
#
# Preserves the quoted/unquoted format of the edited line (sddm's own IniConf
# keeps quotes verbatim, so quoted values must stay quoted).
# shellcheck disable=SC2016
set -u

CONF_DIR="/etc/sddm.conf.d"
CONF="$CONF_DIR/hyprcandy.conf"
LEGACY_CONF="$CONF_DIR/sugar-candy.conf"
SUDO_HOME="${HC_GREETER_HOME:-$(getent passwd "${SUDO_UID:-$(id -u)}" | cut -d: -f6)}"
GT_DIR="$SUDO_HOME/.hyprcandy/Greeter/themes"
STATE_DIR="$SUDO_HOME/.config/hyprcandy"

conf_current() {
    local f="" raw=""
    for f in "$CONF" "$LEGACY_CONF"; do
        [ -f "$f" ] || continue
        raw=$(sed -n 's/^Current=//p' "$f" | head -1)
        [ -n "$raw" ] && break
    done
    # strip surrounding quotes and whitespace
    raw=${raw#\"}; raw=${raw%\"}; raw=${raw%\'}; raw=${raw#\'}
    printf '%s' "$(printf '%s' "$raw" | tr -d '[:space:]')"
}

active_theme_dir() {
    local id
    id=$(conf_current)
    [ -n "$id" ] || { echo ""; return; }
    # prefer the live tree: /usr/share/sddm/themes/<id> (symlink or real dir)
    if [ -d "/usr/share/sddm/themes/$id" ]; then
        echo "/usr/share/sddm/themes/$id"
    elif [ -d "$GT_DIR/$id" ]; then
        echo "$GT_DIR/$id"
    else
        echo ""
    fi
}

repair_links() {
    [ -d "$GT_DIR" ] || return 0
    local th id
    for th in "$GT_DIR"/*/; do
        [ -d "$th" ] || continue
        id=$(basename "$th")
        dst="/usr/share/sddm/themes/$id"
        # ln can't replace a pre-existing real directory (a stale copy left by an
        # older installer), which would make SDDM keep reading the old theme. Drop
        # it first so the symlink to the live dotfile tree can take its place.
        [ -d "$dst" ] && [ ! -L "$dst" ] && rm -rf "$dst"
        ln -sfn "${th%/}" "$dst"
    done
    # drop dangling hyprcandy links (theme dir was removed)
    for th in /usr/share/sddm/themes/*/; do
        [ -L "${th%/}" ] || continue
        [ -e "${th%/}" ] || rm -f "${th%/}"
    done
    return 0
}

seed_conf() {
    mkdir -p "$CONF_DIR"
    cat > "$CONF" << EOF
[Theme]
Current=${1:-hyprcandy-1}
CursorTheme=geared-brass-32x
CursorSize=18
EOF
    chmod 644 "$CONF"
}

set_key() {
    local file="$1" key="$2" value="$3"
    local line="" q=""
    grep -q "^${key}=" "$file" 2>/dev/null && line=$(grep "^${key}=" "$file" | head -1)
    case "$line" in
        "${key}= \""*'"' | "${key}=\""*'"') q=1 ;;
        *) q=0 ;;
    esac
    local new
    if [ "$q" = 1 ]; then
        new="${key}=\"${value}\""
    else
        new="${key}=${value}"
    fi
    local tmp
    tmp=$(mktemp)
    if [ -n "$line" ]; then
        awk -v old="$line" -v new="$new" '{ if ($0 == old && !done) { print new; done=1 } else print }' \
            "$file" > "$tmp"
    else
        cp "$file" "$tmp" 2>/dev/null || : > "$tmp"
        printf '%s\n' "$new" >> "$tmp"
    fi
    # keep file mode; hand ownership back to the invoking user for home files
    tee "$file" > /dev/null < "$tmp"
    rm -f "$tmp"
    case "$file" in
        "$SUDO_HOME"/*) chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$file" 2>/dev/null || true ;;
    esac
}

cmd="${1:-}"
shift || true

case "$cmd" in
    active)
        conf_current
        ;;
    current)
        id="${1:-}"
        [ -n "$id" ] || exit 1
        case "$id" in
            *[!A-Za-z0-9._-]*) echo "invalid theme id" >&2; exit 1 ;;
        esac
        [ -d "/usr/share/sddm/themes/$id" ] || [ -d "$GT_DIR/$id" ] || {
            echo "theme not found: $id" >&2; exit 1
        }
        mkdir -p "$CONF_DIR"
        if [ -f "$CONF" ] && grep -q '^Current=' "$CONF"; then
            set_key "$CONF" Current "$id"
        elif [ -f "$LEGACY_CONF" ] && grep -q '^Current=' "$LEGACY_CONF"; then
            # migrate legacy file into the new one, then write
            cur=$(conf_current)
            seed_conf "${cur:-hyprcandy-1}"
            set_key "$CONF" Current "$id"
        else
            seed_conf "$id"
        fi
        repair_links
        ;;
    set)
        key="${1:-}"; value="${2-}"; state="${3:-}"
        [ -n "$key" ] || exit 1
        tdir=$(active_theme_dir)
        [ -n "$tdir" ] || { echo "no active theme" >&2; exit 1; }
        tconf="$tdir/theme.conf"
        [ -f "$tconf" ] || : > "$tconf"
        set_key "$tconf" "$key" "$value"
        if [ -n "$state" ]; then
            mkdir -p "$STATE_DIR"
            printf '%s\n' "$value" > "$STATE_DIR/$state"
            chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$STATE_DIR/$state" 2>/dev/null || true
        fi
        # wallpaper edits refresh the shared runtime copies
        if [ "$key" = "Background" ]; then
            sync="$(dirname "$(readlink -f "$0")")/greeter-sync.sh"
            [ -x "$sync" ] && "$sync" || true
        fi
        ;;
    get)
        key="${1:-}"
        tdir=$(active_theme_dir)
        [ -n "$tdir" ] || exit 1
        grep "^${key}=" "$tdir/theme.conf" 2>/dev/null | head -1 | \
            sed -e 's/^[^=]*=//' -e 's/^"//' -e 's/"$//' -e "s/^'//" -e "s/'$//"
        ;;
    permit)
        # traverse-only ACL so the greeter can read symlinked theme files
        setfacl -m u:sddm:--x "$SUDO_HOME" 2>/dev/null || true
        ;;
    *)
        echo "usage: greeter-set.sh {current <id>|set <key> <value> [state]|get <key>|active|permit}" >&2
        exit 2
        ;;
esac
