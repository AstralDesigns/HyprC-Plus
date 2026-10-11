#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")"

# ── Give the React build enough room on low-RAM machines ─────────────────────
# Bundling Monaco (full editor + every language worker; ts.worker alone is 7 MB)
# across tsc + vite is memory heavy. Two different ceilings can be hit:
#   1. Node's default V8 old-space cap -> "javascript heap out of memory";
#   2. the machine's physical RAM      -> "Aborted (core dumped)" (SIGABRT).
# Raising only the heap cap just moves a 4 GB box from (1) to (2). So we ALSO
# add a throwaway swapfile on <6 GB machines when we can (running as root, which
# the pkexec update path is, or with passwordless sudo) so a raised heap can
# actually be backed. NODE_OPTIONS is exported once and inherited by every Node
# step below (npm ci, tsc --noEmit, vite build) — i.e. all potential abort lines.
_HC_MEM_TOTAL="$(awk '/MemTotal/{print int($2/1024); exit}' /proc/meminfo 2>/dev/null)"
case "${_HC_MEM_TOTAL:-}" in ''|*[!0-9]*) _HC_MEM_TOTAL=2048 ;; esac
_HC_SWAP=""
_hc_del_swap() {
  [ -n "${_HC_SWAP:-}" ] || return 0
  local _s
  if [ "$(id -u)" = "0" ]; then _s=""
  elif sudo -n true 2>/dev/null; then _s="sudo -n"
  else return 0; fi
  # shellcheck disable=SC2086
  $_s swapoff "$_HC_SWAP" 2>/dev/null || true
  # shellcheck disable=SC2086
  $_s rm -f "$_HC_SWAP" 2>/dev/null || true
}
_HC_MODE=""
if [ "$_HC_MEM_TOTAL" -lt 6144 ]; then
  _HC_PRIV=0
  if [ "$(id -u)" = "0" ]; then _HC_MODE=""; _HC_PRIV=1
  elif sudo -n true 2>/dev/null; then _HC_MODE="sudo -n"; _HC_PRIV=1
  elif [ -t 0 ] && sudo -v 2>/dev/null; then _HC_MODE="sudo"; _HC_PRIV=1
  fi
  if [ "$_HC_PRIV" = "1" ]; then
    _HC_SWAP=/var/tmp/hyprcandy-build.swap
    if ! swapon --show=NAME --noheadings 2>/dev/null | grep -qx "$_HC_SWAP"; then
      if [ ! -f "$_HC_SWAP" ]; then
        # shellcheck disable=SC2086
        $_HC_MODE dd if=/dev/zero of="$_HC_SWAP" bs=1M count=4096 status=none 2>/dev/null \
          && $_HC_MODE chmod 600 "$_HC_SWAP" 2>/dev/null \
          && $_HC_MODE mkswap "$_HC_SWAP" >/dev/null 2>&1 || { _HC_SWAP=""; }
      fi
      if [ -n "$_HC_SWAP" ]; then $_HC_MODE swapon "$_HC_SWAP" 2>/dev/null || true; fi
    fi
    trap _hc_del_swap EXIT
  fi
fi
if [ -z "${NODE_OPTIONS:-}" ]; then
  _hc_heap=$((_HC_MEM_TOTAL/2))
  if [ -n "$_HC_SWAP" ]; then _hc_heap=4096; fi   # spill available -> build bigger
  if [ "$_hc_heap" -lt 1024 ]; then _hc_heap=1024; fi
  if [ "$_hc_heap" -gt 8192 ]; then _hc_heap=8192; fi
  export NODE_OPTIONS="--max-old-space-size=${_hc_heap}"
fi
echo "Build env: MemTotal=${_HC_MEM_TOTAL}MB swap=${_HC_SWAP:-none} NODE_OPTIONS=${NODE_OPTIONS:-inherited}"

# One-shot first-time setup for a new install: prepares everything the agent
# workspace needs to run, without starting or auto-starting any of it.
# The GJS launcher starts the Python runtime itself on demand (it's lightweight,
# BYOK / cloud inference).

echo "== 1/2: Python runtime (Agents/local_runtime) =="
RUNTIME_DIR="../Agents/local_runtime"
VENV="$RUNTIME_DIR/.venv"
if [[ ! -f "$VENV/bin/uvicorn" ]]; then
  echo "Creating Python virtual environment and installing dependencies..."
  python3 -m venv "$VENV"
  # Keep this package list identical to start.sh's own bootstrap — that
  # script re-checks/re-installs the same way on every launch, so the two
  # must never drift.
  "$VENV/bin/pip" install --quiet \
    fastapi \
    "uvicorn[standard]" \
    httpx \
    pydantic
else
  echo "Python virtual environment already present at $VENV — skipping."
fi

echo "== 2/2: agent-app frontend (React UI) =="
if [[ ! -d node_modules ]]; then
  npm ci --include=dev --no-audit --no-fund --loglevel=error || npm install --include=dev --no-audit --no-fund
fi
./node_modules/.bin/tsc --noEmit
./node_modules/.bin/vite build

echo "Setup complete: the Python runtime venv is ready, and dist/index.html is built."
echo "Nothing was started — the Python runtime starts itself the first time the agent workspace is opened."
