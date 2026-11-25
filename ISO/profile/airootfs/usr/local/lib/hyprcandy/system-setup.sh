#!/usr/bin/env bash
# HyprCandy system setup — idempotent, runs once per boot before the DM.
# Handles everything that needs root: per-user sudoers, greeter seed, cursors,
# pacman candy, service enables. Per-user dotfile work happens in the
# hyprcandy-firstboot.service user unit instead.
set -euo pipefail

SENTINEL=/run/hyprcandy-system-setup.done
[ -f "$SENTINEL" ] && exit 0

LIVE=0
grep -q 'archisobasedir=' /proc/cmdline && LIVE=1

SKEL=/etc/skel
HC_SKEL="$SKEL/.hyprcandy"

# ── 0. Live session: provision liveuser home from skel if missing/empty ─────
# Guarantees the baked dotfiles exist for SDDM autologin regardless of what
# upstream live hooks do. Idempotent: skips a home that already has content.
if [ "$LIVE" -eq 1 ]; then
  luhome=$(getent passwd liveuser | cut -d: -f6)
  if [ -n "$luhome" ] && { [ ! -d "$luhome" ] || [ -z "$(ls -A "$luhome" 2>/dev/null)" ]; }; then
    install -d -o liveuser -g liveuser "$luhome"
    cp -a "$SKEL/." "$luhome/"
    chown -R liveuser:liveuser "$luhome"
  fi
fi

# ── 0b. Drop the build-time [hc-local] repo (file:// path only exists on the
# build machine; packages are already installed, AUR updates go through paru)
if grep -q '^\[hc-local\]' /etc/pacman.conf; then
  sed -i '/^\[hc-local\]/,/^\[/{/^\[hc-local\]/d;/^\[/!d;}' /etc/pacman.conf
fi

# ── 1. Per-user sudoers drop-ins + firstboot self-heal ──────────────────────
while IFS=: read -r user _ uid _ _ home shell; do
  [ "$uid" -ge 1000 ] 2>/dev/null || continue
  [ "$uid" -eq 65534 ] && continue
  [ -d "$home" ] || continue
  case "$shell" in */nologin|*/false) continue ;; esac

  tmp=$(mktemp)
  sed -e "s|@USER@|$user|g" -e "s|@HOME@|$home|g" \
      /usr/local/lib/hyprcandy/sudoers.template > "$tmp"
  if visudo -cf "$tmp" >/dev/null 2>&1; then
    install -m 440 -o root -g root "$tmp" "/etc/sudoers.d/hyprcandy-background-$user"
  else
    echo "hyprcandy: sudoers validation failed for $user" >&2
  fi
  rm -f "$tmp"

  # Calamares creates users with /bin/bash; HyprCandy's default shell is zsh.
  # Only convert bash/sh so a deliberate fish choice is preserved.
  case "$shell" in
    /bin/bash|/usr/bin/bash|/bin/sh|/usr/bin/sh)
      if [ -x /usr/bin/zsh ]; then
        usermod -s /usr/bin/zsh "$user"
      fi
      ;;
  esac

  # Installed system: live-session welcome app should not autostart
  if [ "$LIVE" -eq 0 ]; then
    rm -f "$home/.config/autostart/cachyos-hello.desktop"
  fi

  if [ -d "$home/.hyprcandy" ]; then
    # Ensure the firstboot user unit is wanted (relative symlink, user-owned)
    install -d -o "$user" -g "$user" "$home/.config/systemd/user/default.target.wants"
    ln -sfn ../hyprcandy-firstboot.service \
        "$home/.config/systemd/user/default.target.wants/hyprcandy-firstboot.service"
    chown -h "$user:$user" \
        "$home/.config/systemd/user/default.target.wants/hyprcandy-firstboot.service"
    # Installed system: seed Hyprland keyboard layout from Calamares' setting
    if [ "$LIVE" -eq 0 ] && [ -f /etc/default/keyboard ] && \
       [ -f "$home/.hyprcandy/.config/hypr/hyprviz.lua" ]; then
      kb=$(sed -n 's/^XKBLAYOUT="\{0,1\}\([^"]*\)"\{0,1\}/\1/p' /etc/default/keyboard | head -1)
      if [ -n "$kb" ]; then
        sed -i "s/kb_layout = \"[^\"]*\"/kb_layout = \"$kb\"/" \
            "$home/.hyprcandy/.config/hypr/hyprviz.lua" || true
      fi
    fi
  fi
done < /etc/passwd

# ── 1b. Display-manager alias self-heal ─────────────────────────────────────
# Upstream points the alias at plasmalogin, which is not baked; a dangling
# alias would drop the live boot to a tty. Only heal when dangling/missing so
# an installed system's Calamares dmcheck choice is never overridden.
if [ ! -e /etc/systemd/system/display-manager.service ]; then
  ln -sfn /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service
fi

