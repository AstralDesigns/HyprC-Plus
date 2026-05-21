#!/bin/bash
#    ___                    
#   / _ \___ _    _____ ____
#  / ___/ _ \ |/|/ / -_) __/
# /_/   \___/__,__/\__/_/   
#                           

USERNAME=$(whoami)

if [[ "$1" == "exit" ]]; then
  echo ":: Exit"
  hyprshutdown > /dev/null 2>&1 -t 'Logging out...' --post-cmd "hyprctl dispatch hl.dsp.exit()"
fi

if [[ "$1" == "lock" ]]; then
  echo ":: Lock"
  qs -c candylock
fi

if [[ "$1" == "reboot" ]]; then
  echo ":: Reboot"
  hyprshutdown > /dev/null 2>&1 -t 'Restarting...' --post-cmd 'reboot'
fi

if [[ "$1" == "shutdown" ]]; then
  echo ":: Shutdown"
  hyprshutdown > /dev/null 2>&1 -t 'Shutting down...' --post-cmd 'shutdown -P 0'
fi

if [[ "$1" == "suspend" ]]; then
  echo ":: Suspend"
  touch /tmp/.qs-candylock-sleep
  qs -c candylock
  rm -f /tmp/.qs-candylock-sleep
fi

if [[ "$1" == "hibernate" ]]; then
  echo ":: Hibernate"
  sleep 1
  systemctl hibernate
fi
