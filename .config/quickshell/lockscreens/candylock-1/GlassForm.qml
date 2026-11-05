// GlassForm.qml — a reusable frosted-glass panel for the candylock-1 lockscreen.
//
// Renders a rounded rect that blurs the wallpaper region behind it (offset to the
// item's scene position) and tints it with the theme's inverse-primary, matching
// the frosted look the single centerPanel used to provide — but now per card.
//
// Usage:  GlassForm { anchors.fill: parent; radius: 30; wallpaper: root.wallpaperPath; tintColor: root.cInvPrimary }
import QtQuick
import QtQuick.Effects
import Quickshell

Item {
    id: glass

    property real radius: 30
    property string wallpaper: ""
    property Item bg: null            // the item the wallpaper fills (uiRoot) — slice is aligned to it
    // Callers supply the theme inverse-primary (shell.qml passes root.cInvPrimary);
    // this is only an unused fallback, so it stays transparent rather than black.
    property color tintColor: Qt.rgba(0, 0, 0, 0)
    property real tintAlpha: 0.45     // matches the powerpill form tint (cPanel = inversePrimary @ 0.45)
    readonly property size _screen: Quickshell.primaryScreen
        ? Qt.size(Quickshell.primaryScreen.geometry.width, Quickshell.primaryScreen.geometry.height)
        : Qt.size(1280, 800)

    // Clip the blurred wallpaper + tint to the rounded form.
    layer.enabled: true
    layer.effect: MultiEffect {
        maskEnabled:      true
        maskSource:       glassMask
        maskThresholdMin: 0.5
        maskSpreadAtMin:  1.0
    }

    Rectangle {
        id: glassMask
        anchors.fill: parent
        radius: glass.radius
        color: "white"
        opacity: 0
        layer.enabled: true
    }

    // Blurred wallpaper slice, positioned so it lines up with what is behind this
    // item on screen (scene coordinates via mapToItem(null, …)).
    Item {
        anchors.fill: parent
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
        Image {
            // Align the blurred slice to the wallpaper that fills `bg` (uiRoot),
            // exactly like the powerpill/centerPanel slices (x: -powerRow.x, w:
            // uiRoot.width). The earlier scene-space mapToItem(null) left the far
            // side of the form uncovered, which read as transparent instead of blurred.
            readonly property point _o: glass.mapToItem(bg || glass, 0, 0)
            x: -_o.x
            y: -_o.y
            width:  bg ? bg.width  : glass._screen.width
            height: bg ? bg.height : glass._screen.height
            source: glass.wallpaper !== "" ? ("file://" + glass.wallpaper) : ""
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: true
        }
    }

    // Inverse-primary tint over the blur.
    Rectangle {
        anchors.fill: parent
        radius: glass.radius
        color: Qt.rgba(glass.tintColor.r, glass.tintColor.g, glass.tintColor.b, glass.tintAlpha)
    }
}
