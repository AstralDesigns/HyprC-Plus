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
STOW_ARGS=(-v -t "$HOME" --ignore='Gifs' --ignore='GJS' --ignore='Greeter' --ignore='Wallhaven' --ignore='iso-seeds')
stow "${STOW_ARGS[@]}" . || stow -R "${STOW_ARGS[@]}" .

# 3. Executable bits for scripts/hooks.
for d in "$HOME/.config/hypr/scripts" "$HOME/.config/hyprcandy/scripts" \
         "$HOME/.config/hyprcandy/hooks" "$HOME/.config/quickshell/bar" \
         "$HOME/.config/quickshell/bar/scripts" "$HOME/.config/quickshell/lockscreens" \
         "$HOME/.config/quickshell/wallpaper" "$HC/GJS/hyprcandydock"; do
  [ -d "$d" ] && find "$d" -name '*.sh' -exec chmod +x {} +
done

# 4. User services (watchers; hcproxy stays opt-in via the launcher).
systemctl --user daemon-reload
systemctl --user enable theme-watcher.service cursor-theme-watcher.service 2>/dev/null || true

# 5. Repair path only: rebuild the agent workspace if the baked dist is missing.
if [ ! -f "$HC/GJS/hyprcandydock/agent-app/dist/index.html" ]; then
  bash "$HC/GJS/hyprcandydock/agent-app/build.sh" || true
fi

touch "$STATE/firstboot-done"
