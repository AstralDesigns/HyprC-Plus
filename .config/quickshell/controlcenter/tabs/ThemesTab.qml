import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ═══════════════════════════════════════════════════════════════════════════
//  ThemesTab.qml — Matugen M3 color scheme selection
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: tab
    implicitWidth: parent ? parent.width : 300
    implicitHeight: content.implicitHeight

    property string currentScheme: "scheme-content"

    FileView {
        id: schemeState
        path: CCConfig.configDir + "/matugen-state"
        watchChanges: true
        onLoaded: {
            const s = text().trim()
            if (s.length > 0) tab.currentScheme = s
        }
        Component.onCompleted: reload()
    }

    readonly property var schemeList: [
        { name: "Light",       scheme: "scheme-fidelity" },
        { name: "Dark",        scheme: "scheme-monochrome" },
        { name: "Content",     scheme: "scheme-content" },
        { name: "Expressive",  scheme: "scheme-expressive" },
        { name: "Neutral",     scheme: "scheme-neutral" },
        { name: "Rainbow",     scheme: "scheme-rainbow" },
        { name: "Tonal-spot",  scheme: "scheme-tonal-spot" },
        { name: "Fruit-salad", scheme: "scheme-fruit-salad" },
        { name: "Vibrant",     scheme: "scheme-vibrant" }
    ]

    // Apply theme process
    Process {
        id: applyProc
        property string _scheme: "scheme-content"
        property string _name: "Content"
        command: ["bash", "-c",
            "sed -i 's/--type scheme-[^ ]*/--type " + _scheme + "/' '" + CCConfig.wallpaperInt + "' && " +
            (function() {
                if (_name === "Light") return "sed -i 's/-m dark/-m light/g' '" + CCConfig.wallpaperInt + "'"
                else return "sed -i 's/-m light/-m dark/g' '" + CCConfig.wallpaperInt + "'"
            })() + " && " +
            "bash -c '$HOME/.config/hyprcandy/hooks/wallpaper_integration.sh' && " +
            "echo '" + _scheme + "' > '" + CCConfig.configDir + "/matugen-state'"
        ]
        running: false
        onExited: tab.currentScheme = _scheme
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right }
        anchors.margins: 8
        spacing: 4

        Text {
            text: "\udb84\udd0e Matugen Themes"
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont; font.pixelSize: 14; font.weight: Font.Bold
        }

        Repeater {
            model: tab.schemeList
            CCButton {
                required property var modelData
                Layout.fillWidth: true
                label: modelData.name
                active: tab.currentScheme === modelData.scheme
                onClicked: {
                    applyProc._scheme = modelData.scheme
                    applyProc._name = modelData.name
                    applyProc.running = true
                }
            }
        }
    }
}
