#!/bin/bash
#                _ _
# __      ____ _| | |_ __   __ _ _ __   ___ _ __
# \ \ /\ / / _` | | | '_ \ / _` | '_ \ / _ \ '__|
#  \ V  V / (_| | | | |_) | (_| | |_) |  __/ |
#   \_/\_/ \__,_|_|_| .__/ \__,_| .__/ \___|_|
#                   |_|         |_|
#
# -----------------------------------------------------
# Restore last wallpaper
# -----------------------------------------------------
# `awww restore` only redisplay the daemon's LAST shown image. On a fresh
# live daemon there is none, so it exits 0 without displaying anything and
# the old `restore || img` fallback never fired (no static background). Run
# restore, then guarantee the configured wallpaper: if no output is showing
# an image, apply the wallpaper.ini seed. Host-safe: restore already set an
# image there, so the seed branch is skipped.

seed="$(grep '^wallpaper' "$HOME/.config/wallpaper/wallpaper.ini" 2>/dev/null \
  | cut -d= -f2 | sed "s|^ *||;s|^~|$HOME|")"

awww-daemon 2>/dev/null
sleep 0.5
awww restore 2>/dev/null
if ! awww query 2>/dev/null | grep -q 'displaying: image:'; then
  # First application (ISO / new desktop): go through the picker's apply path
  # so the seed is persisted to wallpaper.ini and matugen colors regenerate.
  # `awww restore` only helps on subsequent logins where the daemon already
  # remembers an image, which never happens on a fresh live session.
  # Retry: hyprland.start fires this before the wayland socket accepts
  # one-shot clients on slow boots; awww img dies on the first refusal, so
  # keep trying until it lands (host logins succeed on the first attempt).
  if [ -n "$seed" ] && [ -f "$seed" ]; then
    for _ in $(seq 1 20); do
      bash "$HOME/.config/quickshell/wallpaper/wallpaper-apply.sh" "$seed" && break
      sleep 1
    done
  fi
fi
