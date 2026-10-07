#!/usr/bin/env bash
# hc-agent-build.sh
# Wrapper called by UpdatesPopup.qml (_hcAgentBuildProc) after a HC+ update.
# Builds the agent-app frontend whenever the workspace is missing OR stale
# (updates routinely ship agent-app source changes, so a present dist/ is
# not proof of freshness), and recreates the Python venv when absent.
#
# NOTE: This is intentionally NOT called by install.sh — that runs build.sh
# directly in an interactive terminal where PATH is already correct.
# This wrapper exists solely for the QML-spawned non-interactive context.
#
# QML runs this via: bash --login -c "exec bash hc-agent-build.sh"
# --login sources /etc/profile + /etc/profile.d/* which puts AUR/system
# node on PATH. The extra PATH exports below are a belt-and-braces fallback
# for edge-case installs.

LOG=/tmp/hc-agent-app-build.log
exec > >(tee -a "$LOG") 2>&1
echo "=== hc-agent-build.sh started: $(date) ==="

AGENT_DIR="$HOME/.hyprcandy/GJS/hyprcandydock/agent-app"
VENV_UVICORN="$HOME/.hyprcandy/GJS/hyprcandydock/Agents/local_runtime/.venv/bin/uvicorn"
DIST_HTML="$AGENT_DIR/dist/index.html"

# ── Freshness check: rebuild unless dist is newer than every input ──────────
needs_build() {
    [[ -f "$DIST_HTML" ]] || return 0
    [[ -f "$VENV_UVICORN" ]] || return 0
    local f
    for f in src package.json package-lock.json vite.config.ts tsconfig.json index.html; do
        [[ -e "$AGENT_DIR/$f" ]] || continue
        if find "$AGENT_DIR/$f" -newer "$DIST_HTML" -print -quit 2>/dev/null | grep -q .; then
            return 0
        fi
    done
    return 1
}

if ! needs_build; then
    echo "Agent workspace up to date (dist newer than all sources) — nothing to do."
    exit 0
fi

echo "Agent workspace missing or stale — running build.sh..."

# build.sh only runs `npm ci` when node_modules is absent; drop it when the
# lockfile is newer than the installed tree so dependency updates apply.
if [[ -d "$AGENT_DIR/node_modules" && "$AGENT_DIR/package-lock.json" -nt "$AGENT_DIR/node_modules" ]]; then
    echo "package-lock.json newer than node_modules — reinstalling deps."
    rm -rf "$AGENT_DIR/node_modules"
fi

# ── Belt-and-braces PATH for non-login edge cases ────────────────────────────
# bash --login in the QML command handles AUR/system node via /etc/profile.d/.
# These extras cover nvm users and local installs as an additional fallback.
export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"
if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    # shellcheck disable=SC1091
    source "$HOME/.nvm/nvm.sh" --no-use
    nvm use default 2>/dev/null || nvm use node 2>/dev/null || true
elif [[ -d "$HOME/.nvm/versions/node" ]]; then
    LATEST_NODE=$(ls -v "$HOME/.nvm/versions/node" | tail -n1)
    [[ -n "$LATEST_NODE" ]] && export PATH="$HOME/.nvm/versions/node/$LATEST_NODE/bin:$PATH"
fi

if ! command -v npm &>/dev/null; then
    echo "ERROR: npm not found on PATH after all PATH augmentation attempts." >&2
    echo "  PATH=$PATH" >&2
    echo "  Install node via AUR (nodejs/nodejs-lts-iron) or nvm." >&2
    exit 1
fi

echo "Using node: $(node --version 2>/dev/null), npm: $(npm --version 2>/dev/null)"

# ── Run build.sh ─────────────────────────────────────────────────────────────
cd "$AGENT_DIR"
bash build.sh

echo "=== hc-agent-build.sh finished: $(date) ==="
