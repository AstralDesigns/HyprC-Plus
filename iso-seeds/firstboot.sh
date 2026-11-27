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
#    Keep in sync with .firstboot.sh (the unit ExecStarts that one; this
#    iso-seeds copy is packaging-only). theme/cursor watchers are
#    WantedBy=default.target, already reached when firstboot runs -> use
#    --now. background/lock watchers are WantedBy=hyprland-session.target /
#    graphical-session.target, reached LATER: plain `enable` installs the
#    wants symlinks so the session pulls them in once Hyprland is up.
systemctl --user daemon-reload
systemctl --user enable --now theme-watcher.service cursor-theme-watcher.service 2>/dev/null || true
systemctl --user enable background-watcher.service lock-watcher.service 2>/dev/null || true

# 4b. Seed the GTK icon theme into dconf ONCE (this script runs once per user,
#     live and installed). GTK3's gsettings backend overrides gtk-3.0/settings.ini
#     on dbus sessions, and a fresh dconf defaults icon-theme to Adwaita. Seeding
#     here - not in per-session autostart - keeps later nwg-look/CC choices intact.
#     Wait briefly for the user bus socket (firstboot precedes the session).
for _ in $(seq 1 10); do
  [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/bus" ] && break
  sleep 0.5
done
gsettings set org.gnome.desktop.interface icon-theme 'Tela-circle-black' 2>/dev/null || true

# 5. Repair path only: rebuild the agent workspace if the baked dist is missing.
if [ ! -f "$HC/GJS/hyprcandydock/agent-app/dist/index.html" ]; then
  bash "$HC/GJS/hyprcandydock/agent-app/build.sh" || true
fi

touch "$STATE/firstboot-done"
