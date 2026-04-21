#!/usr/bin/env bash
# hc-update-check.sh
# Checks for HyprCandy Plus dotfile updates.
# Outputs a single JSON line:
#   {"hasUpdates": true/false, "tooltip": "...", "noStore": true/false}
#
# Logic:
#   - If ~/HCUpdates does NOT exist → report updates available (no store),
#     so the apply button forces the main update script to set it up.
#   - If ~/HCUpdates exists → run git pull; if changes were pulled → updates
#     available; if already up-to-date → no updates.

HC_STORE="$HOME/.HCUpdates"
HC_REPO="https://github.com/AstralDesigns/HyprC-Plus.git"

emit() {
    local has="$1" tip="$2" nostore="${3:-false}"
    # Escape any double-quotes in tooltip
    tip="${tip//\"/\\\"}"
    echo "{\"hasUpdates\":${has},\"tooltip\":\"${tip}\",\"noStore\":${nostore}}"
}

# ── Store folder absent ────────────────────────────────────────────────────────
if [ ! -d "$HC_STORE" ]; then
    emit "true" "HCPlus store not found — run Apply to set up and sync dotfiles." "true"
    exit 0
fi

# ── Store folder present: attempt git pull ────────────────────────────────────
if [ ! -d "$HC_STORE/.git" ]; then
    # Folder exists but isn't a git repo — treat same as absent
    emit "true" "HCPlus store is not a git repo — run Apply to re-initialise." "true"
    exit 0
fi

# Fetch quietly; capture pull output to detect changes
pull_out=$(git -C "$HC_STORE" pull --ff-only 2>&1)
pull_exit=$?

if [ $pull_exit -ne 0 ]; then
    # Network error or conflict — report unknown state, don't claim updates
    emit "false" "HCPlus check failed: ${pull_out}" "false"
    exit 0
fi

if echo "$pull_out" | grep -q "Already up to date"; then
    emit "false" "HyprCandy Plus is up to date" "false"
else
    # git pull pulled something — count changed files
    changed=$(echo "$pull_out" | grep -E '^\s+[0-9]+ file' | grep -oE '[0-9]+ file' | head -1)
    if [ -z "$changed" ]; then
        changed="changes available"
    fi
    emit "true" "HC+ dotfile updates pulled (${changed}) — apply to sync." "false"
fi
