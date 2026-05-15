#!/usr/bin/env bash
# license-deactivate.sh — HyprCandy+ Gumroad licence deactivation
# Usage: license-deactivate.sh <license_key>

PRODUCT_ID="qyLXH3bCRFgiaFrjVWwIjQ=="
LICENSE_KEY="${1:-}"

if [[ -z "$LICENSE_KEY" ]]; then
    echo '{"success":false,"message":"No license key provided"}'
    exit 1
fi

# Decrement uses count via Gumroad API
curl -s --max-time 10 \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "product_id=${PRODUCT_ID}&license_key=${LICENSE_KEY}" \
    "https://api.gumroad.com/v2/licenses/decrement_uses_count" \
    || echo '{"success":false,"message":"Network error — check your connection"}'
