--  ██████╗ █████╗ ███╗   ██╗██████╗ ██╗   ██╗
-- ██╔════╝██╔══██╗████╗  ██║██╔══██╗╚██╗ ██╔╝
-- ██║     ███████║██╔██╗ ██║██║  ██║ ╚████╔╝ 
-- ██║     ██╔══██║██║╚██╗██║██║  ██║  ╚██╔╝  
-- ╚██████╗██║  ██║██║ ╚████║██████╔╝   ██║   
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝    ╚═╝   

hl.bind("SUPER + S", hl.dsp.exec_cmd("spotify-launcher"), { description = "Launch Spotify" })
hl.bind("SUPER + D", hl.dsp.exec_cmd("equibop"), { description = "Launch the Discord app" })
hl.bind("SUPER + C", hl.dsp.exec_cmd("gedit"), { description = "Launch the editor" })
hl.bind("SUPER + Q", hl.dsp.exec_cmd("kitty"), { description = "Launch normal kitty instances" })
hl.bind("SUPER + Return", hl.dsp.exec_cmd("pypr toggle term"), { description = "Launch a kitty scratchpad through pyprland" })
hl.bind("SUPER + E", hl.dsp.exec_cmd("nautilus"), { description = "Launch the filemanager" })
hl.bind("SUPER + CTRL + C", hl.dsp.exec_cmd("gnome-calculator"), { description = "Launch the calculator" })
hl.bind("SUPER + Escape", hl.dsp.window.close(), { description = "Kill active window" })
hl.bind("ALT + 1", hl.dsp.exec_cmd("~/.config/hyprcandy/scripts/bar.sh"), { description = "Toggle bar visibility" })
hl.bind("ALT + 2", hl.dsp.exec_cmd("qs ipc -c bar call bar toggleDock"), { description = "Toggle dock visibility" })
hl.bind("ALT + 3", hl.dsp.exec_cmd("qs ipc -c bar call bar toggleControlCenter"), { description = "Toggle control center" })
hl.bind("ALT + 4", hl.dsp.exec_cmd("qs ipc -c bar call bar toggleStartMenu"), { description = "Toggle start menu" })
hl.bind("ALT + 5", hl.dsp.exec_cmd("qs ipc -c bar call bar toggleNotifications"), { description = "Toggle notification history" })
hl.bind("ALT + 6", hl.dsp.exec_cmd("qs ipc -c bar call bar toggleDesktopIcons"), { description = "Toggle desktop icons visibility" })
hl.bind("SUPER + A", hl.dsp.exec_cmd("qs ipc -c bar call bar openLauncher"), { description = "Toggle launcher visibility" })
hl.bind("ALT + CTRL + 2", hl.dsp.exec_cmd("qs ipc -c bar call bar launcherTab clipboard"), { description = "Toggle clipboard picker (HC launcher)" })
hl.bind("ALT + CTRL + 3", hl.dsp.exec_cmd("qs ipc -c bar call bar launcherIcons emoji"), { description = "Toggle emoji picker (HC launcher)" })
hl.bind("ALT + CTRL + 4", hl.dsp.exec_cmd("qs ipc -c bar call bar launcherIcons nerd"), { description = "Toggle glyph picker (HC launcher)" })
hl.bind("ALT + CTRL + 5", hl.dsp.exec_cmd("qs ipc -c bar call bar launcherTab websearch"), { description = "Toggle web-search browser tab (HC launcher)" })
hl.bind("ALT + CTRL + 6", hl.dsp.exec_cmd("qs ipc -c bar call bar launcherTab agent"), { description = "Toggle agentic workspace tab (HC launcher)" })
hl.bind("SUPER + W", hl.dsp.exec_cmd("~/.config/hyprcandy/scripts/wallpaper.sh"), { description = "Wallpaper picker" })
hl.bind("ALT + W", hl.dsp.exec_cmd("~/.config/quickshell/wallpaper/wallpaper-cycle.sh -n"), { description = "Alternate wallpapers forward" })
hl.bind("ALT + SHIFT + W", hl.dsp.exec_cmd("~/.config/quickshell/wallpaper/wallpaper-cycle.sh -p"), { description = "Alternate wallpapers backward" })
hl.bind("ALT + SHIFT + R", hl.dsp.exec_cmd("~/.config/hyprcandy/hooks/wallpaper_integration.sh"), { description = "Reload system colors" })
hl.bind("SUPER + B", hl.dsp.exec_cmd("xdg-open \"http://\""), { description = "Launch your default browser" })
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("~/.config/hypr/scripts/loadconfig.sh"), { description = "Reload Hyprland configuration" })
hl.bind("SUPER + PRINT", hl.dsp.exec_cmd("qs -p ~/.config/quickshell/bar ipc call bar toggleCaptureMenu"), { description = "Capture screen (Screenshot or Recorder)" })
hl.bind("SUPER + V", hl.dsp.exec_cmd("cliphist wipe"), { description = "Clear cliphist database" })
hl.bind("SUPER + CTRL + D", hl.dsp.exec_cmd("$ cliphist list | dmenu | cliphist delete"), { description = "Delete an old item" })
hl.bind("SUPER + ALT + D", hl.dsp.exec_cmd("$ cliphist delete-query \"secret item\""), { description = "Delete an old item quering manually" })
hl.bind("SUPER + ALT + S", hl.dsp.exec_cmd("$ cliphist list | dmenu | cliphist decode | wl-copy"), { description = "Select an old item" })
hl.bind("SUPER + L", hl.dsp.exec_cmd("~/.config/hypr/scripts/power.sh lock"), { description = "Lock" })
hl.bind("SHIFT + TAB", hl.dsp.exec_cmd("~/.config/hyprcandy/scripts/overview.sh"), { description = "Workspace overview" })

return true