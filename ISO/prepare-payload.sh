#!/usr/bin/env bash
# HyprCandy ISO payload staging + build tuning.
#
# Rebuilds airootfs/etc/skel from the live sources so the ISO ships the current
# dotfiles, shells, wallpaper state and prebuilt agent-app:
#   ~/.HyprC-Plus          -> skel/.hyprcandy   (stow source of truth)
#   ~/.hyprcandy/.../dist  -> skel/.hyprcandy/GJS/hyprcandydock/agent-app/dist
#   $HOME rc files, oh-my-zsh, cargo bins, wallpaper.ini, Pictures seeds
#
# Pre-compression note: every heavy asset shipped here (jpg/png/gif wallpapers,
# *.pkg.tar.zst, minified dist bundles, git objects) is ALREADY compressed, so
# re-compressing them before the build gains nothing. The two effective levers,
# both applied below, are:
#   * payload dedup/slimming - Gifs/ and Wallhaven/ are stow-ignored, so they
#     are shipped once under Pictures/ instead of twice (~147 MiB saved), and
#     node_modules/.venv/__pycache__/logs never enter the payload;
#   * squashfs compressor - profiledef.sh uses zstd-15 instead of xz, which is
#     several times faster on 4 cores for a modest ISO size increase.
#
# Runnable from any directory. Safe to re-run; wipes and restages skel.
set -euo pipefail

ISO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORK="$HOME/CachyOS-HyprCandy"
ARCHISO="$WORK/cachyos-archiso/archiso"
SKEL="$ARCHISO/airootfs/etc/skel"
SRC="$HOME/.HyprC-Plus"
RUN="$HOME/.hyprcandy"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[[ -d "$SRC/.git" ]] || die "dotfiles repo not found: $SRC"
[[ -d "$ARCHISO" ]]  || die "profile not found: $ARCHISO (run initialize-build.sh first)"

log "Restaging skel from scratch"
rm -rf "$SKEL"
mkdir -p "$SKEL"

log "Staging .hyprcandy dotfiles"
rsync -a \
    --exclude='.git/' \
    --exclude='node_modules/' \
    --exclude='.venv/' \
    --exclude='__pycache__/' \
    --exclude='*.log' \
    --exclude='*.pid' \
    --exclude='*.state' \
    --exclude='matugen-state' \
    --exclude='candy-start-icon.txt' \
    --exclude='.config/hyprcandy/cache/' \
    --exclude='/Gifs/' \
    --exclude='/Wallhaven/' \
    "$SRC/" "$SKEL/.hyprcandy/"
# stow ignores these; Pictures/ carries the single shipped copy
rm -rf "$SKEL/.hyprcandy/Gifs" "$SKEL/.hyprcandy/Wallhaven"

log "Overlaying prebuilt agent-app dist"
[[ -f "$RUN/GJS/hyprcandydock/agent-app/dist/index.html" ]] \
    || die "agent-app dist missing - build it first (agent-app/build.sh)"
rsync -a --delete \
    "$RUN/GJS/hyprcandydock/agent-app/dist/" \
    "$SKEL/.hyprcandy/GJS/hyprcandydock/agent-app/dist/"

log "Shallow .git for in-place dotfile updates"
if [[ ! -d "$SKEL/.hyprcandy/.git" ]]; then
    tmp=$(mktemp -d)
    git clone --quiet --depth 1 --no-local "$SRC" "$tmp/repo"
    mv "$tmp/repo/.git" "$SKEL/.hyprcandy/.git"
    rm -rf "$tmp"
fi

log "Seeding home files"
for f in .zshrc .bashrc .bash_profile; do
    [[ -f "$HOME/$f" ]] && install -Dm644 "$HOME/$f" "$SKEL/$f"
done
[[ -f "$HOME/.config/wallpaper/wallpaper.ini" ]] \
    || die "wallpaper.ini missing - wallpaper restore would have no state"
