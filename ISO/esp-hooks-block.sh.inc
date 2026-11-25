    # HyprCandy: limine-mkinitcpio-hook ships an /etc/pacman.d/hooks override of
    # the standard mkinitcpio alpm hook, and its hooks (80-limine-efi-deploy,
    # 90-mkinitcpio-install) hard-require a mounted FAT32 ESP. In the build
    # chroot there is none: the FAT32 errors are non-fatal, mkinitcpio never
    # runs, and the build later aborts on missing initramfs. Defer these
    # packages to a second pacman pass with an empty hook dir.
    if ! grep -q '_hc_late_pkgs' /usr/bin/mkarchiso || [ "$(grep -cF 'umount -l -R' /usr/bin/mkarchiso)" -lt 3 ]; then
        msg "Patching mkarchiso with hookless pass for ESP-dependent packages..."
        sudo python3 - << 'HCPY'
p = '/usr/bin/mkarchiso'
s = open(p).read()
old = '    _pacstrap_options=(-C "${work_dir}/${buildmode}.pacman.conf" -c -G -M -- "${pacstrap_dir}" "${buildmode_pkg_list[@]}")'
new = (
    '    local -a _hc_main_pkgs=() _hc_late_pkgs=()\n'
    '    local _hc_p\n'
    '    for _hc_p in "${buildmode_pkg_list[@]}"; do\n'
    '        case "${_hc_p}" in\n'
    '            limine-mkinitcpio-hook|limine-snapper-sync|snap-pac) _hc_late_pkgs+=("${_hc_p}") ;;\n'
    '            *) _hc_main_pkgs+=("${_hc_p}") ;;\n'
    '        esac\n'
    '    done\n'
    '    _pacstrap_options=(-C "${work_dir}/${buildmode}.pacman.conf" -c -G -M -- "${pacstrap_dir}" "${_hc_main_pkgs[@]}")'
)
if old in s and '_hc_main_pkgs' not in s:
    s = s.replace(old, new, 1)
old2 = '    _msg_info "Done! Packages installed successfully."'
new2 = (
    '    if (( ${#_hc_late_pkgs[@]} )); then\n'
    '        _msg_info "Installing ESP-hook packages in deferred pass (initramfs already built; ESP hook warnings here are expected)..."\n'
    '        mkdir -p "${work_dir}/hc-empty-hooks"\n'
    '        pacman -r "${pacstrap_dir}" --config "${work_dir}/${buildmode}.pacman.conf" \\\n'
    '            --noconfirm --needed --hookdir "${work_dir}/hc-empty-hooks" -S "${_hc_late_pkgs[@]}"\n'
    '    fi\n'
    '\n'
    '    _msg_info "Done! Packages installed successfully."'
)
if old2 in s and '_hc_late_pkgs' not in s:
    s = s.replace(old2, new2, 1)
# Surviving chroot pseudo-mounts (pacstrap/arch-chroot trap leaks) would be
# baked into the squashfs by mksquashfs (host /proc snapshot: empty files for
# unreadable pseudo-files, real cmdline/environ content for readable ones).
# Lazy-detach them right before BOTH squashfs branches; dirs stay as empty
# mountpoints. No-op when nothing is mounted.
old3 = '    _msg_info "Creating SquashFS image, this may take some time..."'
new3 = (
    '    umount -l -R "${pacstrap_dir}/proc" "${pacstrap_dir}/sys" "${pacstrap_dir}/dev" "${pacstrap_dir}/tmp" 2>/dev/null || true\n'
    + old3
)
if old3 in s and 'umount -l -R' not in s:
    s = s.replace(old3, new3)
# arch-chroot's exit trap can ALSO fail with "target is busy" on sysfs/efivars;
# the surviving mount then kills mkarchiso's cleanup `find` (sysfs I/O errors)
# long before squashfs. Detach again right after the customize hook.
old4 = '        _msg_info "Done! customize_airootfs.sh run successfully."'
new4 = (
    old4 + '\n'
    '        umount -l -R "${pacstrap_dir}/proc" "${pacstrap_dir}/sys" "${pacstrap_dir}/dev" "${pacstrap_dir}/tmp" 2>/dev/null || true'
)
if old4 in s and new4 not in s:
    s = s.replace(old4, new4, 1)
assert '_hc_late_pkgs' in s and s.count('umount -l -R') >= 3, 'patch did not apply'
open(p, 'w').write(s)
HCPY
    else
        msg "mkarchiso hookless-pass patch already applied!"
    fi