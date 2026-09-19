import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

// Start-menu / power button.
// Left-click → toggle start menu
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: Math.max(Config.moduleHeight, smIcon.implicitWidth + Config.btnPadLeft + Config.btnPadRight)
    implicitHeight: Config.moduleHeight

    property string _glyph: Config.ccGlyph

    Rectangle {
        id: smBg
        anchors.fill: parent
        radius: Config.islandRadius
        clip: true
        z: 0

        // Flat mode: SurfaceTint color background
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: Config.islandBgStyle !== "gradient"
            color: Theme.cSurfaceTint
            Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
        }

        // Gradient mode: InversePrimary at top -> SurfaceTint in center -> InversePrimary at bottom
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
        visible: Config.islandBorder > 0 && Config.islandBorderAlpha > 0
        z: 1
    }

    Text {
        id: smIcon
        anchors.centerIn: parent
        text: root._glyph
        color: Config.powerGlyphColor
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
        onClicked: StartMenuState.toggle()
    }
}
