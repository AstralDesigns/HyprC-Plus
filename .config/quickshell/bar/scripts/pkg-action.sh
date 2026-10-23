#!/usr/bin/env bash
# ── pkg-action.sh ────────────────────────────────────────────────────────────
# Privileged package transaction runner for the launcher Packages tab.
# Launched INSIDE a floating-installer kitty so the user watches live output and
# authenticates in the terminal (the helper's sudo prompt, or pkexec when no
# helper is present). The tab itself never sees a password.
#
#   pkg-action.sh <install|uninstall|update> <group>...
#   group = native:a,b | aur:c | flatpak:org.a,org.b
#
# An AUR helper (paru/yay) is the preferred front-end: it covers the native
# repos AND the AUR in a single transaction and self-elevates via sudo, so a
# mixed selection is one prompt instead of a split pacman + paru pair. Only when
# no helper exists do we fall back to `pkexec pacman`. Flatpak always stays
# user-scoped (running it wholesale under root would target the wrong install).
set -u

VERB="${1:-}"
shift || true
if [ -z "$VERB" ]; then
    echo "usage: pkg-action.sh <install|uninstall|update> <group>..." >&2
    exit 2
fi

AUR_HELPER="$(command -v paru || command -v yay || true)"

NATIVE=(); AUR=(); FP=()
for grp in "$@"; do
    case "$grp" in
        native:*)   IFS=',' read -ra _a <<< "${grp#native:}";   NATIVE+=("${_a[@]}") ;;
        aur:*)      IFS=',' read -ra _a <<< "${grp#aur:}";      AUR+=("${_a[@]}") ;;
        flatpak:*)  IFS=',' read -ra _a <<< "${grp#flatpak:}";  FP+=("${_a[@]}") ;;
    esac
done

# pacman-side selection = native + AUR (installed AUR lives in the same local
# DB, so the helper treats both uniformly). Prefer the helper; else pacman+pkexec.
PKGS=( "${NATIVE[@]}" "${AUR[@]}" )
if [ -n "$AUR_HELPER" ]; then
    PKG="$AUR_HELPER"; PRIV=()        # helper self-elevates via sudo
else
    PKG="pacman"; PRIV=(pkexec)       # bare pacman needs explicit elevation
fi

banner() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Overall outcome of the transaction: ok | cancelled | blocked | failed.
# The last non-zero command decides the wording, so a mixed run still reports
# the most informative status. `run <kind> <cmd...>` keeps a command's raw exit
# code out of the messaging; `kind=remove` maps a non-zero exit to "blocked"
# (a reverse-dependency refusal or an answered-no prompt) rather than "failed".
FINAL="ok"
run() {
    local kind="$1"; shift
    "$@"
    local rc=$?
    if [ "$rc" -ne 0 ]; then
        case "$rc" in
            126|127) FINAL="cancelled" ;;                       # pkexec: auth declined
            130)     FINAL="cancelled" ;;                       # SIGINT: interrupted
            *)       [ "$kind" = "remove" ] && FINAL="blocked" || FINAL="failed" ;;
        esac
    fi
    return 0
}

case "$VERB" in
    install)
        if [ "${#PKGS[@]}" -gt 0 ]; then
            banner "Installing packages: ${PKGS[*]}"
            run install "${PRIV[@]}" "$PKG" -S --needed "${PKGS[@]}"
        fi
        if [ "${#FP[@]}" -gt 0 ]; then
            banner "Installing Flatpak apps: ${FP[*]}"
            run install flatpak install -y --noninteractive flathub "${FP[@]}"
        fi
        ;;
    uninstall)
        # Interactive on purpose (no --noconfirm): the helper/pacman prints the
        # transaction and asks, so the user answers y/n. A reverse-dependency
        # refusal exits non-zero WITHOUT removing anything -> "blocked".
        if [ "${#PKGS[@]}" -gt 0 ]; then
            banner "Removing packages: ${PKGS[*]}"
            run remove "${PRIV[@]}" "$PKG" -Rns "${PKGS[@]}"
        fi
        if [ "${#FP[@]}" -gt 0 ]; then
            banner "Removing Flatpak apps: ${FP[*]}"
            run remove flatpak uninstall -y --noninteractive "${FP[@]}"
        fi
        ;;
    update)
        if [ "${#PKGS[@]}" -gt 0 ]; then
            banner "Updating packages: ${PKGS[*]}"
            run update "${PRIV[@]}" "$PKG" -S --needed "${PKGS[@]}"
        fi
        if [ "${#FP[@]}" -gt 0 ]; then
            banner "Updating Flatpak apps: ${FP[*]}"
            run update flatpak update -y --noninteractive "${FP[@]}"
        fi
        ;;
    *)
        echo "unknown verb: $VERB" >&2
        exit 2
        ;;
esac

case "$FINAL" in
    ok)
        printf '\n\033[1;32m==> Done — transaction complete.\033[0m\n' ;;
    cancelled)
        printf '\n\033[1;33m==> Cancelled — authentication was declined or interrupted. No changes were made.\033[0m\n' ;;
    blocked)
        printf '\n\033[1;33m==> Nothing removed — pacman refused the transaction (a reverse dependency, or you answered no). See the messages above.\033[0m\n' ;;
    failed)
        printf '\n\033[1;31m==> Finished with errors — review the output above.\033[0m\n' ;;
esac

[ "$FINAL" = ok ] && exit 0 || exit 1
