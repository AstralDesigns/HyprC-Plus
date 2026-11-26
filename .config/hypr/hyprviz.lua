--  ██████╗ █████╗ ███╗   ██╗██████╗ ██╗   ██╗
-- ██╔════╝██╔══██╗████╗  ██║██╔══██╗╚██╗ ██╔╝
-- ██║     ███████║██╔██╗ ██║██║  ██║ ╚████╔╝ 
-- ██║     ██╔══██║██║╚██╗██║██║  ██║  ╚██╔╝  
-- ╚██████╗██║  ██║██║ ╚████║██████╔╝   ██║   
--  ╚═════╝╚═╝  ╚═╝╚═╝  ╚═══╝╚═════╝    ╚═╝

-- HyprCandyPlus visual configuration migrated from hyprviz.conf
-- Generated from the complete original file; comments below preserve original section context where useful.
-- Runtime-generated overrides should live in ~/.config/hypr/hyprviz-state.lua, loaded after this file.

local mainMod = "SUPER"
local HYPRSCRIPTS = os.getenv("HOME") .. "/.config/hypr/scripts"
local SCRIPTS = os.getenv("HOME") .. "/.config/hyprcandy/scripts"
local function home(path) return (os.getenv("HOME") or "") .. path end

-- Autostart
hl.on("hyprland.start", function()
    hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE")
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP=hyprland DBUS_SESSION_BUS_ADDRESS DISPLAY XAUTHORITY")
    hl.exec_cmd("bash ~/.config/hypr/scripts/xdg.sh")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface gtk-theme 'adw-gtk3-dark'")
    hl.exec_cmd("gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'")
    hl.exec_cmd("systemctl --user start hyprpolkitagent")
    hl.exec_cmd("systemctl --user start font-watcher")
    hl.exec_cmd("systemctl --user start cursor-theme-watcher")
    hl.exec_cmd("bash ~/.config/hypr/scripts/wallpaper-restore.sh")
    hl.exec_cmd("hypridle")
    hl.exec_cmd("/usr/bin/pypr")
    hl.exec_cmd("qs -c bar")
    hl.exec_cmd("wl-paste --watch cliphist store")
end)

-- Environment variables
--hl.env("PATH", "$PATH:/usr/local/bin:/usr/bin:/bin:/home/$USERNAME/.cargo/bin")
--hl.env("AQ_NO_MODIFIERS", "1")
--hl.env("AQ_DRM_DEVICES", "/dev/dri/card1")
--hl.env("AQ_MGPU_NO_DIRECT", "1")
--hl.env("WLR_DRM_NO_ATOMIC", "1")
hl.env("XCURSOR_THEME", "geared-brass-32x")
hl.env("XCURSOR_SIZE", "18")
hl.env("HYPRCURSOR_THEME", "geared-brass-32x")
hl.env("HYPRCURSOR_SIZE", "18")
hl.env("GTK_THEME", "adw-gtk3-dark")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "0")
hl.env("QT_AUTO_SCREEN_SCALE_FACTOR", "1")
hl.env("GDK_DEBUG", "portals")
hl.env("GDK_SCALE", "1")
hl.env("GDK_BACKEND", "wayland")
hl.env("GDK_WAYLAND_DISABLE", "ext_background_effect_manager_v1")
hl.env("CLUTTER_BACKEND", "wayland")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "wayland")
hl.env("WINIT_UNIX_BACKEND", "wayland")
hl.env("QT_SCALE_FACTOR_ROUNDING_POLICY", "PassThrough")
hl.env("QEMU_AUDIO_DRV", "pa")
hl.env("QS_NO_RELOAD_POPUP", "1")

