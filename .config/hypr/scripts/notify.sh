#!/bin/bash

notify-send " HC+ Update Complete" "LATEST:   
 Switched from wallust aur package to cargo
  package with new cargo packages handling.
 Added tooltips to bar modules where relevant.
 New agent-app keybinds to toggle left & right
  panels + open files, app-wide tooltips, file
  and directory watching and other patches.
 Shell type can now be changed by clicking the
  interactive 'Shell' chip in the control-center
  'System' tab which launches a shell-switcher
  terminal instance with options for zsh, fish
  and bash. 
 Updated launcher agent-app with improved text
  contrast, increased file-type linting and file
  git statuc tracking.
 Fixed media-playback resume from desktop sleep
  state on the web-search tab browser.
 Updatd the HC+ workspace themeing and agentic
  logic: agents can create memories when prompted
  to remember something and that chat flow is
  improved to handle reversion of changes, user
  qued prompts to steer the agent and new agent
  instructions and tools for the agent's loop.
 Added preview mode scrolling to the wallpaper
  popup right-click preview UI and enhanced the
  the display of Wallhaven search results with
  pagination & auto-load of results on scroll.
 Added a new 'Display' settings tab to the
  control center and move the 'Dock' tab logic
  under the Bar sub-stack.
 Fixed 'suspension' and 'hibernation' from the
  startmenu and lock-screen.
  - When triggered from the start-menu popup, the
  process now correctly transitions to the lock-
  screen prior to sleep or hibernation.
 Fixed media playback disconnecting on launcher
  web-search tab when launcher is hidden. 
 Wallpaper popup image-preview on right-click of
  thumbnails as well as image deletion logic has
  been added.
 Migrating screen recorder from wf-recorder to
  gpu-screen-recorder with added 'stream' option
  in the recorder popup.
 Fixed masking of new cava styles in the bar cava
  modules.
 Migrated the dock and launcher from GJS to
  Quickshell for reduced cpu usage and faster
  animations plus unified theming.
 Updated the launcher's web-search tabto a full
  browser experience with the same focus on secirty
  and privacy.
 Added 6 sound profiles to the media-player popup.
 Minor shell and feature fixes:
  - Contflicting auto-hide in tri & shell modes.
    - Restored center-island auto-hide.
  - Cava color in popup not being vsisible.

RECENT:
 Auto-start/stop SearXNG-docker.
 Improved integration of cloud-model-providers.
 Added Wallhaven integration to the wallpaper-picker
  and extra awww-walpaper engine options on the bottom
  row.
 App-launcer bookmarks now autostart the backend 
  SearXNG docker container.
 Significantly reduced web view CPU usage including on
  video-playback.
 Bookmarks support added to launcher's web search tab."
