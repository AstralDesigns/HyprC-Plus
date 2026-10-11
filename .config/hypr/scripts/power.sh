#!/bin/bash
#    ___                    
#   / _ \___ _    _____ ____
#  / ___/ _ \ |/|/ / -_) __/
# /_/   \___/__,__/\__/_/   
#                           

USERNAME=$(whoami)

if [[ "$1" == "exit" ]]; then
  echo ":: Exit"
  hyprshutdown -t 'Logging out...' --post-cmd "hyprctl dispatch hl.dsp.exit()" > /dev/null 2>&1
fi

if [[ "$1" == "lock" ]]; then
  echo ":: Lock"
  "$HOME/.config/hyprcandy/scripts/candylock.sh"
fi

if [[ "$1" == "reboot" ]]; then
  echo ":: Reboot"
  hyprshutdown -t 'Restarting...' --post-cmd 'reboot' > /dev/null 2>&1
fi

if [[ "$1" == "shutdown" ]]; then
  echo ":: Shutdown"
  hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown -P 0' > /dev/null 2>&1
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
