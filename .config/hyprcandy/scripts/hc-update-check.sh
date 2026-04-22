#!/usr/bin/env bash
# hc-update-check.sh
# Checks for HyprCandy Plus dotfile updates and maintains a persistent state
# file so update availability survives bar restarts and session restarts.
#
# State file: ~/.config/hyprcandy/hc-update-state
#   - Written (with tooltip text) only when updates are detected
#   - Never written when git pull says "Already up to date"
#   - Deleted only by the HC update process after a successful apply
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

write_state() {
    # Write tooltip to state file so the update is remembered across restarts
    echo "$1" > "$STATE_FILE"
}

# ── If state file already exists, updates were previously detected and not
#    yet applied — honour that regardless of what git pull says this scan
# ─────────────────────────────────────────────────────────────────────────────
if [ -f "$STATE_FILE" ]; then
    saved_tip=$(cat "$STATE_FILE")
    emit "true" "${saved_tip}" "false"
    # Still run the git pull in background to keep the store current so the
    # apply step gets the latest changes, but don't let its output affect state
    if [ -d "$HC_STORE/.git" ]; then
        git -C "$HC_STORE" pull 2>&1 > /dev/null &
    fi
    exit 0
fi

# ── No state file — evaluate current situation fresh ─────────────────────────

# Store folder absent or not a git repo → needs setup
if [ ! -d "$HC_STORE" ] || [ ! -d "$HC_STORE/.git" ]; then
    tip="HCPlus store not found — run Apply to set up and sync dotfiles."
    write_state "$tip"
    emit "true" "$tip" "true"
    exit 0
fi

# Store present and is a git repo — pull and check for changes
pull_out=$(git -C "$HC_STORE" pull 2>&1)
pull_exit=$?

if [ $pull_exit -ne 0 ]; then
    # Network/git failure — don't write state, don't claim updates
    emit "false" "HCPlus check failed: ${pull_out}" "false"
    exit 0
fi

if echo "$pull_out" | grep -q "Already up to date"; then
    # Genuinely up to date and no prior state file — nothing to report
    emit "false" "HyprCandy Plus is up to date" "false"
else
    # New changes were pulled — write state so this survives restarts
    tip="HC+ dotfile updates available — apply to sync."
    write_state "$tip"
    emit "true" "$tip" "false"
fi