# ── 2. Greeter themes: seed system-wide copies (never clobber runtime sync) ─
if [ -d "$HC_SKEL/Greeter/themes" ]; then
  for th in "$HC_SKEL/Greeter/themes/"*/; do
    [ -d "$th" ] || continue
    name=$(basename "$th")
    if [ ! -d "/usr/share/sddm/themes/$name" ]; then
      cp -a "$th" "/usr/share/sddm/themes/$name"
    fi
    if [ ! -f "/usr/share/sddm/themes/$name/theme.conf" ] && [ -f "$th/theme.conf" ]; then
      cp "$th/theme.conf" "/usr/share/sddm/themes/$name/theme.conf"
    fi
    chmod -R a+rX "/usr/share/sddm/themes/$name" 2>/dev/null || true
  done
fi
# Shared greeter background seed (greeter-sync.sh updates it at runtime later)
install -d -m 755 /usr/share/sddm/themes/hyprcandy-shared/Backgrounds
if [ ! -f /usr/share/sddm/themes/hyprcandy-shared/Backgrounds/current.jpg ]; then
  cp "$SKEL/Pictures/Wallhaven/1347728.png" \
     /usr/share/sddm/themes/hyprcandy-shared/Backgrounds/current.jpg 2>/dev/null || true
  chmod 644 /usr/share/sddm/themes/hyprcandy-shared/Backgrounds/current.jpg 2>/dev/null || true
fi

# ── 3. SDDM theme config (write once; runtime CC edits via sudoers afterwards) ─
mkdir -p /etc/sddm.conf.d
if [ ! -f /etc/sddm.conf.d/hyprcandy.conf ]; then
  cat > /etc/sddm.conf.d/hyprcandy.conf << SDDM
[Theme]
Current=hyprcandy-1
CursorTheme=geared-steel-32x
CursorSize=18
SDDM
fi
# The live autologin drop-in must not survive onto an installed system
if [ "$LIVE" -eq 0 ]; then
  rm -f /etc/sddm.conf.d/autologin.conf
  rm -f /etc/systemd/system/getty@tty1.service.d/autologin.conf
fi

# ── 3b. Btrfs snapshot stack (installed system only) ────────────────────────
# cachyos-snapper-support is not baked (its post_install would create the
# snapper config at build time); recreate its effect on first real boot.
if [ "$LIVE" -eq 0 ] && [ "$(findmnt -no FSTYPE /)" = "btrfs" ] && command -v snapper >/dev/null; then
  if [ ! -f /etc/snapper/configs/root ]; then
    snapper --no-dbus -c root create-config --template cachyos-root / 2>/dev/null || \
      snapper --no-dbus -c root create-config / 2>/dev/null || true
  fi
  systemctl enable snapper-cleanup.timer 2>/dev/null || true
  # Installation restore point (mirrors upstream btrfs-installation-snapshot)
  if [ -f /etc/snapper/configs/root ] && [ ! -f /etc/cachyos/installation-snapshot ]; then
    snap_id=$(snapper --no-dbus -c root create --print-number \
        --description "Fresh HyprCandy Installation" --userdata "important=yes" 2>/dev/null) || true
    if [ -n "$snap_id" ]; then
      mkdir -p /etc/cachyos
      echo "$snap_id" > /etc/cachyos/installation-snapshot
    fi
  fi
  # grub-btrfs keeps snapshot boot entries current on GRUB installs
  if [ -f /boot/grub/grub.cfg ]; then
    systemctl enable grub-btrfsd.service 2>/dev/null || true
  fi
fi

# The live profile masks cachyos-rate-mirrors.timer (live sessions must not
# re-rank mirrors); unpackfs carries that mask into offline installs and the
# package scriptlet only runs `systemctl enable`, which fails while masked.
# Restore installed-system behavior (host reference: unmasked + enabled).
if [ "$LIVE" -eq 0 ] && [ -e /usr/lib/systemd/system/cachyos-rate-mirrors.timer ]; then
  systemctl unmask cachyos-rate-mirrors.timer 2>/dev/null || true
  systemctl enable cachyos-rate-mirrors.timer 2>/dev/null || true
fi

# ── 4. Cursors system-wide (no-clobber: keep runtime user updates) ──────────
if [ -d "$SKEL/.icons" ]; then
  cp -rn "$SKEL/.icons/." /usr/share/icons/ 2>/dev/null || true
fi

# ── 5. pacman ILoveCandy ─────────────────────────────────────────────────────
if ! grep -qE '^[[:space:]]*ILoveCandy([[:space:]]|$)' /etc/pacman.conf; then
  if grep -qE '^[[:space:]]*#[[:space:]]*ILoveCandy' /etc/pacman.conf; then
    sed -i -E 's/^([[:space:]]*)#[[:space:]]*(ILoveCandy[[:space:]]*)$/\1\2/' /etc/pacman.conf
  else
    sed -i '/^\[options\]/a ILoveCandy' /etc/pacman.conf
  fi
fi

# ── 6. Services ──────────────────────────────────────────────────────────────
for svc in sddm NetworkManager bluetooth power-profiles-daemon switcheroo-control ufw fstrim.timer; do
  systemctl enable "$svc" 2>/dev/null || true
done

touch "$SENTINEL"
