#!/usr/bin/env bash

# Export Qt icon/theme env vars from current GTK settings
# so each Quickshell launch reflects the active system theme.
qs_export_theme_env() {
    local gtk3="$HOME/.config/gtk-3.0/settings.ini"
    local gtk4="$HOME/.config/gtk-4.0/settings.ini"
    local icon_theme=""

    if [ -f "$gtk3" ]; then
        icon_theme=$(sed -n 's/^gtk-icon-theme-name=//p' "$gtk3" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi
    if [ -z "$icon_theme" ] && [ -f "$gtk4" ]; then
        icon_theme=$(sed -n 's/^gtk-icon-theme-name=//p' "$gtk4" | head -n1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    fi

    export QT_QPA_PLATFORMTHEME="${QT_QPA_PLATFORMTHEME:-qt6ct}"
    if [ -n "$icon_theme" ]; then
        export QT_ICON_THEME="$icon_theme"
    fi
}
