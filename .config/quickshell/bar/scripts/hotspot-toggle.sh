#!/bin/bash
# HyprCandy Wi-Fi hotspot — keeps the client Wi-Fi connection up and opens a
# virtual AP (ap0) on the SAME control channel (single-radio constraint),
# NAT'd through the active uplink. hostapd does the WPA2 state machine,
# dnsmasq the DHCP. Status reads are unprivileged; on/off self-elevate via
# `sudo` (a NOPASSWD sudoers entry for this script is installed by the
# HyprCandy installer/updater). Optional overrides in
# ~/.config/hyprcandy/hotspot.conf:  SSID_OVR / PASSWORD_OVR
set -uo pipefail

AP="ap0"
STATE="/run/hyprcandy-hotspot.state"    # "<upstream> <ssid>" while active
NMEXCL="/etc/NetworkManager/conf.d/99-hyprcandy-hotspot.conf"
HSCONF="/tmp/hyprcandy-hostapd.conf"    # fixed path; the on/off branch runs as root

# sudo/pkexec run the elevated branch as root with HOME=/root; recover the
# invoking user's real home so their hotspot.conf (SSID/password) is honoured.
if [ -n "${SUDO_UID:-}" ]; then
    REALHOME=$(getent passwd "$SUDO_UID" | cut -d: -f6)
elif [ -n "${PKEXEC_UID:-}" ]; then
    REALHOME=$(getent passwd "$PKEXEC_UID" | cut -d: -f6)
else
    REALHOME="$HOME"
fi
[ -n "$REALHOME" ] || REALHOME="$HOME"
CONF="$REALHOME/.config/hyprcandy/hotspot.conf"

hotspot_status() {
    [ -f "$STATE" ] && iw dev "$AP" info >/dev/null 2>&1 && echo on || echo off
}

