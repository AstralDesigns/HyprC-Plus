# HyprCandy CachyOS ISO — Build Directions

How to (re)create the `~/CachyOS-HyprCandy` build folder and produce the custom
CachyOS ISO carrying the HyprCandy desktop. Intended for a fresh install handled
by the maintainer or a trusted party.

The ISO is an **offline (unpackfs) Calamares install**: the installed system is
the exact baked squashfs rootfs. Every package in
`ISO/profile/packages_desktop.x86_64` installs regardless of what the build host
has installed; the host only supplies the foreign/AUR prebaked packages and the
dotfiles/config seeds.

---

## 0. Prerequisites (build host)

- Arch/CachyOS host with a **working HyprCandy desktop already installed**
  (via `.candyinstall/install.sh`). `prepare-payload.sh` seeds runtime-generated
  state from the live host and aborts if any of these are missing:
  - `~/.config/wallpaper/wallpaper.ini`
  - `~/.config/hypr/hyprviz.lua` (generated at runtime, not in git)
  - `~/.oh-my-zsh/`, `~/.cargo/bin/{wallust,cargo-install-update,cargo-install-update-config}`
  - `~/.cache/quickshell/{overview,wallpaper}/*Colors.qml` (4 files)
  - prebuilt agent-app: `~/.hyprcandy/GJS/hyprcandydock/agent-app/dist/index.html`
    (run `agent-app/build.sh` if absent)
- **Prebaked foreign packages** available in host caches (the `[hc-local]`
  repo). `initialize-build.sh` copies them and dies if a source is missing:
  - `~/.cache/hyprcandy-qs.pkg.tar.zst` (patched Quickshell; CI release asset)
  - newest `*.pkg.tar.zst` in each `~/.cache/paru/clone/<pkg>` for:
    `darkly-bin`, `easyeffects-bundy01-presets`, `gpu-screen-recorder-qt`,
    `matugen-bin`, `pipes.sh`, `pyprland`, `python-pywal16`, `python-pywalfox`,
    `sddm-sugar-candy-git`, `ttf-dejavu-sans-code`
  - On a fresh host, build these with paru first (or copy the artifacts from a
    prepared machine) before running the scripts.
- Build dependencies are installed automatically by `initialize-build.sh`
  (`archiso`, `mkinitcpio-archiso`, `squashfs-tools`, `grub`, `git`, `rsync`;
  sudo needed only when something is missing). `stow`, `lua5.4` (luac) and
  `python3` should also be present.

## 1. Get the sources

```bash
# Dotfiles repo — the staging source of truth (stow layout).
git clone https://github.com/AstralDesigns/HyprC-Plus ~/.HyprC-Plus

# Live installed tree (normally already present from install.sh).
# If starting truly fresh, install HyprCandy first, then:
git clone https://github.com/AstralDesigns/HyprC-Plus ~/.hyprcandy
```

The build scripts and the authoritative profile live in `ISO/` inside the repo
(`~/.HyprC-Plus/ISO/`). Both scripts resolve their own location, so they are
runnable from any directory and from either tree.

> If `ISO/` is absent from a fresh clone, it has not been pushed upstream yet —
> copy it from a prepared machine into `~/.HyprC-Plus/ISO/` before continuing.

## 2. Initialize the build folder (staging)

```bash
bash ~/.HyprC-Plus/ISO/initialize-build.sh
```

Creates/refreshes `~/CachyOS-HyprCandy`:

1. installs missing build dependencies;
2. shallow-clones `CachyOS/CachyOS-Live-ISO` into `cachyos-archiso/`
   (an existing clone is **never reset** — it may carry uncommitted fixes);
3. makes `buildiso.sh`'s EXIT trap status-aware (upstream prints "unknown
   error" even on success) and embeds the ESP-hook deferral patch into
   `util-iso.sh` (limine/snap-pac alpm hooks need a mounted FAT32 ESP the build
   chroot lacks; they are deferred to a second pacman pass). Both idempotent;
