#!/usr/bin/env bash
set -euo pipefail

source "$HOME/.config/hyprcandy/scripts/qs-theme-env.sh"
qs_export_theme_env

# Old working behavior: toggle the control center *inside the running bar*
# via Quickshell IPC. This avoids starting a separate control center instance
# (which can create an invisible focus-grabbing layer if misconfigured).
#
# If bar is not running, start it and then toggle.

if qs ipc -c bar --newest --any-display call bar toggleControlCenter >/dev/null 2>&1; then
  exit 0
fi

nohup "$HOME/.config/hyprcandy/scripts/bar.sh" >/dev/null 2>&1 &
sleep 0.4
qs ipc -c bar --newest --any-display call bar toggleControlCenter >/dev/null 2>&1 || true

