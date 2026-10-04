import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

// Control-center launcher button.
// ccGlyph is the default; reads ~/.config/hyprcandy/candy-start-icon.txt if present.
// Left-click → toggle control center
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: Config.moduleHeight
    implicitHeight: Config.moduleHeight

    property string _glyph: Config.ccGlyph

    // Live state file
    FileView {
        path: Quickshell.env("HOME") + "/.config/hyprcandy/candy-start-icon.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const g = text().trim()
            if (g.length > 0) root._glyph = g
        }
    }

    // Island background — mirrors StartMenu.qml so the two bar buttons match:
    // glass/flat = SurfaceTint fill, gradient = InversePrimary→SurfaceTint→InversePrimary.
    Rectangle {
        id: ccBg
        anchors.fill: parent
        radius: Config.islandRadius
        clip: true
        z: 0

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: Config.islandBgStyle !== "gradient"
            color: Theme.cSurfaceTint
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: Config.islandBgStyle === "gradient"
            gradient: Gradient {
                orientation: Gradient.Vertical
                GradientStop { position: 0.0; color: Theme.cInversePrimary }
                GradientStop { position: 0.35; color: Theme.cSurfaceTint }
                GradientStop { position: 0.7; color: Theme.cSurfaceTint }
                GradientStop { position: 1.0; color: Theme.cInversePrimary }
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: Config.islandRadius
        color: "transparent"
        border.width: Config.islandBorder
        border.color: Qt.rgba(Config.islandBorderColor.r, Config.islandBorderColor.g,
                              Config.islandBorderColor.b, Config.islandBorderAlpha)
        visible: Config.borderDistro && Config.islandBorder > 0 && Config.islandBorderAlpha > 0
        z: 1
    }

    Text {
        id: ccIcon
        anchors.centerIn: parent
        text: root._glyph
        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, Config.ccGlyphOpacity)
        font.family: Config.fontFamily
        font.pixelSize: Config.glyphSize + 2
        z: 2
        Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: 3
        onClicked: ControlCenterState.toggle()
    }
}
