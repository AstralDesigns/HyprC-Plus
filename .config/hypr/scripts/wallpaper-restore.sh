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
  [ -n "$seed" ] && [ -f "$seed" ] && awww img "$seed"
fi
