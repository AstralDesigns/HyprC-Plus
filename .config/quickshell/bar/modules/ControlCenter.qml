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
    readonly property bool _distro:    Config.ccIconMode === "distro"
    readonly property bool _custom:    Config.ccIconMode === "custom"
    readonly property bool _glyphMode: !root._distro && !root._custom

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

    // ── Icon: Glyph | Distro | Custom (Bar:Icons → Control Center) ───────
    // glyph  → the ccGlyph text (live-overridable via candy-start-icon.txt)
    // distro → detected distro brand image, else its Nerd Font glyph
    // custom → a user image chosen from ~/Pictures/Icons
    // ccGlyphOpacity fades all three (color alpha for the glyph, element
    // opacity for images).
    Text {
        id: ccIcon
        anchors.centerIn: parent
        visible: root._glyphMode
        text: root._glyph
        color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, Config.ccGlyphOpacity)
        font.family: Config.fontFamily
        font.pixelSize: Config.glyphSize + 2
        z: 2
        Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
    }

    DistroIconView {
        anchors.centerIn: parent
        visible: root._distro
        opacity: Config.ccGlyphOpacity
        imagePath: DistroState.imagePath
        glyph: DistroState.glyph
        pixelSize: Config.glyphSize + 2
        color: Theme.cOnSecondary
        z: 2
    }

    Item {
        anchors.centerIn: parent
        visible: root._custom
        opacity: Config.ccGlyphOpacity
        // Match DistroIconView's image sizing exactly (pixelSize * 1.15) so the
        // custom logo scales 1:1 with the Glyph Size slider like the other modes.
        readonly property real _d: Math.round((Config.glyphSize + 2) * 1.15)
        width: _d
        height: _d
        z: 2
        Image {
            anchors.fill: parent
            visible: Config.ccCustomIconPath.length > 0 && status === Image.Ready
            source: Config.ccCustomIconPath.length > 0 ? "file://" + Config.ccCustomIconPath : ""
            sourceSize.width: parent._d * 2
            sourceSize.height: parent._d * 2
            fillMode: Image.PreserveAspectFit
            smooth: true
            mipmap: true
            asynchronous: true
        }
        // Placeholder when no custom image is chosen yet.
        Text {
            anchors.centerIn: parent
            visible: !(Config.ccCustomIconPath.length > 0)
            text: ""
            font.family: Config.fontFamily
            font.pixelSize: Config.glyphSize + 2
            color: Theme.cOnSecondary
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 150 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        z: 3
        onEntered: if (Config.tipControlCenter) BarTipState.show("Left-click: Control center", parent)
        onExited: BarTipState.hide(parent)
        onClicked: ControlCenterState.toggle()
    }
}