install -Dm644 "$HOME/.config/wallpaper/wallpaper.ini" "$SKEL/.config/wallpaper/wallpaper.ini"
# hyprviz.lua is GENERATED at runtime (not in the git repo) and hyprland.lua
# dofile()s it unconditionally: without it Hyprland aborts config load and
# boots its bare default session (no bar, no autostart).
[[ -f "$HOME/.config/hypr/hyprviz.lua" ]] \
    || die "hyprviz.lua missing - Hyprland's Lua entry dofile()s it unconditionally"
install -Dm644 "$HOME/.config/hypr/hyprviz.lua" \
    "$SKEL/.hyprcandy/.config/hypr/hyprviz.lua"
# first-boot user service + its wants symlink (relative, survives stow).
# Only firstboot is seeded outside .hyprcandy; the six watcher units arrive
# via the stowed .hyprcandy/.config/systemd/user copy above.
install -Dm644 "$SRC/.config/systemd/user/hyprcandy-firstboot.service" \
    "$SKEL/.config/systemd/user/hyprcandy-firstboot.service"
mkdir -p "$SKEL/.config/systemd/user/default.target.wants"
ln -sfn ../hyprcandy-firstboot.service \
    "$SKEL/.config/systemd/user/default.target.wants/hyprcandy-firstboot.service"
rsync -a --exclude='.git/' "$HOME/.oh-my-zsh/" "$SKEL/.oh-my-zsh/"
# Live-session installer autostart, hooked through hyprland.lua's optional
# custom.lua dofile. Installed systems never match the archiso cmdline, so
# the block is a no-op there; host user preferences are preserved.
mkdir -p "$SKEL/.config/custom"
if [[ -f "$HOME/.config/custom/custom.lua" ]]; then
    install -Dm644 "$HOME/.config/custom/custom.lua" "$SKEL/.config/custom/custom.lua"
else
    : > "$SKEL/.config/custom/custom.lua"
fi
# The host custom.lua ends with `return true`; Lua forbids statements after a
# return, so the live block must be inserted BEFORE that line (appending it
# after makes the whole chunk a syntax error and optional_dofile rethrows).
hc_block=$(mktemp)
cat > "$hc_block" <<'LUA'

-- HyprCandy ISO live session: autostart the offline installer once.
local hc_cmdline = io.open("/proc/cmdline", "r")
if hc_cmdline then
    local hc_args = hc_cmdline:read("*a") or ""
    hc_cmdline:close()
    if hc_args:match("archisobasedir=") then
        hl.exec_cmd("/usr/local/bin/calamares-online.sh")
        -- VM outputs can settle after hyprland.start; retry wallpaper once.
        hl.exec_cmd("bash -c 'sleep 3; bash ~/.config/hypr/scripts/wallpaper-restore.sh'")
    end
end
LUA
awk -v bf="$hc_block" '
    /^return true[[:space:]]*$/ && !ins { while ((getline l < bf) > 0) print l; close(bf); ins=1 }
    { print }
    END { if (!ins) while ((getline l < bf) > 0) print l }
' "$SKEL/.config/custom/custom.lua" > "$SKEL/.config/custom/custom.lua.new"
mv "$SKEL/.config/custom/custom.lua.new" "$SKEL/.config/custom/custom.lua"
rm -f "$hc_block"
install -Dm755 -t "$SKEL/.cargo/bin" \
    "$HOME/.cargo/bin/wallust" \
    "$HOME/.cargo/bin/cargo-install-update" \
    "$HOME/.cargo/bin/cargo-install-update-config"

log "Seeding Pictures (single copy of wallpapers/gifs)"
mkdir -p "$SKEL/Pictures/Screenshots" "$SKEL/Videos/Recordings"
rsync -a --delete "$SRC/Wallhaven/" "$SKEL/Pictures/Wallhaven/"
rsync -a --delete "$SRC/Gifs/" "$SKEL/Pictures/Gifs/"
install -Dm644 "$SRC/transparent.png" "$SKEL/Pictures/transparent.png"

