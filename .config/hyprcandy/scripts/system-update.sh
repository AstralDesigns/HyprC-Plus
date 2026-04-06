#!/usr/bin/env bash

YELLOW='\033[1;33m'
NC='\033[0m'

print_warning() { echo -e "${YELLOW}WARNING:${NC} $1"; }
print_status() { echo "$1"; }

# Check release
if [ ! -f /etc/arch-release ]; then
  exit 0
fi

pkg_installed() {
  local pkg=$1
  if pacman -Qi "${pkg}" &>/dev/null; then
    return 0
  elif pacman -Qi "flatpak" &>/dev/null && flatpak info "${pkg}" &>/dev/null; then
    return 0
  elif command -v "${pkg}" &>/dev/null; then
    return 0
  else
    return 1
  fi
}

get_aur_helper() {
  if pkg_installed yay; then
    aur_helper="yay"
  elif pkg_installed paru; then
    aur_helper="paru"
  fi
}

get_aur_helper
export -f pkg_installed

clean_cache() {
    echo
    print_warning "Clearing the cache frees disk space but requires redownloading if you need to downgrade later."
    echo -e "${YELLOW}󰩺 Would you like to clear your $aur_helper package cache? (n/Y)${NC}"
    read -r clean_choice
    case "$clean_choice" in
        [nN][oO]|[nN])
            print_status "Cache cleaning skipped."
            ;;
        *)
            if [ -n "$aur_helper" ]; then
                print_status "󰩺 Cleaning $aur_helper cache..."
                $aur_helper -Scc
                print_status "󰸞 $aur_helper cache cleared."
            fi
            ;;
    esac
}

prompt_reboot() {
    echo
    print_warning "A reboot is recommended to ensure all changes take effect properly."
    echo
    echo -e "${YELLOW}󰜉 Would you like to reboot now? (n/Y)${NC}"
    read -r reboot_choice
    case "$reboot_choice" in
        [nN][oO]|[nN])
            print_status "Reboot skipped. Please reboot manually when convenient."
            ;;
        *)
            print_status "󰜉 Rebooting system..."
            sudo reboot
            ;;
    esac
}

# Trigger upgrade (legacy — via waybar/kitty self-spawn)
if [ "$1" == "up" ]; then
  trap 'pkill -RTMIN+20 waybar' EXIT
  export -f prompt_reboot print_warning print_status clean_cache
  export YELLOW NC aur_helper
  command="
    $0 upgrade
    ${aur_helper} -Syu
    if command -v checkrebuild >/dev/null; then
        echo
        print_status \"Checking for packages requiring a rebuild...\"
        broken_pkgs=\$(checkrebuild | grep '^foreign' | awk '{print \$2}')
        if [ -n \"\$broken_pkgs\" ]; then
            print_warning \"Found broken packages: \$broken_pkgs\"
            print_status \"Rebuilding them now...\"
            ${aur_helper} -S --rebuild \$broken_pkgs
        else
            print_status \"No packages require rebuilding.\"
        fi
    fi
    hyprctl reload
    if pkg_installed flatpak; then flatpak update; fi
    clean_cache
    prompt_reboot
    "
  kitty --title "   System Update" sh -c "${command}"
fi

# Run upgrade inside terminal (launched directly by QML via kitty)
if [ "$1" == "run" ]; then
  # Keep window open on any error
  trap 'echo; print_warning "An error occurred (exit code: $?)"; echo "Press Enter to close..."; read' ERR

  if [ -z "$aur_helper" ]; then
      print_warning "No AUR helper (yay/paru) found in PATH."
      echo "PATH: $PATH"
      echo "Press Enter to close..."
      read
      exit 1
  fi

  # Print update summary header
  aur_updates_now=$(${aur_helper} -Qua 2>/dev/null | grep -c '^' || echo )
  official_updates_now=$( (while pgrep -x checkupdates >/dev/null; do sleep 1; done); checkupdates 2>/dev/null | grep -c '^' || echo )
  flatpak_updates_now=$(pkg_installed flatpak && flatpak remote-ls --updates 2>/dev/null | grep -c '^' || echo )
  printf "Official:  %-10s\nAUR (%s): %-10s\nFlatpak:   %-10s\n\n" \
    "$official_updates_now" "$aur_helper" "$aur_updates_now" "$flatpak_updates_now"

  ${aur_helper} -Syu

  if command -v checkrebuild >/dev/null; then
      echo
      print_status "Checking for packages requiring a rebuild..."
      broken_pkgs=$(checkrebuild | grep '^foreign' | awk '{print $2}')
      if [ -n "$broken_pkgs" ]; then
          print_warning "Found broken packages: $broken_pkgs"
          print_status "Rebuilding them now..."
          ${aur_helper} -S --rebuild $broken_pkgs
      else
          print_status "No packages require rebuilding."
      fi
  fi

  hyprctl reload
  if pkg_installed flatpak; then flatpak update; fi

  clean_cache
  prompt_reboot
  exit 0
fi

# Check for AUR updates
if [ -n "$aur_helper" ]; then
  aur_updates=$(${aur_helper} -Qua | grep -c '^')
else
  aur_updates=0
fi

# Check for official repository updates
official_updates=$(
  (while pgrep -x checkupdates >/dev/null; do sleep 1; done)
  checkupdates | grep -c '^'
)

# Check for Flatpak updates
if pkg_installed flatpak; then
  flatpak_updates=$(flatpak remote-ls --updates | grep -c '^')
else
  flatpak_updates=0
fi

total_updates=$((official_updates + aur_updates + flatpak_updates))

if [ "$aur_helper" == "yay" ]; then
  [ "${1}" == upgrade ] && printf "Official:  %-10s\nAUR ($aur_helper): %-10s\nFlatpak:   %-10s\n\n" "$official_updates" "$aur_updates" "$flatpak_updates" && exit
  tooltip="Official:  $official_updates\nAUR ($aur_helper): $aur_updates\nFlatpak:   $flatpak_updates"
elif [ "$aur_helper" == "paru" ]; then
  [ "${1}" == upgrade ] && printf "Official:   %-10s\nAUR ($aur_helper): %-10s\nFlatpak:    %-10s\n\n" "$official_updates" "$aur_updates" "$flatpak_updates" && exit
  tooltip="Official:   $official_updates\nAUR ($aur_helper): $aur_updates\nFlatpak:    $flatpak_updates"
fi

if [ $total_updates -eq 0 ]; then
  echo "{\"text\":\"󰸟\", \"tooltip\":\"Packages are up to date\"}"
else
  echo "{\"text\":\"\", \"tooltip\":\"${tooltip//\"/\\\"}\"}"
fi
