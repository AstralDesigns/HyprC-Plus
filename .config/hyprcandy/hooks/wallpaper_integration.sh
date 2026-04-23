#!/bin/bash

CONFIG_BG="$HOME/.config/background"
WP_CONFIG="$HOME/.config/wallpaper/wallpaper.ini"
WAYPAPER_CONFIG="$HOME/.config/waypaper/config.ini"
MATUGEN_CONFIG="$HOME/.config/matugen/config.toml"
RELOAD_SO="/usr/local/lib/gtk3-reload.so"
RELOAD_SRC="/usr/local/share/gtk3-reload/gtk3-reload.c"
HOOKS_DIR="$HOME/.config/hyprcandy/hooks"

get_waypaper_background() {
    # Prefer quickshell wallpaper picker config, fall back to waypaper config
    for cfg in "$WP_CONFIG" "$WAYPAPER_CONFIG"; do
        if [ -f "$cfg" ]; then
            current_bg=$(grep -E "^wallpaper\s*=" "$cfg" | head -n1 | cut -d'=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$current_bg" ]; then
                current_bg=$(echo "$current_bg" | sed "s|^~|$HOME|")
                echo "$current_bg"
                return 0
            fi
        fi
    done
    return 1
}

update_config_background() {
    local bg_path="$1"
    if [ -f "$bg_path" ] && [ -f "$MATUGEN_CONFIG" ]; then
        echo "🎨 Triggering matugen color generation..."
        wal -i "$bg_path" -n --cols16 darken --backend colorthief --contrast 1.5 --saturate 0.25 2>/dev/null
		matugen image "$bg_path" --type scheme-fidelity -m dark -r nearest --base16-backend wal --lightness-dark -0.1 --source-color-index 0 --contrast 0.2 2>/dev/null
        sleep 0.5
        magick "$bg_path" "$HOME/.config/background"
        sleep 1
        "$HOOKS_DIR/update_background.sh"
        #echo "✅ Updated ~/.config/background to point to: $bg_path"
        return 0
    else
        echo "❌ Background file not found: $bg_path"
        return 1
    fi
}

main() {
    echo "🎯 Waypaper integration triggered"
    current_bg=$(get_waypaper_background)
    if [ $? -eq 0 ]; then
        echo "📸 Current Waypaper background: $current_bg"
        if update_config_background "$current_bg"; then
           echo "✅ Color generation processes complete"
        fi
    else
        echo "⚠️  Could not determine current Waypaper background"
    fi
}

main
