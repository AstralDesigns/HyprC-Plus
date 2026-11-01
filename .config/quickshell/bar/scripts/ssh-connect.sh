#!/usr/bin/env bash
# ── ssh-connect.sh ───────────────────────────────────────────────────────────
# Open a terminal running `ssh <target>` for the ControlCenter SSH sub-tab.
# <target> is a ~/.ssh/config Host alias (or user@host); ssh resolves the rest.
# The first available terminal from a preference list is used, with $TERMINAL
# honoured first. A login shell wraps ssh so PATH / ssh-agent / shell env are
# exactly what the user would get at a prompt. Detached via `setsid --fork` so
# the session survives the Control Center closing.
set -u
target="${1:-}"
if [ -z "$target" ]; then echo "err no target"; exit 1; fi

q="$(printf '%q' "$target")"
cmd="ssh $q"

term=""
for c in "${TERMINAL:-}" kitty alacritty wezterm foot ghostty \
         xfce4-terminal gnome-terminal konsole x-terminal-emulator xterm; do
    [ -z "$c" ] && continue
    if command -v "$c" >/dev/null 2>&1; then term="$c"; break; fi
done
if [ -z "$term" ]; then echo "err no terminal found"; exit 2; fi

base="$(basename "$term")"
case "$base" in
    kitty)              args=(-- bash -lc "$cmd") ;;
    alacritty)          args=(-e bash -lc "$cmd") ;;
    wezterm)            args=(start -- bash -lc "$cmd") ;;
    foot)               args=(-- bash -lc "$cmd") ;;
    ghostty)            args=(-e bash -lc "$cmd") ;;
    xfce4-terminal)     args=(--command "bash -lc \"$cmd\"") ;;
    gnome-terminal)     args=(-- bash -lc "$cmd") ;;
    konsole)            args=(-e bash -lc "$cmd") ;;
    xterm)              args=(-e bash -lc "$cmd") ;;
    x-terminal-emulator) args=(-e bash -lc "$cmd") ;;
    *)                  args=(-e "$cmd") ;;
esac

setsid --fork "$term" "${args[@]}" </dev/null >/dev/null 2>&1 &
echo "ok launching: $cmd (via $base)"