4. applies the saved overlay from `ISO/profile/` — `packages_desktop.x86_64`,
   `pacman.conf` (wires `[hc-local]`), `profiledef.sh`, bootloader configs and
   the `airootfs/` root-side files (customize hook, system-setup, Calamares
   launcher). `ISO/profile/` is the **source of truth**: edit there, then
   re-run this script (or copy into the clone) — never edit only the clone;
5. bootstraps `~/CachyOS-HyprCandy/localrepo` (`hc-local.db.tar.gz`) from the
   host caches listed above;
6. stages the `airootfs/etc/skel` payload by calling `prepare-payload.sh`.

## 3. Restage the payload (after dotfile changes)

```bash
bash ~/.HyprC-Plus/ISO/prepare-payload.sh
```

Wipes and rebuilds `airootfs/etc/skel` from `~/.HyprC-Plus` + host seeds:
dotfiles (pre-stowed, race-free first login), prebuilt agent-app dist, shells,
wallpaper.ini + Pictures wallpapers, dock pinned apps (live-only Calamares pin,
stripped by firstboot on installed systems), quickshell cache colors, and the
live-session Lua block (Calamares autostart + wallpaper retry, inserted BEFORE
custom.lua's trailing `return true`). Ends with sanity checks incl. `luac -p`.
Safe to re-run any time **no build is running**. It also forces zstd-15
squashfs compression (permanent decision: ~30 min builds vs ~2 h with xz).

## 4. Build

```bash
cd ~/CachyOS-HyprCandy/cachyos-archiso
sudo ./buildiso.sh -p desktop -v -w
```

- ~30 minutes. Output: `out/desktop/cachyos-desktop-linux-<date>.iso`
  (+ sha1/sha256/pkgs.txt). `-w` removes the build dir on success.
- Early checkpoint (once the build starts patching):
  `grep -cF 'umount -l -R' /usr/bin/mkarchiso` must print **3**
  (pseudo-mount leak guards before both squashfs branches + post-customize).
- Known harmless log noise: nbd-client ERROR (PXE-NBD only), firmware warnings,
  deferred-pass FAT32/snap-pac hook errors, keyring/SBAT chatter, syslinux
  optdeps, rate-mirrors masked-unit scriptlet.
- **Interrupted build cleanup** (before any `rm -rf build`):
  ```bash
  sudo umount -R ~/CachyOS-HyprCandy/cachyos-archiso/build/x86_64/airootfs 2>/dev/null
  sudo rm -rf ~/CachyOS-HyprCandy/cachyos-archiso/build
  ```
  Never remove the build dir while chroot mounts are live (devtmpfs shares the
  host /dev superblock). After a host reboot the mounts are gone and a plain
  `sudo rm -rf build` is safe.

## 5. When to rebuild

Rebuild the ISO when **upstream CachyOS moves**, per our own criteria — e.g.:

- new kernel releases (`linux-cachyos` / LTS variants) or mesa/NVIDIA stack bumps;
- CachyOS package-set changes worth shipping (new tools, security updates);
- Hyprland/Quickshell ecosystem updates that need fresh prebaked binaries.

Routine HyprCandy dotfile/app changes do **not** require an ISO rebuild: they
flow through the standard internal update channel (pushed upstream via
`~/.HyprC-Plus`, pulled on user machines, surfaced by the Updates popup).

## 6. Test pass (summary)

virt-manager VM: plain UEFI (`OVMF_CODE.4m.fd`, not secboot), Q35, 2 vCPUs,
≥4 GB RAM, VirtIO disk ≥40 GB, SATA CDROM boot-first (eject ISO or reorder at
first post-install reboot), Display Spice with **OpenGL OFF**, Video Virtio
**3D OFF**, NIC virtio/NAT, channels qemu-ga + spice.

Live: SDDM autologin → wallpaper + full keybinds + dock pins (incl. Calamares)
→ Calamares auto-launch with bootloader chooser → install → reboot.
Installed: zsh/dotfiles/greeter, `journalctl -u hyprcandy-system-setup`,
`journalctl --user -u hyprcandy-firstboot`, chosen bootloader boots, dock pins
WITHOUT calamares. Then bare-metal USB pass.