-- Core Hyprland config blocks
hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_model = "",
        kb_options = "",
        numlock_by_default = true,
        mouse_refocus = false,
        follow_mouse = 1,
        touchpad = {
            natural_scroll = false,
            scroll_factor = 1.0,
        },
        sensitivity = 0,
    },
    general = {
        gaps_in = 4,
        gaps_out = 20,
        gaps_workspaces = 50,
        border_size = 3,
        col = {
            active_border = color5,
            inactive_border = background,
        },
        layout = "dwindle",
        resize_on_border = true,
        allow_tearing = false,
    },
    group = {
        col = {
            border_active = source_color,
            border_inactive = background,
            border_locked_active = primary_fixed_dim,
            border_locked_inactive = background,
        },
        groupbar = {
            font_size = 14,
            font_weight_active = "heavy",
            font_weight_inactive = "heavy",
            text_color = surface_tint,
            col = {
                active = primary_fixed_dim,
                inactive = background,
                locked_active = primary_fixed_dim,
                locked_inactive = background,
            },
            indicator_height = 4,
            indicator_gap = 6,
            height = 10,
            render_titles = true,
            scrolling = true,
        },
    },
    dwindle = {
        pseudotile = true,
        preserve_split = true,
    },
    master = {
        new_status = "slave",
        new_on_active = "after",
        smart_resizing = true,
        drop_at_cursor = true,
    },
    scrolling = {
        direction = "right",
        focus_fit_method = 0,
        column_width = 0.5,
    },
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.2,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true,
    },
    binds = {
        workspace_back_and_forth = true,
        allow_workspace_cycles = true,
        pass_mouse_when_bound = false,
    },
    decoration = {
        rounding = 10,
        rounding_power = 2,
        active_opacity = 0.90,
        inactive_opacity = 0.90,
        fullscreen_opacity = 1.0,
        blur = {
            enabled = true,
            size = 1,
            passes = 4,
            new_optimizations = true,
            ignore_opacity = true,
            xray = true,
            vibrancy = 0.24999999999999933,
            noise = 0,
            popups = true,
            popups_ignorealpha = 0.8,
            brightness = 1.0000000000000002,
            contrast = 0.9999999999999997,
            special = false,
            vibrancy_darkness = 0.5000000000000002,
        },
        shadow = {
            enabled = true,
            range = 12,
            render_power = 4,
            color = scrim,
        },
        dim_strength = 0.19999999999999973,
        dim_inactive = false,
    },
    --cursor = {
        --no_hardware_cursors = 0,
        --no_warps = 0,
    --},
    --renderer = {
        --explicit_sync = true,
        --explicit_sync_kms = true,
    --},
    misc = {
        --vfr = true,
        --enable_swallow = false,
        --swallow_regex = "",
        --disable_watchdog_warning = true,
        disable_hyprland_logo = true,
        disable_splash_rendering = false,
        initial_workspace_tracking = 1,
    },
    --xwaylabd = { 
        --force_zero_scaling = true,
    --},
    debug = {
        suppress_errors = true,
    },
})

-- Gestures
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
hl.gesture({ fingers = 4, direction = "swipe", action = "move" })
hl.gesture({ fingers = 2, direction = "pinch", action = "float" })

-- Keybindings
-- Legacy variables retained as Lua locals for scripts used by keybinds.
local function expand_vars(cmd)
    cmd = cmd:gsub("%$HYPRSCRIPTS", HYPRSCRIPTS):gsub("%$SCRIPTS", SCRIPTS):gsub("%$mainMod", mainMod)
    return cmd
