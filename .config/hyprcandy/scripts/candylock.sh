#!/usr/bin/env bash
# candylock.sh — launch the unified candylock
# Use this as your lock command in swayidle / Hyprland bindl

set -euo pipefail

CONFDIR="$HOME/.config/quickshell"
source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# Rebuild pam_auth if source is newer than binary or binary missing
if [ "$CONFDIR/candylock/pam_auth.c" -nt "$CONFDIR/candylock/pam_auth" ] 2>/dev/null || \
   [ ! -x "$CONFDIR/candylock/pam_auth" ]; then
    gcc -O2 -o "$CONFDIR/candylock/pam_auth" "$CONFDIR/candylock/pam_auth.c" -lpam
fi

# Kill any stale instance
pkill -f "qs -c candylock$" 2>/dev/null || true
sleep 0.15

# Start (blocks until unlocked)
qs -c candylock
