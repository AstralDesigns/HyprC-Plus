#!/usr/bin/env bash
# license-verify.sh — HyprCandy+ Gumroad licence verification
# Usage: license-verify.sh <license_key> [increment]
#   increment: "true" (first activation) or "false" (background re-check)
#
# Replace YOUR_GUMROAD_PRODUCT_ID below with the product_id from your
# Gumroad product settings page (Settings → License Keys → Product ID).
# This keeps the ID out of the QML source.

PRODUCT_ID="qyLXH3bCRFgiaFrjVWwIjQ=="
LICENSE_KEY="${1:-}"
INCREMENT="${2:-false}"

if [[ -z "$LICENSE_KEY" ]]; then
    echo '{"success":false,"message":"No license key provided"}'
    exit 1
fi

curl -s --max-time 10 \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "product_id=${PRODUCT_ID}&license_key=${LICENSE_KEY}&increment_uses_count=${INCREMENT}" \
    "https://api.gumroad.com/v2/licenses/verify" \
    || echo '{"success":false,"message":"Network error — check your connection"}'
