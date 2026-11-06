#!/usr/bin/env bash
# wallpaper-bing.sh — fetch & apply today's Bing daily wallpaper.
#
# Idempotent per day: if today's image was already applied (same urlbase), it
# exits without re-downloading/re-applying. Safe to call on a repeating timer.
# Triggered by the bar's WallpaperBtn scheduler (the bar is always running) and
# immediately when the picker's Bing toggle is switched on.
set -uo pipefail

CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/hyprcandy/bing"
mkdir -p "$CACHE"
LAST_FILE="$CACHE/.last"
IMG="$CACHE/bing.jpg"
HERE="$(cd "$(dirname "$0")" && pwd)"
APPLY="$HERE/wallpaper-apply.sh"
RECOLOR="${XDG_CONFIG_HOME:-$HOME/.config}/hyprcandy/hooks/wallpaper_integration.sh"

API="https://www.bing.com/HPImageArchive.aspx?format=js&idx=0&n=1&mkt=en-US"
json=$(curl -fsSL --max-time 15 "$API") || { echo "bing: fetch failed" >&2; exit 1; }

# urlbase changes once per day (idempotency key); url is the full path WITH the
# required query params (&rf=...&pid=hp) — urlbase alone 404s.
urlbase=$(printf '%s' "$json" | grep -oP '"urlbase"\s*:\s*"\K[^"]+')
url=$(printf '%s' "$json" | grep -oP '"url"\s*:\s*"\K[^"]+')
[[ -z "$url" ]] && { echo "bing: no image in response" >&2; exit 1; }
key="${urlbase:-$url}"

# Already applied today? Nothing to do — unless --force (an explicit re-enable
# from the picker toggle should re-apply even if today's image is cached).
if [[ "${1:-}" != "--force" && -f "$LAST_FILE" && "$(cat "$LAST_FILE")" == "$key" ]]; then exit 0; fi

# Prefer UHD (swap the resolution token, keep the query), fall back to the default.
uhd="${url//_1920x1080.jpg/_UHD.jpg}"
ok=0
for u in "$uhd" "$url"; do
    if curl -fsSL --max-time 30 -o "$IMG" "https://www.bing.com${u}"; then
        [[ -s "$IMG" ]] && { ok=1; break; }
    fi
done
[[ $ok -eq 1 ]] || { echo "bing: download failed" >&2; exit 1; }

# Apply with the picker's transition defaults (wallpaper-apply.sh fills the rest).
bash "$APPLY" "$IMG" || { echo "bing: apply failed" >&2; exit 1; }

# Recolor the palette from the new wallpaper (same hook the bar recolor uses).
[[ -x "$RECOLOR" || -f "$RECOLOR" ]] && bash "$RECOLOR" >/dev/null 2>&1 || true

printf '%s' "$urlbase" > "$LAST_FILE"
echo "bing: applied https://www.bing.com${urlbase}_UHD.jpg"