log "Seeding dock pinned apps (install.sh defaults, baked providers only)"
# com.shellyorg.shelly is NOT in the ISO package set -> omitted (dead dock
# entry otherwise). The calamares pin is live-only: .firstboot.sh removes it
# on installed systems (guarded by /proc/cmdline archisobasedir= match).
cat > "$SKEL/.config/pinned" <<'PIN'
org.gnome.Nautilus
org.gnome.gedit
org.gnome.DiskUtility
nwg-displays
nwg-look
calamares
PIN

log "Seeding quickshell cache color defaults (overview/wallpaper panels)"
# Those panels parse these QML color files at startup; if wallpaper-restore
# fails on first boot, missing files render solid black. Host copies are the
# current palette; matugen/wallust overwrite them on the first theme run.
for _f in overview/Appearance.colors.qml overview/Appearance.wallust.qml \
          wallpaper/MatugenColors.qml wallpaper/WallustColors.qml; do
    [[ -f "$HOME/.cache/quickshell/$_f" ]] || die "quickshell cache color file missing: $_f"
    install -Dm644 "$HOME/.cache/quickshell/$_f" "$SKEL/.cache/quickshell/$_f"
done

log "Pre-stowing skel (race-free dotfiles at first login)"
# mkarchiso copies skel into user homes BEFORE the customize hook runs, and
# Hyprland reads ~/.config/hypr at process start - a firstboot-time stow races
# the compositor and loses on slow machines (bare default session). Stowing
# here bakes relative symlinks that survive the skel->home copy.
rm -f "$SKEL/.config/systemd/user/hyprcandy-firstboot.service"
# transparent.png is stow-ignored: it ships only as the real Pictures/ copy
# (optional Brave see-through background), never as a home-root symlink.
(cd "$SKEL/.hyprcandy" && stow -t "$SKEL" \
    --ignore='Gifs' --ignore='GJS' --ignore='Greeter' \
    --ignore='Wallhaven' --ignore='iso-seeds' --ignore='transparent.png' \
    --ignore='ISO' .)

log "Tuning squashfs compression (zstd-15)"
sed -i "s/^airootfs_image_tool_options=.*/airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')/" \
    "$ARCHISO/profiledef.sh"

log "Sanity checks"
test -f "$SKEL/.hyprcandy/GJS/hyprcandydock/agent-app/dist/index.html"
test -f "$SKEL/.hyprcandy/.config/hypr/hyprviz.lua"
test -L "$SKEL/.config/hypr"
test -f "$SKEL/.config/custom/custom.lua"
# live block must precede any trailing `return true` (Lua syntax rule)
awk '/^return true/{f=1} f && /HyprCandy ISO live session/{exit 1}' "$SKEL/.config/custom/custom.lua"
if command -v luac5.4 >/dev/null; then
    luac5.4 -p "$SKEL/.config/custom/custom.lua"
    luac5.4 -p "$SKEL/.hyprcandy/.config/hypr/hyprviz.lua"
fi
test -f "$SKEL/.config/wallpaper/wallpaper.ini"
test -f "$SKEL/.config/pinned"
grep -qx 'calamares' "$SKEL/.config/pinned"
! grep -qx 'com.shellyorg.shelly' "$SKEL/.config/pinned"
test -f "$SKEL/Pictures/transparent.png"
test ! -e "$SKEL/transparent.png"
test -f "$SKEL/.cache/quickshell/overview/Appearance.colors.qml"
test -f "$SKEL/.cache/quickshell/wallpaper/MatugenColors.qml"
test -f "$SKEL/.config/systemd/user/hyprcandy-firstboot.service"
test -L "$SKEL/.config/systemd/user/default.target.wants/hyprcandy-firstboot.service"
bash -n "$ARCHISO/airootfs/root/customize_airootfs.sh"
bash -n "$ARCHISO/airootfs/usr/local/lib/hyprcandy/system-setup.sh"
bash -n "$ARCHISO/airootfs/usr/local/bin/calamares-online.sh"

log "Payload size"
du -sh "$SKEL" "$SKEL/.hyprcandy" "$SKEL/Pictures"
printf '\nPayload staged. Build with:\n  cd %s && sudo ./buildiso.sh -p desktop -v -w\n' "$WORK/cachyos-archiso"