do_on() {
    local upl ssid phych hsfreq hwmodeset pw psk ssid_raw phyinfo phyname hsctry hsdrv
    upl=$(nmcli -t -f DEVICE,STATE dev | awk -F: '$2=="connected" && $1!="lo"{print $1;exit}')
    [ -z "$upl" ] && { echo "no connected interface to share" >&2; exit 1; }

    phyinfo=$(iw dev "$upl" info)
    ssid_raw=$(printf '%s\n' "$phyinfo" | awk '/ssid/{print $2; exit}')
    [ -z "$ssid_raw" ] && ssid_raw="HyprCandy"
    phych=$(printf '%s\n' "$phyinfo" | awk '/channel/{print $2; exit}')
    hsfreq=$(printf '%s\n' "$phyinfo" | awk '/channel/{gsub(/[(),]/,"");print $3; exit}')
    phyname=$(printf '%s\n' "$phyinfo" | awk '/wiphy/{print "phy"$2; exit}')
    [ -z "$phyname" ] && phyname=phy0
    # mirror the client band: <4900 MHz → 2.4 GHz (g), else 5 GHz (a)
    [ "${hsfreq:-0}" -lt 4900 ] && hwmodeset=g || hwmodeset=a
    # Some drivers expose no AP interface mode at all — notably the proprietary
    # Broadcom 'wl' (e.g. BCM4313: supported modes are only IBSS + managed).
    # There hostapd can never start, so fail fast with a clear reason instead of
    # creating ap0, silently bailing, and leaving the button not lighting up.
    if ! iw phy "$phyname" info 2>/dev/null \
          | awk '/Supported interface modes:/{f=1;next} f&&/Band/{f=0} f' \
          | grep -qE '^[[:space:]]*\*[[:space:]]*AP[[:space:]]*$'; then
        hsdrv=$(basename "$(readlink -f "/sys/class/net/$upl/device/driver" 2>/dev/null)" 2>/dev/null)
        echo "This Wi-Fi card (driver: ${hsdrv:-unknown}) has no AP/hotspot mode — it can only be a client. To tether on Wi-Fi use a USB adapter (Intel/Atheros/MediaTek) or the open b43/brcmsmac driver." >&2
        exit 1
    fi
    # regulatory country so hostapd/firmware TX beacons+EAPOL on the 5 GHz
    # channel without falling back to a passive/scan state (a common cause of
    # clients looping in the WPA2 handshake on iwlwifi).
    hsctry=$(iw reg get 2>/dev/null | awk '/^country/{print substr($2,1,2); exit}')
    [ -n "$hsctry" ] || hsctry=00

    SSID_OVR="" PASSWORD_OVR=""
    [ -f "$CONF" ] && . "$CONF"
    ssid="${SSID_OVR:-${ssid_raw}-HS}"
    ssid="${ssid:0:32}"
    pw="${PASSWORD_OVR:-hyprcandy123}"
    # WPA2 pre-shared keys must be 8-63 ASCII chars (or 64 raw hex). A shorter
    # key makes wpa_passphrase emit no psk and hostapd then aborts with an empty
    # PSK — the AP never broadcasts, so clients see nothing. Fail fast & clearly
    # before touching the system.
    if [ "${#pw}" -lt 8 ] || [ "${#pw}" -gt 63 ]; then
        echo "hotspot password must be 8-63 characters (got ${#pw}); set PASSWORD_OVR in ~/.config/hyprcandy/hotspot.conf or use Control Center ▸ System ▸ Hotspot" >&2
        exit 1
    fi
    # wpa_passphrase emits a network={} block with a "#psk=" comment line and a
    # real "psk=<hex>" line; take only the hex (robust to spaces in the phrase).
    psk=$(wpa_passphrase "$ssid" "$pw" | sed -n 's/^[[:space:]]*psk=\(.*\)/\1/p' | head -1)

    # hold NetworkManager off the virtual iface for the session
    printf '[keyfile]\nunmanaged-devices=interface-name:%s\n' "$AP" >"$NMEXCL"
    kill -HUP "$(pidof NetworkManager)" 2>/dev/null || true
    sleep 1

    # Reclaim a clean slate on EVERY start. A leftover ap0 — orphaned from a
    # crashed run (a live hostapd keeps the iface, so a plain "iw del" can't
    # remove it) or an older version — otherwise collides
    # ("RTNETLINK: Name not unique on network") or eats the radio's AP slot.
    # Kill our daemons first, then drop the iface and any stale ap0 rules, so
    # turning the hotspot on is always self-healing. (This deliberately takes
    # over ap0 — HyprCandy is the system-level hotspot.)
    for pf in /run/hyprcandy-hostapd.pid /run/hyprcandy-hotspot.pid; do
        [ -f "$pf" ] && kill "$(cat "$pf")" 2>/dev/null || true
    done
    pkill -f "hostapd .*$HSCONF" 2>/dev/null || true   # orphaned AP whose pidfile is gone
    pkill -f "dnsmasq -i $AP" 2>/dev/null || true
    if iw dev "$AP" info >/dev/null 2>&1; then
        ip link set "$AP" down 2>/dev/null || true
        iw dev "$AP" del 2>/dev/null || true
    fi
    iptables -D INPUT   -i "$AP" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$AP" -o "$upl" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -o "$AP" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true
    rm -f /run/hyprcandy-hostapd.pid /run/hyprcandy-hotspot.pid
    iw phy "$phyname" interface add "$AP" type __ap
    ip link set "$AP" up
    ip addr flush dev "$AP"
    ip addr add 10.42.0.1/24 dev "$AP"

    cat >"$HSCONF" <<EOF
ctrl_interface=/var/run/hostapd
interface=$AP
driver=nl80211
ssid=$ssid
hw_mode=$hwmodeset
channel=$phych
country_code=$hsctry
ieee80211n=1
ht_capab=
wpa=2
wpa_pairwise=CCMP
rsn_pairwise=CCMP
wpa_psk=$psk
EOF
    hostapd -B -P /run/hyprcandy-hostapd.pid "$HSCONF" || {
        echo "hostapd failed to start (see $HSCONF)" >&2
        ip link set "$AP" down 2>/dev/null; iw dev "$AP" del 2>/dev/null
        rm -f "$NMEXCL" "$HSCONF"; kill -HUP "$(pidof NetworkManager)" 2>/dev/null || true
        exit 1; }

    sysctl -qw net.ipv4.ip_forward=1
    iptables -t nat   -C POSTROUTING -o "$upl" -j MASQUERADE 2>/dev/null || \
        iptables -t nat -A POSTROUTING -o "$upl" -j MASQUERADE
    iptables -C FORWARD -i "$AP" -o "$upl" -j ACCEPT 2>/dev/null || \
        iptables -I FORWARD 1 -i "$AP" -o "$upl" -j ACCEPT
    iptables -C FORWARD -o "$AP" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
        iptables -I FORWARD 1 -o "$AP" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    # A default-deny INPUT (e.g. active UFW) otherwise drops the clients'
    # DHCPDISCOVER to 10.42.0.1:67, so they complete WPA but never get an IP and
    # loop in "connecting". Accept host-terminated traffic from the AP subnet
    # (only associated stations can send on ap0). Inserted ahead of UFW's chains.
    iptables -C INPUT -i "$AP" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -i "$AP" -j ACCEPT

    pkill -f "dnsmasq -i $AP" 2>/dev/null
    # DHCP-only (--port=0: systemd-resolved already owns :53); advertise the AP
    # as gateway + public DNS so clients resolve without a local resolver.
    dnsmasq -i "$AP" --port=0 --no-resolv \
        --dhcp-range=10.42.0.50,10.42.0.250,12h \
        --dhcp-option=3,10.42.0.1 --dhcp-option=6,1.1.1.1,8.8.8.8 \
        --pid-file=/run/hyprcandy-hotspot.pid || {
        echo "dnsmasq failed to start" >&2; exit 1; }

    printf '%s %s' "$upl" "$ssid" >"$STATE"
    echo "on $ssid"
}

