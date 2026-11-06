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

    // Blurred wallpaper slice — mirrors the power-pill/dials recipe that blurs
    // fully: a form-sized Item carries the blur layer (with layer.smooth) and the
    // bg-sized wallpaper Image overflows inside it, offset to the form's position
    // in `bg`, so every part of the form samples real wallpaper with no edge falloff.
    Item {
        anchors.fill: parent
        anchors.margins: -80          // oversize so the form edges sit inside the blurred layer (no falloff)
        layer.enabled: true
        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
        layer.smooth: true
        Image {
            readonly property point _o: parent.mapToItem(bg || parent, 0, 0)
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
