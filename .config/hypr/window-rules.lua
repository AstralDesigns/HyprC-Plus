-- Window rules
hl.window_rule({
    name = "windowrule-1",
    match = {
        class = ".*",
    },
    group = "barred",
})
hl.window_rule({
    name = "windowrule-2",
    match = {
        class = "(kitty-scratchpad)",
    },
    float = true,
    center = true,
    border_color = primary_container,
    size = "800 500",
})
hl.window_rule({
    name = "windowrule-3",
    match = {
        class = "^$",
        title = "^$",
        xwayland = "True",
        float = "True",
        fullscreen = "False",
        pinned = "False",
    },
    suppress_event = "maximize",
})
hl.window_rule({
    name = "windowrule-4",
    match = {
        class = "(org.gnome.Weather)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-5",
    match = {
        class = "(org.gnome.Calendar)",
    },
    float = true,
    size = "820 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-6",
    match = {
        class = "(org.gnome.SystemMonitor)",
    },
    float = true,
    size = "820 625",
    center = true,
})
hl.window_rule({
    name = "windowrule-7",
    match = {
        title = "(Open Files)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-8",
    match = {
        title = "(Select Copy Destination)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-9",
    match = {
        title = "(Select Move Destination)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-10",
    match = {
        title = "(Save As)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-11",
    match = {
        title = "(Select files to send)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-12",
    match = {
        title = "(Bluetooth File Transfer)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-13",
    match = {
        class = "(nwg-look)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-14",
    match = {
        title = "(CachyOS Hello)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-15",
    match = {
        class = "(nwg-displays)",
    },
    float = true,
    size = "990 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-16",
    match = {
        class = "(io.missioncenter.MissionCenter)",
    },
    float = true,
    size = "900 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-17",
    match = {
        class = "(missioncenter)",
        title = "^(Preferences)$",
    },
    float = true,
    center = true,
})
hl.window_rule({
    name = "windowrule-18",
    match = {
        class = "(org.gnome.Calculator)",
    },
    float = true,
    size = "700 600",
    center = true,
})
hl.window_rule({
    name = "windowrule-19",
    match = {
        class = "(it.mijorus.smile)",
    },
    float = true,
    move = "100%-w-40 90",
})
hl.window_rule({
    name = "windowrule-20",
    match = {
        class = "(hyprland-share-picker)",
    },
    float = true,
    size = "600 400",
    center = true,
})
hl.window_rule({
    name = "windowrule-21",
    match = {
        title = "(hyprviz)",
    },
    float = true,
    size = "1000 625",
    center = true,
})
hl.window_rule({
    name = "windowrule-22",
    match = {
        class = "(dotfiles-floating)",
    },
    float = true,
    size = "1000 700",
    center = true,
})
hl.window_rule({
    name = "windowrule-23",
    match = {
        title = "(satty)",
    },
    float = true,
    size = "1000 565",
    center = true,
})
hl.window_rule({
    name = "windowrule-24",
    match = {
        class = "^(org.pulseaudio.pavucontrol)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-25",
    match = {
        class = "^()$",
        title = "^(Picture in picture)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-26",
    match = {
        class = "^()$",
        title = "^(Save File)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-27",
    match = {
        class = "^()$",
        title = "^(Open File)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-28",
    match = {
        class = "^(LibreWolf)$",
        title = "^(Picture-in-Picture)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-30",
    match = {
        class = "^(xdg-desktop-portal-hyprland|xdg-desktop-portal-gtk|xdg-desktop-portal-kde)(.*)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-31",
    match = {
        class = "^(hyprpolkitagent|polkit-gnome-authentication-agent-1|org.org.kde.polkit-kde-authentication-agent-1)(.*)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-32",
    match = {
        class = "^(zenity)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-33",
    match = {
        class = "^()$",
        title = "^(Steam - Self Updater)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-34",
    match = {
        title = "^(Picture-in-Picture)$",
    },
    float = true,
    pin = true,
    size = "360 200",
    move = "((monitor_w*0.5)-(window_w*0.5)) 50",
})
hl.window_rule({
    name = "windowrule-36",
    match = {
        title = "^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$",
    },
    float = true,
    move = "25%-",
    size = "960 540",
})
hl.window_rule({
    name = "windowrule-37",
    match = {
        title = "^(danmufloat|termfloat)$",
    },
    rounding = 10,
})
hl.window_rule({
    name = "windowrule-38",
    match = {
        title = "^(nm-connection-editor)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-39",
    match = {
        title = "^(qalculate-gtk)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-40",
    match = {
        class = "([window])",
    },
    idle_inhibit = "fullscreen",
    -- TODO verify direct Lua equivalent for legacy effect: always
    -- TODO verify direct Lua equivalent for legacy effect: focus
    -- TODO verify direct Lua equivalent for legacy effect: fullscreen
})
hl.window_rule({
    name = "windowrule-41",
    match = {
        class = "^(org.kde.dolphin)$",
        title = "^(Progress Dialog — Dolphin)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-42",
    match = {
        class = "^(org.kde.dolphin)$",
        title = "^(Copying — Dolphin)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-43",
    match = {
        title = "^(About Mozilla Firefox)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-44",
    match = {
        class = "^(firefox)$",
        title = "^(Picture-in-Picture)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-45",
    match = {
        class = "^(firefox)$",
        title = "^(Library)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-46",
    match = {
        class = "^(kvantummanager)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-47",
    match = {
        class = "^(qt5ct)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-48",
    match = {
        class = "^(qt6ct)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-49",
    match = {
        class = "^(org.kde.ark)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-50",
    match = {
        class = "^(org.pulseaudio.pavucontrol)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-51",
    match = {
        class = "^(org.kde.polkit-kde-authentication-agent-1)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-52",
    match = {
        class = "^(Signal)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-53",
    match = {
        class = "^(com.github.rafostar.Clapper)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-54",
    match = {
        class = "^(app.drey.Warp)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-55",
    match = {
        class = "^(net.davidotek.pupgui2)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-56",
    match = {
        class = "^(yad)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-57",
    match = {
        class = "^(eog)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-58",
    match = {
        class = "^(io.github.alainm23.planify)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-59",
    match = {
        class = "^(io.gitlab.theevilskeleton.Upscaler)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-60",
    match = {
        class = "^(com.github.unrud.VideoDownloader)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-61",
    match = {
        class = "^(io.gitlab.adhami3310.Impression)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-62",
    match = {
        class = "^(io.missioncenter.MissionCenter)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-63",
    match = {
        class = "(clipse)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-64",
    match = {
        class = "(clipse)",
    },
    size = "622 652",
})
hl.window_rule({
    name = "windowrule-65",
    match = {
        title = "^(Choose Files)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-66",
    match = {
        title = "^(Save As)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-67",
    match = {
        title = "^(Confirm to replace files)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-68",
    match = {
        title = "^(File Operation Progress)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-69",
    match = {
        class = "^(xdg-desktop-portal-gtk)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-70",
    match = {
        class = "(floating-installer)",
    },
    float = true,
    center = true,
})
hl.window_rule({
    name = "windowrule-72",
    match = {
        class = "(clock)",
    },
    float = true,
    center = true,
    size = "400 200",
})