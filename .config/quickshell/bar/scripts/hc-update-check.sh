#!/usr/bin/env bash
# hc-update-check.sh
# Checks for HyprCandy Plus dotfile updates and maintains a persistent state
# file so update availability survives bar restarts and session restarts.
#
# State file: ~/.config/hyprcandy/hc-update-state
#   - Written (with tooltip text) only when new updates are detected
#   - Deleted only by Candy_Update.sh / _hcStateClearProc after an update is applied
#
# Outputs one JSON line:
#   {"hasUpdates": true|false, "tooltip": "...", "noStore": true|false}

HC_STORE="$HOME/.HCUpdates"
STATE_FILE="$HOME/.config/hyprcandy/hc-update-state"

emit() {
    local has="$1" tip="$2" nostore="${3:-false}"
    tip="${tip//\"/\\\"}"
    echo "{\"hasUpdates\":${has},\"tooltip\":\"${tip}\",\"noStore\":${nostore}}"
}

# ── If state file already exists, updates are pending application ─────────────
if [ -f "$STATE_FILE" ]; then
    saved_tip=$(cat "$STATE_FILE")
    [ -z "$saved_tip" ] && saved_tip="HC+ files changed — 󰇚 to sync."
    emit "true" "${saved_tip}" "false"
    exit 0
fi

# ── Store folder absent or not a git repo → needs setup ───────────────────────
if [ ! -d "$HC_STORE" ] || [ ! -d "$HC_STORE/.git" ]; then
    tip="HC+ store not found — 󰇚 to set up and sync dotfiles."
    echo "$tip" > "$STATE_FILE"
    emit "true" "$tip" "true"
    exit 0
fi

# ── Store present and is a git repo — pull and check for changes ──────────────
pull_out=$(git -C "$HC_STORE" pull 2>&1)
pull_exit=$?

if [ $pull_exit -ne 0 ]; then
    emit "false" "HC+ check failed: ${pull_out}" "false"
    exit 0
fi

if echo "$pull_out" | grep -q "Already up to date"; then
    emit "false" "HyprCandy Plus is up to date" "false"
else
    # New changes were pulled — write state so update button stays visible until applied
    tip="HC+ files changed — 󰇚 to sync."
    echo "$tip" > "$STATE_FILE"
    notify-send " HC+ Update" "New updates available"
    emit "true" "$tip" "false"
fi
