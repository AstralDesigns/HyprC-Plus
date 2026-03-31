pragma Singleton

import QtQuick
import QtCore

// ═══════════════════════════════════════════════════════════════════════════
//  CCConfig.qml — Paths & constants for the control center
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: cfg

    readonly property string home:        StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string configDir:   home + "/.config/hyprcandy"
    readonly property string hyprConf:    home + "/.config/hypr/hyprviz.conf"
    readonly property string hyprScripts: home + "/.config/hypr/scripts"
    readonly property string dockConfig:  home + "/.hyprcandy/GJS/hyprcandydock/config.js"
    readonly property string dockCycle:   home + "/.hyprcandy/GJS/hyprcandydock/cycle.sh"
    readonly property string dockToggle:  home + "/.hyprcandy/GJS/hyprcandydock/toggle.sh"
    readonly property string rofiBorder:  home + "/.config/hyprcandy/settings/rofi-border.rasi"
    readonly property string rofiRadius:  home + "/.config/hyprcandy/settings/rofi-border-radius.rasi"
    readonly property string rofiConf:    home + "/.config/rofi/config.rasi"
    readonly property string sddmTheme:   "/usr/share/sddm/themes/sugar-candy/theme.conf"
    readonly property string wallpaperInt: home + "/.config/hyprcandy/hooks/wallpaper_integration.sh"
    readonly property string userIconPath: configDir + "/user-icon.png"
    readonly property string usernamePath: configDir + "/username.txt"

    // Control center dimensions
    readonly property int    ccWidth:     340
    readonly property int    ccHeight:    680
    readonly property int    ccRadius:    16
    readonly property real   bgAlpha:     0.92

    // Fonts
    readonly property string fontFamily:  "Symbols Nerd Font Mono"
    readonly property string labelFont:   "JetBrainsMono Nerd Font"
}
