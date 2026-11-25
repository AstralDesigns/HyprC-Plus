#!/bin/bash
# HyprCandy OFFLINE installer launcher.
# Overrides upstream calamares-online.sh (cachyos-hello invokes this exact
# path). Uses Calamares unpackfs: the baked airootfs is copied to disk, so
# the install needs no network and finishes in seconds.

main() {
    local log="/home/liveuser/cachy-install.log"
    local mode="offline"

    local SYSTEM=""
    if [ -d /sys/firmware/efi ]; then
        SYSTEM="UEFI SYSTEM"
    else
        SYSTEM="BIOS/MBR SYSTEM"
    fi

    local ISO_VERSION="$(cat /etc/version-tag 2>/dev/null)"
    echo "USING ISO VERSION: ${ISO_VERSION:-unknown}"

    # Best-effort only: offline install must work without network.
    timedatectl set-ntp true 2>/dev/null || true

    {
        echo "########## HyprCandy offline install log"
        echo "########## Started (UTC): $(date -u "+%x %X")"
        echo "########## ISO version: ${ISO_VERSION:-unknown}"
        echo "########## System: $SYSTEM"
    } >> "$log" 2>/dev/null

    sudo cp "/usr/share/calamares/settings_${mode}.conf" /etc/calamares/settings.conf
    # Upstream's offline sequence has no bootloader chooser; all four
    # bootloaders are baked, so expose the same choice online users get
    # (pure UI step, no network involved).
    if [ "$mode" = "offline" ]; then
        sed -i '0,/^  - keyboard$/s//  - keyboard\n  - packagechooser@bootloader/' \
            /etc/calamares/settings.conf
    fi
    exec pkexec-wrapper calamares -D6 >> "$log" 2>&1
}

main "$@"
