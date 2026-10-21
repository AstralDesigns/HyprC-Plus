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
        class = "(com.candy.widgets|gjs|widgets)",
    },
    pin = true,
    border_size = 3,
})
hl.window_rule({
    name = "windowrule-3",
    match = {
        title = "(candy.utils)",
    },
    move = "((monitor_w*0.5)-(window_w*0.5)) 45",
})
hl.window_rule({
    name = "windowrule-4",
    match = {
        title = "(candy.systemmonitor)",
    },
    move = "((monitor_w*1)-((window_w*1)+10)) 45",
})
hl.window_rule({
    name = "windowrule-5",
    match = {
        title = "(candy.weather)",
    },
    move = "((monitor_w*0.5)-(window_w*0.5)) 45",
})
hl.window_rule({
    name = "windowrule-6",
    match = {
        title = "(candy.media)",
    },
    move = "((monitor_w*0.5)-(window_w*0.5))",
})
hl.window_rule({
    name = "windowrule-7",
    match = {
        class = "^(kitty|kitty-scratchpad|Alacritty|floating-installer|clock)$",
    },
    opacity = "1.0 1.0",
})
hl.window_rule({
    name = "windowrule-8",
    match = {
        class = "(kitty-scratchpad)",
    },
    float = true,
    center = true,
    size = "800 500",
})
hl.window_rule({
    name = "windowrule-9",
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
    name = "windowrule-10",
    match = {
        class = "(.*org.pulseaudio.pavucontrol.*)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-11",
    match = {
        class = "(.*org.pulseaudio.pavucontrol.*)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-12",
    match = {
        class = "(.*org.pulseaudio.pavucontrol.*)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-13",
    match = {
        class = "(.*waypaper.*)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-14",
    match = {
        class = "(.*waypaper.*)",
    },
    size = "800 600",
})
hl.window_rule({
    name = "windowrule-15",
    match = {
        class = "(.*waypaper.*)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-16",
    match = {
        class = "(blueman-manager)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-17",
    match = {
        class = "(blueman-manager)",
    },
    size = "800 600",
})
hl.window_rule({
    name = "windowrule-18",
    match = {
        class = "(blueman-manager)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-19",
    match = {
        class = "(org.gnome.Weather)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-20",
    match = {
        class = "(org.gnome.Weather)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-21",
    match = {
        class = "(org.gnome.Weather)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-22",
    match = {
        class = "(org.gnome.Calendar)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-23",
    match = {
        class = "(org.gnome.Calendar)",
    },
    size = "820 600",
})
hl.window_rule({
    name = "windowrule-24",
    match = {
        class = "(org.gnome.Calendar)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-25",
    match = {
        class = "(org.gnome.SystemMonitor)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-26",
    match = {
        class = "(org.gnome.SystemMonitor)",
    },
    size = "820 625",
})
hl.window_rule({
    name = "windowrule-27",
    match = {
        class = "(org.gnome.SystemMonitor)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-28",
    match = {
        title = "(Open Files)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-29",
    match = {
        title = "(Open Files)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-30",
    match = {
        title = "(Open Files)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-31",
    match = {
        title = "(Select Copy Destination)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-32",
    match = {
        title = "(Select Copy Destination)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-33",
    match = {
        title = "(Select Copy Destination)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-34",
    match = {
        title = "(Select Move Destination)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-35",
    match = {
        title = "(Select Move Destination)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-36",
    match = {
        title = "(Select Move Destination)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-37",
    match = {
        title = "(Save As)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-38",
    match = {
        title = "(Save As)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-39",
    match = {
        title = "(Save As)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-40",
    match = {
        title = "(Select files to send)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-41",
    match = {
        title = "(Select files to send)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-42",
    match = {
        title = "(Select files to send)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-43",
    match = {
        title = "(Bluetooth File Transfer)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-44",
    match = {
        class = "(nwg-look)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-45",
    match = {
        class = "(nwg-look)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-46",
    match = {
        class = "(nwg-look)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-47",
    match = {
        title = "(CachyOS Hello)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-48",
    match = {
        title = "(CachyOS Hello)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-49",
    match = {
        title = "(CachyOS Hello)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-50",
    match = {
        class = "(nwg-displays)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-51",
    match = {
        class = "(nwg-displays)",
    },
    size = "990 600",
})
hl.window_rule({
    name = "windowrule-52",
    match = {
        class = "(nwg-displays)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-53",
    match = {
        class = "(io.missioncenter.MissionCenter)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-54",
    match = {
        class = "(io.missioncenter.MissionCenter)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-55",
    match = {
        class = "(io.missioncenter.MissionCenter)",
    },
    size = "900 600",
})
hl.window_rule({
    name = "windowrule-56",
    match = {
        class = "(missioncenter)",
        title = "^(Preferences)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-57",
    match = {
        class = "(missioncenter)",
        title = "^(Preferences)$",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-58",
    match = {
        class = "(org.gnome.Calculator)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-59",
    match = {
        class = "(org.gnome.Calculator)",
    },
    size = "700 600",
})
hl.window_rule({
    name = "windowrule-60",
    match = {
        class = "(org.gnome.Calculator)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-61",
    match = {
        class = "(it.mijorus.smile)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-62",
    match = {
        class = "(it.mijorus.smile)",
    },
    move = "100%-w-40 90",
})
hl.window_rule({
    name = "windowrule-63",
    match = {
        class = "(hyprland-share-picker)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-64",
    match = {
        title = "match:class (hyprland-share-picker)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-65",
    match = {
        class = "(hyprland-share-picker)",
    },
    size = "600 400",
})
hl.window_rule({
    name = "windowrule-66",
    match = {
        title = "(hyprviz)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-67",
    match = {
        title = "(hyprviz)",
    },
    size = "1000 625",
})
hl.window_rule({
    name = "windowrule-68",
    match = {
        title = "(hyprviz)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-69",
    match = {
        class = "(dotfiles-floating)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-70",
    match = {
        class = "(dotfiles-floating)",
    },
    size = "1000 700",
})
hl.window_rule({
    name = "windowrule-71",
    match = {
        class = "(dotfiles-floating)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-72",
    match = {
        title = "(satty)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-73",
    match = {
        title = "(satty)",
    },
    size = "1000 565",
})
hl.window_rule({
    name = "windowrule-74",
    match = {
        title = "(satty)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-75",
    match = {
        class = "^(org.pulseaudio.pavucontrol)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-76",
    match = {
        class = "^()$",
        title = "^(Picture in picture)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-77",
    match = {
        class = "^()$",
        title = "^(Save File)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-78",
    match = {
        class = "^()$",
        title = "^(Open File)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-79",
    match = {
        class = "^(LibreWolf)$",
        title = "^(Picture-in-Picture)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-80",
    match = {
        class = "^(xdg-desktop-portal-hyprland|xdg-desktop-portal-gtk|xdg-desktop-portal-kde)(.*)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-81",
    match = {
        class = "^(hyprpolkitagent|polkit-gnome-authentication-agent-1|org.org.kde.polkit-kde-authentication-agent-1)(.*)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-82",
    match = {
        title = "^(CachyOSHello)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-83",
    match = {
        class = "^(zenity)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-84",
    match = {
        class = "^()$",
        title = "^(Steam - Self Updater)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-85",
    match = {
        class = "^(zen)$",
    },
    opacity = "1.0",
})
hl.window_rule({
    name = "windowrule-86",
    match = {
        title = "^(Picture-in-Picture)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-87",
    match = {
        title = "^(Picture-in-Picture)$",
    },
    pin = true,
})
hl.window_rule({
    name = "windowrule-88",
    match = {
        title = "^(Picture-in-Picture)$",
    },
    size = "360 200",
})
hl.window_rule({
    name = "windowrule-89",
    match = {
        title = "^(Picture-in-Picture)$",
    },
    move = "((monitor_w*0.5)-(window_w*0.5)) 50",
})
hl.window_rule({
    name = "windowrule-90",
    match = {
        title = "^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-91",
    match = {
        title = "^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$",
    },
    move = "25%-",
})
hl.window_rule({
    name = "windowrule-92",
    match = {
        title = "^(imv|mpv|danmufloat|termfloat|nemo|ncmpcpp)$",
    },
    size = "960 540",
})
hl.window_rule({
    name = "windowrule-93",
    match = {
        title = "^(danmufloat|termfloat)$",
    },
    rounding = 10,
})
hl.window_rule({
    name = "windowrule-94",
    match = {
        class = "^(kitty|Alacritty)$",
    },
    animation = "slide right",
})
hl.window_rule({
    name = "vwindowrule-95",
    match = {
        title = "^(Brave-browser)$",
    },
    float = false,
})
hl.window_rule({
    name = "windowrule-96",
    match = {
        title = "^(pavucontrol)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-97",
    match = {
        title = "^(blueman-manager)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-98",
    match = {
        title = "^(nm-connection-editor)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-99",
    match = {
        title = "^(qalculate-gtk)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-100",
    match = {
        class = "([window])",
    },
    idle_inhibit = "fullscreen",
    -- TODO verify direct Lua equivalent for legacy effect: always
    -- TODO verify direct Lua equivalent for legacy effect: focus
    -- TODO verify direct Lua equivalent for legacy effect: fullscreen
})
hl.window_rule({
    name = "windowrule-101",
    match = {
        class = "^(nautilus)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-102",
    match = {
        class = "^(zen)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-103",
    match = {
        class = "^(code-oss)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-104",
    match = {
        class = "^([Cc]ode)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-105",
    match = {
        class = "^(nwg-look)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-106",
    match = {
        class = "^(qt5ct)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-107",
    match = {
        class = "^(qt6ct)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-108",
    match = {
        class = "^(kvantummanager)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-109",
    match = {
        class = "^([Ss]potify)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-110",
    match = {
        title = "^(Spotify Free)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-111",
    match = {
        title = "^(Spotify Premium)$",
    },
    opacity = "1.0 $& 1.0 $& 1",
})
hl.window_rule({
    name = "windowrule-112",
    match = {
        class = "^(org.kde.dolphin)$",
        title = "^(Progress Dialog — Dolphin)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-113",
    match = {
        class = "^(org.kde.dolphin)$",
        title = "^(Copying — Dolphin)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-114",
    match = {
        title = "^(About Mozilla Firefox)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-115",
    match = {
        class = "^(firefox)$",
        title = "^(Picture-in-Picture)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-116",
    match = {
        class = "^(firefox)$",
        title = "^(Library)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-117",
    match = {
        class = "^(kitty)$",
        title = "^(top)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-118",
    match = {
        class = "^(kitty)$",
        title = "^(btop)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-119",
    match = {
        class = "^(kitty)$",
        title = "^(htop)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-120",
    match = {
        class = "^(eww-main-window)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-121",
    match = {
        class = "^(eww-notifications)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-122",
    match = {
        class = "^(kvantummanager)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-123",
    match = {
        class = "^(qt5ct)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-124",
    match = {
        class = "^(qt6ct)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-125",
    match = {
        class = "^(nwg-look)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-126",
    match = {
        class = "^(org.kde.ark)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-127",
    match = {
        class = "^(org.pulseaudio.pavucontrol)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-128",
    match = {
        class = "^(blueman-manager)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-129",
    match = {
        class = "^(nm-applet)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-130",
    match = {
        class = "^(nm-connection-editor)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-131",
    match = {
        class = "^(org.kde.polkit-kde-authentication-agent-1)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-132",
    match = {
        class = "^(Signal)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-133",
    match = {
        class = "^(com.github.rafostar.Clapper)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-134",
    match = {
        class = "^(app.drey.Warp)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-135",
    match = {
        class = "^(net.davidotek.pupgui2)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-136",
    match = {
        class = "^(yad)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-137",
    match = {
        class = "^(eog)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-138",
    match = {
        class = "^(io.github.alainm23.planify)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-139",
    match = {
        class = "^(io.gitlab.theevilskeleton.Upscaler)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-140",
    match = {
        class = "^(com.github.unrud.VideoDownloader)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-141",
    match = {
        class = "^(io.gitlab.adhami3310.Impression)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-142",
    match = {
        class = "^(io.missioncenter.MissionCenter)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-143",
    match = {
        class = "(clipse)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-144",
    match = {
        class = "(clipse)",
    },
    size = "622 652",
})
hl.window_rule({
    name = "windowrule-145",
    match = {
        title = "^(Choose Files)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-146",
    match = {
        title = "^(Save As)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-147",
    match = {
        title = "^(Confirm to replace files)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-148",
    match = {
        title = "^(File Operation Progress)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-149",
    match = {
        class = "^(xdg-desktop-portal-gtk)$",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-150",
    match = {
        class = "(floating-installer)",
    },
    float = true,
})
hl.window_rule({
    name = "windowrule-151",
    match = {
        class = "(floating-installer)",
    },
    center = true,
})
hl.window_rule({
    name = "windowrule-152",
    match = {
        class = "(clock)",
    },
    float = true,
    center = true,
    size = "400 200",
})
hl.window_rule({
    name = "windowrule-153",
    rounding = 10,
    -- TODO verify direct Lua equivalent for legacy effect: fullscreen true
    border_size = 3,
})