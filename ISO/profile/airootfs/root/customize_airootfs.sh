#!/usr/bin/env bash
# Runs inside the pacstrap chroot AFTER packages are installed (mkarchiso
# _make_customize_airootfs). Package-shipped files must be overridden here,
# not in airootfs/ overlays: pacman refuses to overwrite files that already
# exist when airootfs is copied before pacstrap.
set -euo pipefail

# HyprCandy default shell: zsh first, fish fallback (upstream prefers fish;
# install.sh chsh -s zsh parity wins). Overrides cachyos-calamares script.
cat > /etc/calamares/scripts/shell-setup << "SHELLSETUP"
#!/usr/bin/env bash
user="$1"
for shell in "zsh" "fish"; do
    if [ -e "/bin/$shell" ]; then
        chsh -s "/bin/${shell}" "$user" && break
    fi
done
SHELLSETUP
chmod 755 /etc/calamares/scripts/shell-setup

# buildiso's prepare_profile re-creates the display-manager alias pointing at
# plasmalogin on EVERY build (after airootfs is staged), so the sddm relink must
# happen here, post-pacstrap, to survive into the image.
ln -sfn /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service

# VM friendliness: allow Hyprland's software (llvmpipe) renderer on QXL/virtio
# without 3D acceleration. pam_env feeds /etc/environment to every login
# session incl. SDDM autologin; harmless on real GPUs (fallback only).
grep -q WLR_RENDERER_ALLOW_SOFTWARE /etc/environment || \
    echo 'WLR_RENDERER_ALLOW_SOFTWARE=1' >> /etc/environment

# Normalize ownership left over from the build host: airootfs overlays can
# arrive owned by the building user (uid 1000). Security-sensitive /etc files,
# system units and /etc/skel must be root-owned in the live image. Runs after
# mkarchiso copied skel into user homes, so those copies are unaffected.
chown root:root /etc/passwd /etc/group /etc/shadow /etc/gshadow /etc/sudoers 2>/dev/null || true
chmod 0644 /etc/passwd /etc/group 2>/dev/null || true
chmod 0400 /etc/shadow /etc/gshadow 2>/dev/null || true
chown -R root:root /etc/skel /etc/systemd/system /etc/sddm.conf.d 2>/dev/null || true

