#!/usr/bin/env bash
# license-verify.sh — HyprCandy+ Gumroad licence verification
# Usage: license-verify.sh <license_key> [increment]
#   increment: "true" (first activation) or "false" (background re-check)
#
# Replace YOUR_GUMROAD_PRODUCT_ID below with the product_id from your
# Gumroad product settings page (Settings → License Keys → Product ID).
# This keeps the ID out of the QML source.

PRODUCT_ID="YOUR_GUMROAD_PRODUCT_ID"
LICENSE_KEY="${1:-}"
INCREMENT="${2:-false}"

if [[ -z "$LICENSE_KEY" ]]; then
    echo '{"success":false,"message":"No license key provided"}'
    exit 1
fi

curl -sf --max-time 10 \
    -X POST \
    --data-urlencode "product_id=${PRODUCT_ID}" \
    --data-urlencode "license_key=${LICENSE_KEY}" \
    --data-urlencode "increment_uses_count=${INCREMENT}" \
    "https://api.gumroad.com/v2/licenses/verify" \
    2>/dev/null \
    || echo '{"success":false,"message":"Network error — check your connection"}'