end
hl.bind("Shift + H", hl.dsp.exec_cmd("hyprctl hyprsunset gamma +10"), { description = "Increase gamma by 10%" })
hl.bind("Alt + H", hl.dsp.exec_cmd("hyprctl hyprsunset gamma -10"), { description = "Reduce gamma by 10%" })
-- Toggle Gamemode Performance Profile directly in Lua
hl.bind("ALT + G", function()
    -- Check if animations are currently active
    if hl.get_config("animations.enabled") == true then
        -- Turn OFF eye candy for Max Performance
        hl.config({
            animations = { enabled = false },
            decoration = {
                blur = { enabled = false },
                shadow = { enabled = false }
            },
            --general = { gaps_in = 0, gaps_out = 0, border_size = 1 }
        })
        hl.exec_cmd("notify-send \"Game-mode\" \"Activated\" -t 2000")
    else
        -- Restore eye candy
        hl.config({
            animations = { enabled = true },
            decoration = {
                blur = { enabled = true },
                shadow = { enabled = true }
            },
            --general = { gaps_in = 0, gaps_out = 0, border_size = 1 }
        })
        hl.exec_cmd("notify-send \"Game-mode\" \"Deactivated\" -t 2000")
    end
end, { description = "Toggle game-mode" })
hl.bind("SUPER + 1", hl.dsp.focus({ workspace = "1" }), { description = "Open workspace 1" })
hl.bind("SUPER + 2", hl.dsp.focus({ workspace = "2" }), { description = "Open workspace 2" })
hl.bind("SUPER + 3", hl.dsp.focus({ workspace = "3" }), { description = "Open workspace 3" })
hl.bind("SUPER + 4", hl.dsp.focus({ workspace = "4" }), { description = "Open workspace 4" })
hl.bind("SUPER + 5", hl.dsp.focus({ workspace = "5" }), { description = "Open workspace 5" })
hl.bind("SUPER + 6", hl.dsp.focus({ workspace = "6" }), { description = "Open workspace 6" })
hl.bind("SUPER + 7", hl.dsp.focus({ workspace = "7" }), { description = "Open workspace 7" })
hl.bind("SUPER + 8", hl.dsp.focus({ workspace = "8" }), { description = "Open workspace 8" })
hl.bind("SUPER + 9", hl.dsp.focus({ workspace = "9" }), { description = "Open workspace 9" })
hl.bind("SUPER + 0", hl.dsp.focus({ workspace = "10" }), { description = "Open workspace 10" })
hl.bind("SUPER + SHIFT + 1", hl.dsp.window.move({ workspace = "1", follow = true }), { description = "Move active window to workspace 1" })
hl.bind("SUPER + SHIFT + 2", hl.dsp.window.move({ workspace = "2", follow = true }), { description = "Move active window to workspace 2" })
hl.bind("SUPER + SHIFT + 3", hl.dsp.window.move({ workspace = "3", follow = true }), { description = "Move active window to workspace 3" })
hl.bind("SUPER + SHIFT + 4", hl.dsp.window.move({ workspace = "4", follow = true }), { description = "Move active window to workspace 4" })
hl.bind("SUPER + SHIFT + 5", hl.dsp.window.move({ workspace = "5", follow = true }), { description = "Move active window to workspace 5" })
hl.bind("SUPER + SHIFT + 6", hl.dsp.window.move({ workspace = "6", follow = true }), { description = "Move active window to workspace 6" })
hl.bind("SUPER + SHIFT + 7", hl.dsp.window.move({ workspace = "7", follow = true }), { description = "Move active window to workspace 7" })
hl.bind("SUPER + SHIFT + 8", hl.dsp.window.move({ workspace = "8", follow = true }), { description = "Move active window to workspace 8" })
hl.bind("SUPER + SHIFT + 9", hl.dsp.window.move({ workspace = "9", follow = true }), { description = "Move active window to workspace 9" })
hl.bind("SUPER + SHIFT + 0", hl.dsp.window.move({ workspace = "10", follow = true }), { description = "Move active window to workspace 10" })
hl.bind("SUPER + Tab", hl.dsp.focus({ workspace = "m+1" }), { description = "Open next workspace" })
hl.bind("SUPER + SHIFT + Tab", hl.dsp.focus({ workspace = "m-1" }), { description = "Open previous workspace" })
hl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }), { description = "Open next workspace" })
hl.bind("SUPER + mouse_up", hl.dsp.focus({ workspace = "e-1" }), { description = "Open previous workspace" })
hl.bind("SUPER + CTRL + down", hl.dsp.focus({ workspace = "empty" }), { description = "Open the next empty workspace" })
hl.bind("CTRL + SHIFT + 1", hl.dsp.workspace.toggle_special("magic"), { description = "Toggle scratchpad/special workspace" })
hl.bind("CTRL + SHIFT + 2", hl.dsp.window.move({ workspace = "special:magic", follow = true }), { description = "Move window to special workspace 4 (Can be toggled with \"SUPER,1\")" })
hl.bind("SUPER + ALT + 1", hl.dsp.window.move({ workspace = "1", follow = false }), { description = "Move active window to workspace 1 silently" })
hl.bind("SUPER + ALT + 2", hl.dsp.window.move({ workspace = "2", follow = false }), { description = "Move active window to workspace 2 silently" })
hl.bind("SUPER + ALT + 3", hl.dsp.window.move({ workspace = "3", follow = false }), { description = "Move active window to workspace 3 silently" })
hl.bind("SUPER + ALT + 4", hl.dsp.window.move({ workspace = "4", follow = false }), { description = "Move active window to workspace 4 silently" })
hl.bind("SUPER + ALT + 5", hl.dsp.window.move({ workspace = "5", follow = false }), { description = "Move active window to workspace 5 silently" })
hl.bind("SUPER + ALT + 6", hl.dsp.window.move({ workspace = "6", follow = false }), { description = "Move active window to workspace 6 silently" })
hl.bind("SUPER + ALT + 7", hl.dsp.window.move({ workspace = "7", follow = false }), { description = "Move active window to workspace 7 silently" })
hl.bind("SUPER + ALT + 8", hl.dsp.window.move({ workspace = "8", follow = false }), { description = "Move active window to workspace 8 silently" })
hl.bind("SUPER + ALT + 9", hl.dsp.window.move({ workspace = "9", follow = false }), { description = "Move active window to workspace 9 silently" })
hl.bind("SUPER + ALT + 0", hl.dsp.window.move({ workspace = "10", follow = false }), { description = "Move active window to workspace 10 silently" })
hl.bind("SUPER + Z", hl.dsp.window.drag(), { mouse = true, description = "Hold to move selected window" })
hl.bind("SUPER + X", hl.dsp.window.resize(), { mouse = true, description = "Hold to resize selected window" })
hl.bind("SUPER + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }), { description = "Set active window to fullscreen" })
hl.bind("SUPER + CTRL + F", hl.dsp.window.float({ action = "toggle" }), { description = "Toggle active windows into floating mode" })
hl.bind("SUPER + CTRL + T", hl.dsp.exec_cmd("~/.config/hypr/scripts/toggleallfloat.sh"), { description = "Toggle all windows into floating mode" })
hl.bind("SUPER + J", hl.dsp.exec_cmd("hyprctl dispatch togglesplit"), { description = "Toggle split" })
hl.bind("SUPER + left", hl.dsp.focus({ direction = "l" }), { description = "Move focus left" })
hl.bind("SUPER + right", hl.dsp.focus({ direction = "r" }), { description = "Move focus right" })
hl.bind("SUPER + up", hl.dsp.focus({ direction = "u" }), { description = "Move focus up" })
hl.bind("SUPER + down", hl.dsp.focus({ direction = "d" }), { description = "Move focus down" })
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Move window with the mouse" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize window with the mouse" })
hl.bind("SUPER + SHIFT + right", hl.dsp.window.resize({ x = 100, y = 0, relative = true }), { description = "Increase window width with keyboard" })
hl.bind("SUPER + SHIFT + left", hl.dsp.window.resize({ x = -100, y = 0, relative = true }), { description = "Reduce window width with keyboard" })
hl.bind("SUPER + SHIFT + down", hl.dsp.window.resize({ x = 0, y = 100, relative = true }), { description = "Increase window height with keyboard" })
hl.bind("SUPER + SHIFT + up", hl.dsp.window.resize({ x = 0, y = -100, relative = true }), { description = "Reduce window height with keyboard" })
hl.bind("SUPER + G", hl.dsp.group.toggle(), { description = "Toggle window group" })
hl.bind("SUPER + CTRL + left", hl.dsp.group.prev(), { description = "Switch to the previous window in the group" })
hl.bind("SUPER + CTRL + right", hl.dsp.group.next(), { description = "Switch to the next window in the group" })
hl.bind("SUPER + ALT + left", hl.dsp.window.swap({ direction = "l" }), { description = "Swap tiled window left" })
hl.bind("SUPER + ALT + right", hl.dsp.window.swap({ direction = "r" }), { description = "Swap tiled window right" })
hl.bind("SUPER + ALT + up", hl.dsp.window.swap({ direction = "u" }), { description = "Swap tiled window up" })
hl.bind("SUPER + ALT + down", hl.dsp.window.swap({ direction = "d" }), { description = "Swap tiled window down" })
hl.bind("ALT + Tab", hl.dsp.window.cycle_next({ next = true }), { repeating = true, description = "Cycle between windows" })
hl.bind("ALT + Tab", hl.dsp.window.alter_zorder({ mode = "top" }), { repeating = true, description = "Bring active floating window to the top" })
hl.bind("SUPER + CTRL + K", hl.dsp.layout("swapsplit"), { description = "Dwindle Layout- swap current focused window's halves" })
hl.bind("ALT + S", hl.dsp.layout("swapwithmaster master"), { description = "Master Layout - switch current focused window to master" })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("brightnessctl -q s +10% && notify-send \"Screen Brightness\" \"$(brightnessctl | grep -o '[0-9]*%' | head -1)\" -t 1000"), { description = "Increase brightness by 10%" })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -q s 10%- && notify-send \"Screen Brightness\" \"$(brightnessctl | grep -o '[0-9]*%' | head -1)\" -t 1000"), { description = "Reduce brightness by 10%" })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ 0 && pactl set-sink-volume @DEFAULT_SINK@ +5% && notify-send \"Volume\" \"$(pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -1)\" -t 1000"), { description = "Volume up" })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ 0 && pactl set-sink-volume @DEFAULT_SINK@ -5% && notify-send \"Volume\" \"$(pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -1)\" -t 1000"), { description = "Volume down" })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("pactl set-sink-mute @DEFAULT_SINK@ toggle && if pactl get-sink-mute @DEFAULT_SINK@ | grep -q 'yes'; then notify-send \"Volume\" \"Muted\" -t 1000; else notify-send \"Volume\" \"$(pactl get-sink-volume @DEFAULT_SINK@ | grep -o '[0-9]*%' | head -1)\" -t 1000; fi"), { description = "Mute Volume" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { description = "Audio play pause" })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl pause"), { description = "Audio pause" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { description = "Audio next" })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { description = "Audio previous" })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("pactl set-source-mute @DEFAULT_SOURCE@ toggle"), { description = "Toggle microphone" })
hl.bind("XF86Calculator", hl.dsp.exec_cmd("~/.config/hyprcandy/settings/calculator.sh"), { description = "Open calculator" })
hl.bind("code:236", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s +10 && notify-send \"Keyboard Backlight\" \"$(brightnessctl -d smc::kbd_backlight | grep -o '[0-9]*%' | head -1)\" -t 1000"), { description = "Keyboard brghtness up" })
hl.bind("code:237", hl.dsp.exec_cmd("brightnessctl -d smc::kbd_backlight s 10- && notify-send \"Keyboard Backlight\" \"$(brightnessctl -d smc::kbd_backlight | grep -o '[0-9]*%' | head -1)\" -t 1000"), { description = "Keyboard brghtness down" })

return true
