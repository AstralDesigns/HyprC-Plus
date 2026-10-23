import QtQuick

// Renders a distro brand logo: the real image when DistroState found one
// installed on the system, otherwise the monochrome Nerd Font glyph (which
// recolors with `color`). Drop this anywhere an icon is needed and give it a
// size via width/height or anchors; `pixelSize` drives the glyph cap height
// (and the image box is derived from it).
Item {
    id: root

    property string imagePath: ""
    property string glyph: ""
    property real pixelSize: 16
    property color color: Theme.cOnSecondary
    property string font: Config.fontFamily

    implicitWidth: Math.round(pixelSize)
    implicitHeight: Math.round(pixelSize)

    Image {
        id: img
        anchors.centerIn: parent
        width: Math.round(root.pixelSize * 1.15)
        height: width
        visible: root.imagePath.length > 0 && status === Image.Ready
        source: root.imagePath.length > 0 ? "file://" + root.imagePath : ""
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        // If the file disappears at runtime, fall back to the glyph.
        onStatusChanged: if (status === Image.Error) root.imagePath = ""
    }

    Text {
        anchors.centerIn: parent
        visible: !img.visible
        text: root.glyph
        color: root.color
        font.family: root.font
        font.pixelSize: Math.round(root.pixelSize)
    }
}
