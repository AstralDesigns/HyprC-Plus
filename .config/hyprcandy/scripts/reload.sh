#!/bin/bash

reload_colors() {
    touch "$HOME/.config/gtk-3.0/colors.css"
    touch "$HOME/.config/gtk-3.0/gtk.css"
    touch "$HOME/.config/gtk-4.0/colors.css"
    touch "$HOME/.config/gtk-4.0/gtk.css"
    touch "$HOME/.config/qt5ct/qt5ct.conf"
    touch "$HOME/.config/qt6ct/qt6ct.conf"
    sync
    
    #gsettings set org.gnome.desktop.interface gtk-theme 'Default'
    gsettings set org.gnome.desktop.interface color-scheme 'default'
    sleep 0.5
    #gsettings set org.gnome.desktop.interface gtk-theme "adw-gtk3-dark"
    gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
    
    sudo dconf update
}

update_hypr_group_text() {
    local COLORS_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/colors.conf"
    local HYPRVIZ_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/hyprviz.conf"

    if [[ ! -f "$COLORS_CONF" ]]; then
        echo "update_hypr_group_text: colors.conf not found at $COLORS_CONF"
        return 1
    fi

    if [[ ! -f "$HYPRVIZ_CONF" ]]; then
        echo "update_hypr_group_text: hyprviz.conf not found at $HYPRVIZ_CONF"
        return 1
    fi

    local BG_LINE
    local PAT='(?<=rgba\()[0-9a-fA-F]{6}'
    BG_LINE=$(grep -E '^\$source_color\s*=' "$COLORS_CONF" | head -n1)
    BG_HEX=$(echo "$BG_LINE" | grep -oP "$PAT")

    if [[ -z "$BG_HEX" ]]; then
        echo "update_hypr_group_text: could not parse \$source_color from $COLORS_CONF"
        return 1
    fi

    local R G B
    R=$((16#${BG_HEX:0:2}))
    G=$((16#${BG_HEX:2:2}))
    B=$((16#${BG_HEX:4:2}))

    local LUMINANCE
    LUMINANCE=$(echo "scale=2; 0.2126 * $R + 0.7152 * $G + 0.0722 * $B" | bc)
    local LUMINANCE_INT=${LUMINANCE%.*}

    local MAX MIN SATURATION
    MAX=$(echo -e "$R\n$G\n$B" | sort -n | tail -1)
    MIN=$(echo -e "$R\n$G\n$B" | sort -n | head -1)

    if (( MAX == MIN )); then
        SATURATION=0
    else
        local LIGHTNESS_RAW=$(( (MAX + MIN) / 2 ))
        if (( LIGHTNESS_RAW <= 127 )); then
            SATURATION=$(( (MAX - MIN) * 100 / (MAX + MIN) ))
        else
            SATURATION=$(( (MAX - MIN) * 100 / (510 - MAX - MIN) ))
        fi
    fi

    if (( LUMINANCE_INT > 150 && SATURATION >= 40 )); then
        local TEXT_COLOR="\$inverse_primary"
    elif (( LUMINANCE_INT <= 150 && SATURATION <= 20 )); then
        local TEXT_COLOR="\$surface_tint"
    elif (( LUMINANCE_INT <= 150 && SATURATION > 20 )); then
        local TEXT_COLOR="\$surface_tint"
    elif (( LUMINANCE_INT > 150 && SATURATION >= 20 && SATURATION < 40 )); then
        local TEXT_COLOR="\$secondary_container"
    else
        local TEXT_COLOR="\$on_primary_fixed_variant"
    fi

    sed -i "s|^\(\s*text_color\s*=\).*|\1 $TEXT_COLOR|" "$HYPRVIZ_CONF"
    echo "update_hypr_group_text: source_color luminance=${LUMINANCE_INT}/255 saturation=${SATURATION}% → text_color = $TEXT_COLOR"
}

reload_colors
update_hypr_group_text
