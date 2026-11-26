#!/usr/bin/env bash
# HyprCandy ISO first-login setup — runs once, before the graphical session.
# Everything heavy (packages, shell configs, wallpapers, agent-app dist) is
# baked into the ISO; this only links dotfiles and enables user services.
set -euo pipefail

HC="$HOME/.hyprcandy"
STATE="$HOME/.local/state/hyprcandy"
mkdir -p "$STATE"

# 1. Drop the skel-seeded real copy of the firstboot unit so stow can symlink
#    the repo-managed one (identical content).
rm -f "$HOME/.config/systemd/user/hyprcandy-firstboot.service"

# 2. Stow dotfiles. wallpaper/fish-plugin state stays as baked real files;
#    iso-seeds is packaging-only. (No --ignore='wallpaper' — it would also
#    exclude quickshell/wallpaper, since stow matches basenames.)
cd "$HC"
STOW_ARGS=(-v -t "$HOME" --ignore='Gifs' --ignore='GJS' --ignore='Greeter' --ignore='Wallhaven' --ignore='iso-seeds' --ignore='ISO')
stow "${STOW_ARGS[@]}" . || stow -R "${STOW_ARGS[@]}" .

# 3. Executable bits for scripts/hooks.
for d in "$HOME/.config/hypr/scripts" "$HOME/.config/hyprcandy/scripts" \
         "$HOME/.config/hyprcandy/hooks" "$HOME/.config/quickshell/bar" \
         "$HOME/.config/quickshell/bar/scripts" "$HOME/.config/quickshell/lockscreens" \
         "$HOME/.config/quickshell/wallpaper" "$HC/GJS/hyprcandydock"; do
  [ -d "$d" ] && find "$d" -name '*.sh' -exec chmod +x {} +
done

# 4. User services (watchers; hcproxy stays opt-in via the launcher).
#    theme/cursor watchers are WantedBy=default.target, which has already
#    been reached by the time firstboot runs -> `enable` alone would not
#    start them this session, so use --now. background/lock watchers are
#    WantedBy=hyprland-session.target / graphical-session.target, which are
#    reached LATER (firstboot is Before=graphical-session.target): plain
#    `enable` installs the wants symlinks so the session pulls them in once
#    Hyprland is up (starting them now, before the Hyprland IPC exists, would
#    just fail their import-environment ExecStartPre).
systemctl --user daemon-reload
systemctl --user enable --now theme-watcher.service cursor-theme-watcher.service 2>/dev/null || true
systemctl --user enable background-watcher.service lock-watcher.service 2>/dev/null || true

# 5. Repair path only: rebuild the agent workspace if the baked dist is missing.
if [ ! -f "$HC/GJS/hyprcandydock/agent-app/dist/index.html" ]; then
  bash "$HC/GJS/hyprcandydock/agent-app/build.sh" || true
fi

# 6. Installed systems only: drop the live-only installer dock pin.
# (cat > keeps the inode/ownership; sed -i would replace the file as root-owned
# when run from system contexts, and firstboot runs as the user anyway.)
if ! grep -q 'archisobasedir=' /proc/cmdline && [ -f "$HOME/.config/pinned" ]; then
  if grep -qx 'io.calamares.calamares' "$HOME/.config/pinned"; then
    grep -vx 'io.calamares.calamares' "$HOME/.config/pinned" > "$HOME/.config/pinned.tmp"
    cat "$HOME/.config/pinned.tmp" > "$HOME/.config/pinned"
    rm -f "$HOME/.config/pinned.tmp"
  fi
fi

# 7. Installed systems only: the live SDDM autologin drop-in survives unpackfs
#    but references the removed liveuser. Drop it so the greeter owns login
#    (wheel carries NOPASSWD sudo from the baked g_wheel rule).
if ! grep -q 'archisobasedir=' /proc/cmdline; then
  if grep -qs 'liveuser' /etc/sddm.conf.d/autologin.conf; then
    sudo rm -f /etc/sddm.conf.d/autologin.conf || true
  fi
fi

touch "$STATE/firstboot-done"
