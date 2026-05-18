#!/bin/bash

GTK3_FILE="$HOME/.config/gtk-3.0/settings.ini"
GTK4_FILE="$HOME/.config/gtk-4.0/settings.ini"
HYPRLUA="$HOME/.config/hypr/hyprviz.lua"

get_value() {
    grep -E "^$1=" "$1" 2>/dev/null | cut -d'=' -f2 | tr -d ' '
}

extract_cursor_theme() {
    grep -E "^gtk-cursor-theme-name=" "$1" | cut -d'=' -f2 | tr -d ' '
}

extract_cursor_size() {
    grep -E "^gtk-cursor-theme-size=" "$1" | cut -d'=' -f2 | tr -d ' '
}

update_hypr_cursor_env() {
    local theme="$1"
    local size="$2"

    [ -z "$theme" ] && return
    [ -z "$size" ] && return

    # Replace each hl.env line in hyprviz.lua
    sed -i "s|hl.env(\"XCURSOR_THEME\", \".*\")|hl.env(\"XCURSOR_THEME\", \"$theme\")|" "$HYPRLUA"
    sed -i "s|hl.env(\"XCURSOR_SIZE\", \".*\")|hl.env(\"XCURSOR_SIZE\", \"$size\")|" "$HYPRLUA"
    sed -i "s|hl.env(\"HYPRCURSOR_THEME\", \".*\")|hl.env(\"HYPRCURSOR_THEME\", \"$theme\")|" "$HYPRLUA"
    sed -i "s|hl.env(\"HYPRCURSOR_SIZE\", \".*\")|hl.env(\"HYPRCURSOR_SIZE\", \"$size\")|" "$HYPRLUA"
    
    # Sync GTK4 with GTK3
    sed -i "s|^gtk-cursor-theme-name=.*|gtk-cursor-theme-name=$theme|" "$GTK4_FILE"
    sed -i "s|^gtk-cursor-theme-size=.*|gtk-cursor-theme-size=$size|" "$GTK4_FILE" 

    # SDDM cursor update
    sudo sed -i "s|^CursorTheme=.*|CursorTheme=$theme|" "/etc/sddm.conf.d/sugar-candy.conf"
    sudo sed -i "s|^CursorSize=.*|CursorSize=$size|" "/etc/sddm.conf.d/sugar-candy.conf"

    # Apply changes immediately
    apply_cursor_changes "$theme" "$size"

    echo "✅ Updated and applied cursor theme: $theme / $size"
}

apply_cursor_changes() {
    local theme="$1"
    local size="$2"
    
    # Apply cursor changes immediately using hyprctl
    hyprctl setcursor "$theme" "$size" 2>/dev/null || {
        echo "⚠️  hyprctl setcursor failed, falling back to reload"
        hyprctl reload 2>/dev/null
    }
    
    # Method 2: Set cursor for current session (fallback)
    if command -v gsettings >/dev/null 2>&1; then
        gsettings set org.gnome.desktop.interface cursor-theme "$theme" 2>/dev/null || true
        gsettings set org.gnome.desktop.interface cursor-size "$size" 2>/dev/null || true
    fi
    
    # Method 3: Update X11 cursor (if running under Xwayland apps)
    if [ -n "$DISPLAY" ]; then
        echo "Xcursor.theme: $theme" | xrdb -merge 2>/dev/null || true
        echo "Xcursor.size: $size" | xrdb -merge 2>/dev/null || true
    fi
}

watch_gtk_file() {
    local file="$1"
    echo "👁 Watching $file for cursor changes..."
    inotifywait -m -e modify "$file" | while read -r; do
        theme=$(extract_cursor_theme "$file")
        size=$(extract_cursor_size "$file")
        update_hypr_cursor_env "$theme" "$size"
        sleep 0.5
        systemctl --user restart cursor-theme-watcher.service
    done
}

# Initial sync if file exists
for gtk_file in "$GTK3_FILE" "$GTK4_FILE"; do
    if [ -f "$gtk_file" ]; then
        theme=$(extract_cursor_theme "$gtk_file")
        size=$(extract_cursor_size "$gtk_file")
        update_hypr_cursor_env "$theme" "$size"
    fi
done

# Start watchers in background
watch_gtk_file "$GTK3_FILE" &
wait
