#!/bin/bash
# HyprCandy greeter runtime sync — run as root (sudo -n greeter-sync.sh).
# Mirrors the home theme tree into the world-readable runtime location SDDM
# needs: palettes + qmldir + current wallpaper, then points the active
# theme's Background key at the synced copy. Idempotent; silent on missing
# sources so it is safe to call from matugen/wallust/wallpaper hooks.
set -u

SUDO_HOME="${HC_GREETER_HOME:-$(getent passwd "${SUDO_UID:-$(id -u)}" | cut -d: -f6)}"
GT_DIR="$SUDO_HOME/.hyprcandy/Greeter/themes"
SHARED="/usr/share/sddm/themes/hyprcandy-shared"
CONF_DIR="/etc/sddm.conf.d"

current_theme() {
    local f="" raw=""
    for f in "$CONF_DIR/hyprcandy.conf" "$CONF_DIR/sugar-candy.conf"; do
        [ -f "$f" ] || continue
        raw=$(sed -n 's/^Current=//p' "$f" | head -1)
        [ -n "$raw" ] && break
    done
    raw=${raw#\"}; raw=${raw%\"}
    printf '%s' "$(printf '%s' "$raw" | tr -d '[:space:]')"
}

mkdir -p "$SHARED/Backgrounds"

# ── palettes ──────────────────────────────────────────────────────────────
for qml in Appearance.colors.qml Appearance.wallust.qml; do
    if [ -f "$GT_DIR/$qml" ]; then
        cp -f "$GT_DIR/$qml" "$SHARED/$qml"
        chmod 644 "$SHARED/$qml"
    fi
done

# Boot-safety defaults: the greeter must render even before the first
# wallpaper change ever ran matugen/wallust.
if [ ! -f "$SHARED/Appearance.colors.qml" ]; then
    cat > "$SHARED/Appearance.colors.qml" << 'EOF'
pragma Singleton
import QtQuick

QtObject {
    property bool darkmode: true
    property color m3sourceColor: "#8ec8ea"
    property color m3primary: "#8ec8ea"
    property color m3onPrimary: "#000f16"
    property color m3primaryContainer: "#346985"
    property color m3onPrimaryContainer: "#ffffff"
    property color m3onPrimaryFixedVariant: "#0b2a3a"
    property color m3secondary: "#aec4d2"
    property color m3secondaryFixed: "#dbe0e3"
    property color m3onSecondary: "#091218"
    property color m3secondaryContainer: "#455763"
    property color m3onSecondaryContainer: "#ffffff"
    property color m3background: "#091218"
    property color m3onBackground: "#dedfe2"
    property color m3surface: "#09090a"
    property color m3surfaceTint: "#8ec8ea"
    property color m3surfaceContainerLow: "#0b0c0d"
    property color m3surfaceContainer: "#131416"
    property color m3surfaceContainerHigh: "#1e2022"
    property color m3surfaceContainerHighest: "#292b2e"
    property color m3onSurface: "#e2e4e7"
    property color m3surfaceVariant: "#2f3539"
    property color m3onSurfaceVariant: "#bac1c8"
    property color m3inversePrimary: "#134861"
    property color m3inverseSurface: "#dedfe2"
    property color m3inverseOnSurface: "#1a1c1d"
    property color m3outline: "#868c92"
    property color m3outlineVariant: "#4f555a"
    property color m3shadow: "#000000"
    property color m3primaryFixed: "#c7e7ff"
    property color m3primaryFixedDim: "#8ec8ea"
    property color m3onPrimaryFixed: "#001e2e"
    property color m3tertiary: "#e0b3eb"
    property color m3onTertiary: "#2f0043"
    property color m3tertiaryContainer: "#7d5a88"
    property color m3onTertiaryContainer: "#ffd7fb"
    property color m3tertiaryFixed: "#fbd7ff"
    property color m3tertiaryFixedDim: "#dec0e2"
}
EOF
    chmod 644 "$SHARED/Appearance.colors.qml"
fi
if [ ! -f "$SHARED/Appearance.wallust.qml" ]; then
    {
        echo "pragma Singleton"
        echo "import QtQuick"
        echo ""
        echo "QtObject {"
        echo "    property bool darkmode: true"
        n=0
        while [ $n -le 15 ]; do
            echo "    property color m3color$n: \"#8ec8ea\""
            n=$((n + 1))
        done
        echo "}"
    } > "$SHARED/Appearance.wallust.qml"
    chmod 644 "$SHARED/Appearance.wallust.qml"
fi

# ── QML module dir (singleton registrations) ──────────────────────────────
cat > "$SHARED/qmldir" << 'EOF'
module hyprcandy-shared
singleton Colors 1.0 Appearance.colors.qml
singleton Wallust 1.0 Appearance.wallust.qml
EOF
chmod 644 "$SHARED/qmldir"

# ── current wallpaper ─────────────────────────────────────────────────────
WP=""
for c in "$HOME/.config/wallpaper/wallpaper.ini" \
         "$SUDO_HOME/.config/wallpaper/wallpaper.ini" \
         "$SUDO_HOME/.config/waypaper/config.ini"; do
    [ -f "$c" ] || continue
    raw=$(grep -E '^[[:space:]]*wallpaper[[:space:]]*=' "$c" | head -1 | sed 's/^[^=]*=//' | xargs)
    raw=${raw/#\~/$SUDO_HOME}
    [ -n "$raw" ] && [ -f "$raw" ] && { WP="$raw"; break; }
done

if [ -n "$WP" ]; then
    ext="${WP##*.}"
    ext=$(printf '%s' "$ext" | tr '[:upper:]' '[:lower:]')
    case "$ext" in
        gif)
            cp -f "$WP" "$SHARED/Backgrounds/current.gif"
            chmod 644 "$SHARED/Backgrounds/current.gif"
            bg="../hyprcandy-shared/Backgrounds/current.gif"
            ;;
        *)
            if command -v magick >/dev/null 2>&1; then
                magick "$WP[0]" "$SHARED/Backgrounds/current.jpg" 2>/dev/null ||
                    magick "$WP" "$SHARED/Backgrounds/current.jpg" 2>/dev/null
            fi
            if [ ! -s "$SHARED/Backgrounds/current.jpg" ]; then
                cp -f "$WP" "$SHARED/Backgrounds/current.jpg" 2>/dev/null || true
            fi
            chmod 644 "$SHARED/Backgrounds/current.jpg" 2>/dev/null || true
            bg="../hyprcandy-shared/Backgrounds/current.jpg"
            ;;
    esac

    # point the ACTIVE theme's Background at the synced copy (only for
    # hyprcandy-owned themes; sugar-candy keeps its legacy hook flow)
    id=$(current_theme)
    tconf="/usr/share/sddm/themes/$id/theme.conf"
    if [ -n "$id" ] && [ "$id" != "sugar-candy" ] && [ -f "$tconf" ]; then
        sed -i "s|^Background=.*|Background=\"$bg\"|" "$tconf"
        case "$tconf" in "$SUDO_HOME"/*) chown "${SUDO_UID:-0}:${SUDO_GID:-0}" "$tconf" 2>/dev/null || true ;; esac
    fi
fi

chmod a+rX /usr/share/sddm/themes/hyprcandy-shared /usr/share/sddm/themes/hyprcandy-shared/Backgrounds 2>/dev/null || true
