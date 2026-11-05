#!/usr/bin/env bash
# HyprCandy lockscreen theme selector. Lists ~/.config/quickshell/lockscreens/*/
# folders and records the active one in lockscreens-current (read by candylock.sh
# and hypridle to launch `qs -p .../lockscreens/<theme>`).
set -euo pipefail
LOCKDIR="${HYPRCANDY_LOCKSCREENS_DIR:-$HOME/.config/quickshell/lockscreens}"
CURRENT_FILE="$LOCKDIR/lockscreens-current"

current_theme() {
    if [[ -s "$CURRENT_FILE" ]]; then cat "$CURRENT_FILE"; else printf 'candylock\n'; fi
}

list() {
    local cur; cur="$(current_theme)"
    [[ -d "$LOCKDIR" ]] || return 0
    for d in "$LOCKDIR"/*/; do
        [[ -d "$d" ]] || continue
        local base; base="$(basename "$d")"
        [[ "$base" == .* ]] && continue
        # name|label|current
        printf '%s|%s|%s\n' "$base" "$base" \
            "$([[ "$base" == "$cur" ]] && printf true || printf false)"
    done
}

apply() {
    local name="$1"
    if [[ "$name" != "$(basename "$name")" || -z "$name" ]]; then
        echo "Error: invalid lockscreen name: $name" >&2; exit 1
    fi
    if [[ ! -d "$LOCKDIR/$name" ]]; then
        echo "Error: lockscreen theme not found: $name" >&2; exit 1
    fi
    mkdir -p "$LOCKDIR"
    printf '%s\n' "$name" > "$CURRENT_FILE"
    printf 'ok|%s\n' "$name"
}

case "${1:-list}" in
    list)    list ;;
    current) current_theme ;;
    apply)   [[ -n "${2:-}" ]] || { echo "usage: apply <name>" >&2; exit 2; }; apply "$2" ;;
    *)       echo "usage: ${0##*/} list|current|apply <name>" >&2; exit 2 ;;
esac
