#!/usr/bin/env bash
# ── sshd.sh ──────────────────────────────────────────────────────────────────
# Remote-Login (SSH daemon) status + toggle for the ControlCenter SSH sub-tab.
#
#   sshd.sh status   -> key=value line (no privilege): unit / active / enabled
#   sshd.sh on       -> pkexec systemctl enable --now <unit>   (prompts)
#   sshd.sh off      -> pkexec systemctl disable --now <unit>  (prompts)
#
# Detects the unit name (Debian/Arch ship `ssh`, Fedora `sshd`) so the caller
# never hard-codes it. If no unit exists, status reports `unit=none`.
set -u
verb="${1:-status}"

unit=""
for u in ssh sshd; do
    if systemctl list-unit-names "$u.service" 2>/dev/null | grep -q "^$u\.service"; then
        unit="$u"; break
    fi
done

case "$verb" in
    status)
        if [ -z "$unit" ]; then
            echo "unit=none active=unknown enabled=unknown"
            exit 0
        fi
        a="$(systemctl is-active "$unit" 2>/dev/null)"
        e="$(systemctl is-enabled "$unit" 2>/dev/null)"
        echo "unit=$unit active=${a:-unknown} enabled=${e:-unknown}"
        ;;
    on)
        [ -z "$unit" ] && { echo "err no sshd unit found"; exit 3; }
        pkexec systemctl enable --now "$unit"
        ;;
    off)
        [ -z "$unit" ] && { echo "err no sshd unit found"; exit 3; }
        pkexec systemctl disable --now "$unit"
        ;;
    *)
        echo "err unknown verb"
        exit 1
        ;;
esac
