pragma Singleton

import QtQuick
import Quickshell.Io

// Central distro identity + logo source of truth for the whole bar.
// Resolved once at boot (this singleton is instantiated the first time any
// consumer touches it — ControlCenter button, dock start badge, System tab).
//
//   osId      → the ID= field from /etc/os-release (lower-cased)
//   glyph     → monochrome Nerd Font distro glyph; unknown distros fall back
//               to the Hyprland logo glyph (\u{F359})
//   imagePath → absolute path to a real brand logo shipped by the distro
//               (searched in /usr/share/icons, /usr/share/pixmaps + hicolor),
//               or "" when none.
//
// DistroIconView renders imagePath when present, otherwise the glyph.
QtObject {
    id: root

    property string osId: ""
    property string glyph: "\u{F359}"   // nf-md-linux_hyprland (safe default)
    property string imagePath: ""
    property string wmName: "Unknown"

    // Nerd Font glyphs for Arch + its derivatives and other common distros.
    // Anything unmapped keeps the Hyprland default.
    readonly property var _glyphs: {
        "arch": "\uf303", "archlinux": "\uf303", "cachyos": "\uf303",
        "chaotic": "\uf303", "arcolinux": "\uf303", "endeavouros": "\uf322",
        "manjaro": "\uf312", "garuda": "\uf337", "artix": "\uf31f",
        "antergos": "\uf311", "chakra": "\uf302",
        "ubuntu": "\uf31b", "debian": "\uf306", "fedora": "\uf30a",
        "opensuse": "\uf314", "opensuse-tumbleweed": "\uf314",
        "gentoo": "\uf30d", "void": "\uf32f", "alpine": "\uf300",
        "linuxmint": "\uf30f", "mint": "\uf30f", "pop": "\uf32a",
        "zorin": "\uf33f", "nixos": "\u{f1105}", "kali": "\uf327",
        "raspbian": "\uf315", "centos": "\uf305", "rhel": "\uf316",
    }

    readonly property Process _probe: Process {
        command: ["bash", "-c",
            ". /etc/os-release 2>/dev/null; " +
            "OS_ID=${ID:-}; " +
            "printf 'OSID:%s\\n' \"$OS_ID\"; " +
            "printf 'WM:%s\\n' \"${XDG_CURRENT_DESKTOP:-${DESKTOP_SESSION:-Unknown}}\"; " +
            // ── Distro brand logo resolution. Candidate priority: absolute
            //    LOGO= path → /usr/share/icons/<name> → pixmaps → hicolor.
            //    CachyOS etc. resolve to their own shipped logo when present,
            //    else the Arch fallback, else the generic distributor-logo. ──
            "ID_LOWER=$(echo \"${OS_ID}\" | tr '[:upper:]' '[:lower:]'); " +
            "ICON_PATH=''; " +
            "if [ -n \"${LOGO:-}\" ] && [ \"${LOGO#/}\" != \"$LOGO\" ] && [ -f \"$LOGO\" ]; then ICON_PATH=\"$LOGO\"; fi; " +
            "if [ -z \"$ICON_PATH\" ]; then " +
            "  for cand in \"${LOGO:-}\" \"distributor-logo-${ID_LOWER}\" \"${ID_LOWER}-logo\" \"${ID_LOWER}\" \"distributor-logo-archlinux\" \"archlinux-logo\" \"distributor-logo\"; do " +
            "    [ -z \"$cand\" ] && continue; " +
            "    for f in \"/usr/share/icons/${cand}.svg\" \"/usr/share/icons/${cand}.png\" \"/usr/share/pixmaps/${cand}.png\" \"/usr/share/pixmaps/${cand}.svg\"; do " +
            "      [ -f \"$f\" ] && { ICON_PATH=\"$f\"; break; }; done; " +
            "    [ -n \"$ICON_PATH\" ] && break; " +
            "    for sz in 256x256 128x128 64x64 48x48 scalable; do " +
            "      for cat in apps places; do " +
            "        for ext in png svg; do f=\"/usr/share/icons/hicolor/${sz}/${cat}/${cand}.${ext}\"; [ -f \"$f\" ] && { ICON_PATH=\"$f\"; break 3; }; done; " +
            "      done; " +
            "    done; " +
            "    [ -n \"$ICON_PATH\" ] && break; " +
            "  done; " +
            "fi; " +
            "printf 'LOGOICON:%s\\n' \"$ICON_PATH\"; "
        ]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const i = line.indexOf(":")
                if (i < 0) return
                const k = line.slice(0, i)
                const v = line.slice(i + 1)
                if (k === "OSID") {
                    const id = v.trim().toLowerCase()
                    root.osId = id
                    root.glyph = root._glyphs[id] ?? "\u{F359}"
                } else if (k === "LOGOICON") {
                    root.imagePath = v.trim()
                } else if (k === "WM") {
                    root.wmName = v.trim().length > 0 ? v.trim() : "Unknown"
                }
            }
        }
    }

    function refresh() { _probe.running = false; _probe.running = true }
}
