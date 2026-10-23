#!/bin/bash
#set +e

# Update local background.png
if command -v magick >/dev/null && [ -f "$HOME/.config/background" ]; then
    magick "$HOME/.config/background[0]" "$HOME/.config/background.png"
fi

# ── Update SDDM background path and BackgroundColor from waypaper/colors.css ──
WP_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/wallpaper/wallpaper.ini"
WAYPAPER_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/waypaper/config.ini"
# Prefer quickshell wallpaper picker config; fall back to waypaper
[[ -f "$WP_CONFIG" ]] && WAYPAPER_CONFIG="$WP_CONFIG"
SDDM_CONF="/usr/share/sddm/themes/sugar-candy/theme.conf"
SDDM_BG_DIR="/usr/share/sddm/themes/sugar-candy/Backgrounds"
COLORS_CSS="${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/colors.css"

if [[ -f "$WAYPAPER_CONFIG" && -f "$SDDM_CONF" ]]; then
    # ── Wallpaper path ────────────────────────────────────────────────────────
    CURRENT_WP=$(grep -E "^\s*wallpaper\s*=" "$WAYPAPER_CONFIG" \
        | head -n1 \
        | sed 's/.*=\s*//' \
        | sed "s|~|$HOME|g" \
        | xargs)

   if [[ -n "$CURRENT_WP" && -f "$CURRENT_WP" ]]; then
        WP_FILENAME=$(basename "$CURRENT_WP")
        WP_EXT="${WP_FILENAME##*.}"

        # webp is not supported by sugar-candy — convert to jpg first
        if [[ "${WP_EXT,,}" == "webp" ]]; then
            WP_FILENAME="${WP_FILENAME%.*}.jpg"
            sudo magick "$CURRENT_WP" "$SDDM_BG_DIR/$WP_FILENAME"
            sudo chmod 644 "$SDDM_BG_DIR/$WP_FILENAME"
            #echo "🔄 Converted webp → $WP_FILENAME"
        else
            sudo magick "$CURRENT_WP" "$SDDM_BG_DIR/$WP_FILENAME"
            sudo chmod 644 "$SDDM_BG_DIR/$WP_FILENAME"
        fi

        sudo sed -i "s|^Background=.*|Background=\"Backgrounds/$WP_FILENAME\"|" "$SDDM_CONF"
        #echo "🖥️  SDDM background updated → Backgrounds/$WP_FILENAME"
    fi

    # ── BackgroundColor from inverse_primary in colors.css ───────────────────
    if [[ -f "$COLORS_CSS" ]]; then
        FULL_HEX=$(grep -E '@define-color\s+inverse_primary\s+#' "$COLORS_CSS" \
            | head -n1 \
            | grep -oP '(?<=#)[0-9a-fA-F]{6}')

        if [[ -n "$FULL_HEX" ]]; then
            sudo sed -i "s|^BackgroundColor=.*|BackgroundColor=\"#$FULL_HEX\"|" "$SDDM_CONF"
            #echo "🎨 SDDM BackgroundColor updated → #$FULL_HEX (from inverse_primary)"
        else
            echo "⚠️  Could not parse inverse_primary from $COLORS_CSS"
        fi
    else
        echo "⚠️  colors.css not found at $COLORS_CSS"
    fi

    # ── AccentColor from surface_tint in colors.css ───────────────────
    if [[ -f "$COLORS_CSS" ]]; then
        FULL_HEX=$(grep -E '@define-color\s+surface_tint\s+#' "$COLORS_CSS" \
            | head -n1 \
            | grep -oP '(?<=#)[0-9a-fA-F]{6}')

        if [[ -n "$FULL_HEX" ]]; then
            sudo sed -i "s|^AccentColor=.*|AccentColor=\"#$FULL_HEX\"|" "$SDDM_CONF"
            #echo "🎨 SDDM AccentColor updated → #$FULL_HEX (from surface_tint)"
            pkill -f magick
        else
            echo "⚠️  Could not parse surface_tint from $COLORS_CSS"
        fi
    else
        echo "⚠️  colors.css not found at $COLORS_CSS"
    fi

else
    [[ ! -f "$WAYPAPER_CONFIG" ]] && echo "⚠️  waypaper config not found: $WAYPAPER_CONFIG"
    [[ ! -f "$SDDM_CONF" ]]      && echo "⚠️  SDDM config not found: $SDDM_CONF"
fi
