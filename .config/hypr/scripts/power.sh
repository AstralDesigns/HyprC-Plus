#!/bin/bash
#    ___                    
#   / _ \___ _    _____ ____
#  / ___/ _ \ |/|/ / -_) __/
# /_/   \___/__,__/\__/_/   
#                           

USERNAME=$(whoami)

if [[ "$1" == "exit" ]]; then
  echo ":: Exit"
  # Direct logout: hyprshutdown closes apps (qs bar / awww included) as part
  # of its sequence, so cancelling its dialog can leave a half-dead session
  # (and it forks, so the cancel is not detectable via exit status). Exiting
  # Hyprland outright returns to SDDM (autologin on live), which rebuilds the
  # whole session via the normal autostarts - no stuck state possible.
  hyprctl dispatch 'hl.dsp.exit()'
fi

if [[ "$1" == "lock" ]]; then
  echo ":: Lock"
  "$HOME/.config/hyprcandy/scripts/candylock.sh"
fi

if [[ "$1" == "reboot" ]]; then
  echo ":: Reboot"
  # Direct logind action (same rationale as Exit): hyprshutdown pre-closes
  # apps and forks, so a cancelled dialog could leave a half-dead session.
  # logind tears all sessions down cleanly and proceeds unconditionally.
  systemctl reboot
fi

if [[ "$1" == "shutdown" ]]; then
  echo ":: Shutdown"
  systemctl poweroff
fi

if [[ "$1" == "suspend" ]]; then
  echo ":: Suspend"
  # Marker carries the action so candylock sleeps with the RIGHT method AFTER
  # the session is locked (see suspendIfFlagged in candylock/shell.qml).
  echo suspend > /tmp/.qs-candylock-sleep
  "$HOME/.config/hyprcandy/scripts/candylock.sh"
  rm -f /tmp/.qs-candylock-sleep
fi

if [[ "$1" == "hibernate" ]]; then
  echo ":: Hibernate"
  # Mirror suspend: lock first, then suspend-to-disk once secured, so the
  # session is never exposed on resume. Only reachable when the Hibernate
  # button is shown, i.e. logind CanHibernate=yes (swap+resume configured).
  echo hibernate > /tmp/.qs-candylock-sleep
  "$HOME/.config/hyprcandy/scripts/candylock.sh"
  rm -f /tmp/.qs-candylock-sleep
fi