do_off() {
    local upl
    upl=$(awk '{print $1}' "$STATE" 2>/dev/null)
    [ -f /run/hyprcandy-hostapd.pid ] && kill "$(cat /run/hyprcandy-hostapd.pid)" 2>/dev/null
    [ -f /run/hyprcandy-hotspot.pid ] && kill "$(cat /run/hyprcandy-hotspot.pid)" 2>/dev/null
    [ -n "$upl" ] && {
        iptables -t nat -D POSTROUTING -o "$upl" -j MASQUERADE 2>/dev/null
        iptables -D FORWARD -i "$AP" -o "$upl" -j ACCEPT 2>/dev/null
        iptables -D FORWARD -o "$AP" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null
    }
    iptables -D INPUT -i "$AP" -j ACCEPT 2>/dev/null
    ip link set "$AP" down 2>/dev/null
    iw dev "$AP" del 2>/dev/null
    rm -f "$STATE" /run/hyprcandy-hostapd.pid /run/hyprcandy-hotspot.pid "$HSCONF"
    rm -f "$NMEXCL"; kill -HUP "$(pidof NetworkManager)" 2>/dev/null || true
    echo off
}

case "${1:-status}" in
    status)
        hotspot_status
        ;;
    on)
        [ "$(id -u)" = 0 ] || exec sudo -n "$0" on
        do_on
        ;;
    off)
        [ "$(id -u)" = 0 ] || exec sudo -n "$0" off
        do_off
        ;;
    toggle)
        [ "$(id -u)" = 0 ] || exec sudo -n "$0" toggle
        if [ -f "$STATE" ] && iw dev "$AP" info >/dev/null 2>&1; then do_off; else do_on; fi
        ;;
    count)
        # Number of associated stations on the AP. iw station dump needs root,
        # so self-elevate like the mutation paths (covered by the sudo entry).
        [ "$(id -u)" = 0 ] || exec sudo -n "$0" count
        if [ -f "$STATE" ] && iw dev "$AP" info >/dev/null 2>&1; then
            iw dev "$AP" station dump 2>/dev/null | grep -c '^Station'
        else
            echo 0
        fi
        ;;
    *)
        echo "usage: $0 {status|on|off|toggle|count}" >&2; exit 2
        ;;
esac
