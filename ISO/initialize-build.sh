#!/usr/bin/env bash
# HyprCandy ISO build environment bootstrap.
#
# Recreates ~/CachyOS-HyprCandy from scratch (or refreshes an existing one) so a
# build can be started at any time:
#   1. build dependencies
#   2. shallow clone of CachyOS/CachyOS-Live-ISO (only if missing)
#   3. apply the saved HyprCandy profile overlay (ISO/profile/)
#   4. bootstrap the [hc-local] prebaked package repo from host caches
#   5. stage the skel payload via prepare-payload.sh
#
# Runnable from any directory. Never resets an existing clone: it may carry
# uncommitted fixes. The overlay in ISO/profile/ is the source of truth.
set -euo pipefail

ISO_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
WORK="$HOME/CachyOS-HyprCandy"
PROFILE="$WORK/cachyos-archiso"

log() { printf '\n==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

log "Build dependencies"
# Only elevate when something is actually missing, so re-runs on a prepared
# host need no sudo password at all.
if ! pacman -Q archiso mkinitcpio-archiso squashfs-tools grub git rsync &> /dev/null; then
    sudo pacman -S --needed --noconfirm archiso mkinitcpio-archiso squashfs-tools grub git rsync
fi

mkdir -p "$WORK"
cd "$WORK"

if [[ ! -d cachyos-archiso/.git ]]; then
    log "Cloning CachyOS-Live-ISO (shallow)"
    git clone --depth 1 https://github.com/CachyOS/CachyOS-Live-ISO cachyos-archiso
else
    log "Reusing existing clone (left untouched apart from the overlay)"
fi

# Upstream's EXIT trap prints "An unknown error has occurred" even on success
# (trap_exit never checks the exit status). Make it status-aware so real
# failures stay distinguishable in build logs. Idempotent.
if grep -qF "trap 'trap_exit EXIT" "$PROFILE/buildiso.sh"; then
    log "Patching buildiso.sh success-path EXIT trap"
    _s=$(<"$PROFILE/buildiso.sh")
    _old="trap 'trap_exit EXIT \"\$(gettext \"An unknown error has occurred. Exiting...\")\"' EXIT"
    _new="trap '_rc=\$?; trap - EXIT; [ \"\$_rc\" -eq 0 ] || trap_exit EXIT \"\$(gettext \"An unknown error has occurred. Exiting...\")\"' EXIT"
    printf '%s\n' "${_s//"$_old"/"$_new"}" > "$PROFILE/buildiso.sh"
fi

# Fresh clones ship upstream util-iso.sh without the ESP-hook deferral patch
# (limine/snap-pac alpm hooks need a mounted FAT32 ESP the build chroot lacks).
# Insert the shared block into modify_mkarchiso; it patches /usr/bin/mkarchiso
# at build time. Idempotent.
if ! grep -q '_hc_late_pkgs' "$PROFILE/util-iso.sh"; then
    log "Patching util-iso.sh modify_mkarchiso with ESP-hook deferral"
    python3 - "$PROFILE/util-iso.sh" "$ISO_DIR/esp-hooks-block.sh.inc" << 'PYEOF'
import sys
target, snippet = sys.argv[1], sys.argv[2]
s = open(target).read()
block = open(snippet).read()
anchor = '        msg "mkarchiso is already patched!"\n    fi\n}'
assert anchor in s, 'modify_mkarchiso anchor changed'
s = s.replace(anchor, '        msg "mkarchiso is already patched!"\n    fi\n' + block.rstrip('\n') + '\n}', 1)
open(target, 'w').write(s)
PYEOF
fi

log "Applying saved HyprCandy profile overlay"
# --delete keeps the overlay authoritative for everything except the generated
# skel payload, which prepare-payload.sh owns.
# No -o/-g/-p: buildiso creates some airootfs/etc files as root, and preserving
# ownership/modes onto them would EPERM for an unprivileged run. Exec bits are
# restored explicitly below; build-time ownership is normalized by
# root/customize_airootfs.sh inside the pacstrap chroot.
rsync -rlt --delete --no-o --no-g --no-p --exclude='etc/skel/' \
    "$ISO_DIR/profile/airootfs/" "$PROFILE/archiso/airootfs/"
chmod 755 "$PROFILE/archiso/airootfs/root/customize_airootfs.sh" \
          "$PROFILE/archiso/airootfs/usr/local/bin/"* \
          "$PROFILE/archiso/airootfs/usr/local/lib/hyprcandy/"*.sh 2>/dev/null || true
install -Dm644 "$ISO_DIR/profile/packages_desktop.x86_64" "$PROFILE/archiso/packages_desktop.x86_64"
install -Dm644 "$ISO_DIR/profile/pacman.conf"          "$PROFILE/archiso/pacman.conf"
install -Dm644 "$ISO_DIR/profile/profiledef.sh"        "$PROFILE/archiso/profiledef.sh"
install -Dm644 "$ISO_DIR/profile/grub/grub.cfg"        "$PROFILE/archiso/grub/grub.cfg"
install -Dm644 "$ISO_DIR/profile/syslinux/archiso_sys-linux.cfg" "$PROFILE/archiso/syslinux/archiso_sys-linux.cfg"
install -Dm644 "$ISO_DIR/profile/syslinux/archiso_pxe-linux.cfg" "$PROFILE/archiso/syslinux/archiso_pxe-linux.cfg"

log "Bootstrapping [hc-local] prebaked repo"
mkdir -p "$WORK/localrepo"
cd "$WORK/localrepo"

# name|source (file, or directory whose newest *.pkg.tar.zst is used)
PKGS=(
    "hyprcandy-qs|$HOME/.cache/hyprcandy-qs.pkg.tar.zst"
    "darkly-bin|$HOME/.cache/paru/clone/darkly-bin"
    "easyeffects-bundy01-presets|$HOME/.cache/paru/clone/easyeffects-bundy01-presets"
    "gpu-screen-recorder-qt|$HOME/.cache/paru/clone/gpu-screen-recorder-qt"
    "matugen-bin|$HOME/.cache/paru/clone/matugen-bin"
    "pipes.sh|$HOME/.cache/paru/clone/pipes.sh"
    "pyprland|$HOME/.cache/paru/clone/pyprland"
    "python-pywal16|$HOME/.cache/paru/clone/python-pywal16"
    "python-pywalfox|$HOME/.cache/paru/clone/python-pywalfox"
    "sddm-sugar-candy-git|$HOME/.cache/paru/clone/sddm-sugar-candy-git"
    "ttf-dejavu-sans-code|$HOME/.cache/paru/clone/ttf-dejavu-sans-code"
)
for entry in "${PKGS[@]}"; do
    name=${entry%%|*}
    src=${entry#*|}
    if compgen -G "$name-*.pkg.tar.zst" > /dev/null || [[ -f "$name.pkg.tar.zst" ]]; then
        continue  # already prebaked
    fi
    if [[ -d "$src" ]]; then
        newest=$(ls -t "$src"/*.pkg.tar.zst 2>/dev/null | head -1 || true)
        [[ -n "$newest" ]] || die "no built package for $name in $src (build it with paru first)"
        cp -f "$newest" .
    elif [[ -f "$src" ]]; then
        cp -f "$src" .
    else
        die "missing source for $name: $src"
    fi
    echo "prebaked: $name"
done
# Rebuild the repo database from exactly what is present.
rm -f hc-local.db hc-local.db.tar.gz hc-local.db.tar.gz.old \
      hc-local.files hc-local.files.tar.gz hc-local.files.tar.gz.old
repo-add hc-local.db.tar.gz ./*.pkg.tar.zst

log "Staging skel payload"
"$ISO_DIR/prepare-payload.sh"

log "Ready to build"
cat << EOF
cd $PROFILE
sudo ./buildiso.sh -p desktop -v -w

Output ISO: $PROFILE/out/desktop/
EOF