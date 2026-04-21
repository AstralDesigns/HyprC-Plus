#!/usr/bin/env bash
# hc-update-check.sh
# Checks for HyprCandy Plus dotfile updates.
# Outputs a single JSON line:
#   {"hasUpdates": true/false, "tooltip": "...", "noStore": true/false}
#
# Logic:
#   - If ~/.HCUpdates does NOT exist → report updates available (no store).
#   - If ~/.HCUpdates exists → run git pull; if changes were pulled → updates
#     available; if already up-to-date → no updates.
#
# State persistence — intentionally one-directional:
#   The state file (~/.config/hyprcandy/hc-update-state.json) is written ONLY
#   when real updates are found.  "Already up to date" and network failures
#   never touch it.  This means:
#     • A session restart or network-regain scan that finds the store current
#       will NOT erase a previously remembered "updates available" state.
#     • The file is deleted externally by UpdatesPopup.qml the moment the user
#       successfully runs the HC+ update — that is the only way to clear it.

HC_STORE="$HOME/.HCUpdates"
HC_STATE_FILE="$HOME/.config/hyprcandy/hc-update-state.json"

# emit_uptodate: never writes the state file.
# If the state file already exists, re-emit it so a remembered pending-update
# survives a scan that found the store current.
emit_uptodate() {
    if [ -f "$HC_STATE_FILE" ]; then
        cat "$HC_STATE_FILE"
    else
        echo '{"hasUpdates":false,"tooltip":"HyprCandy Plus is up to date","noStore":false}'
    fi
}

# emit_update: writes the state file and echoes the same JSON.
emit_update() {
    local tip="$1" nostore="${2:-false}"
    tip="${tip//\"/\\\"}"
    local json="{\"hasUpdates\":true,\"tooltip\":\"${tip}\",\"noStore\":${nostore}}"
    mkdir -p "$(dirname "$HC_STATE_FILE")"
    echo "$json" > "$HC_STATE_FILE"
    echo "$json"
}

# emit_fail: never touches the state file.
# Re-surfaces persisted state if present so a transient failure doesn't reset
# the UI; otherwise emits a neutral up-to-date so the icon stays quiet.
emit_fail() {
    if [ -f "$HC_STATE_FILE" ]; then
        cat "$HC_STATE_FILE"
    else
        local msg="${1//\"/\\\"}"
        echo "{\"hasUpdates\":false,\"tooltip\":\"HCPlus check failed: ${msg}\",\"noStore\":false}"
    fi
}

# ── Store folder absent ────────────────────────────────────────────────────────
if [ ! -d "$HC_STORE" ]; then
    emit_update "HCPlus store not found — run Apply to set up and sync dotfiles." "true"
    exit 0
fi

if [ ! -d "$HC_STORE/.git" ]; then
    emit_update "HCPlus store is not a git repo — run Apply to re-initialise." "true"
    exit 0
fi

# ── Pull ──────────────────────────────────────────────────────────────────────
pull_out=$(git -C "$HC_STORE" pull 2>&1)
pull_exit=$?

if [ $pull_exit -ne 0 ]; then
    emit_fail "$pull_out"
    exit 0
fi

if echo "$pull_out" | grep -q "Already up to date"; then
    emit_uptodate
else
    # Pull brought in new commits — count changed files from the summary line
    changed=$(echo "$pull_out" | grep -E '^\s+[0-9]+ file' | grep -oE '[0-9]+ file' | head -1)
    [ -z "$changed" ] && changed="changes available"
    emit_update "HC+ dotfile updates pulled (${changed}) — apply to sync."
fi
