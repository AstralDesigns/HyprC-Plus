#!/usr/bin/env bash
# wallhaven-download.sh <url> <dest>
URL="$1"
DEST="$2"

if [ -z "$URL" ] || [ -z "$DEST" ]; then
    echo "Usage: $0 <url> <dest>" >&2
    exit 1
fi

mkdir -p "$(dirname "$DEST")"

if curl --silent --fail --location -A "Mozilla/5.0 (X11; Linux x86_64)" --output "$DEST" "$URL"; then
    notify-send -i emblem-photos "Wallhaven" "Downloaded: $(basename "$DEST")" 2>/dev/null
    exit 0
else
    rm -f "$DEST"
    notify-send -u critical "Wallhaven" "Download failed: $(basename "$DEST")" 2>/dev/null
    exit 1
fi
