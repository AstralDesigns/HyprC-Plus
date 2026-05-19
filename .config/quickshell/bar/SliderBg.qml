import QtQuick
import ".."

Item {
    id: sl
    property real value: 0.0
    property color gradA: Theme.cInversePrimary
    property color gradB: Theme.cOnPrimary
    property color track: Theme.cOutVar
    property color accent: Theme.cPrimary
    signal moved(real v)

    // Trough — taller, with inner padding so fill + thumb sit inside it
    readonly property int trackH: 14
    readonly property int pad: 3
    readonly property int innerH: trackH - pad * 2

    Item {
        y: (parent.height - sl.trackH) / 2
        width: parent.width; height: sl.trackH

        // Trough background
        Rectangle {
            anchors.fill: parent; radius: sl.trackH / 2
            color: Qt.rgba(sl.track.r, sl.track.g, sl.track.b, 0.28)
            border.width: 1; border.color: Qt.rgba(sl.accent.r, sl.accent.g, sl.accent.b, 0.55)
        }

        // Gradient fill — inset by pad, clipped to left portion
        Item {
            x: sl.pad; y: sl.pad
            width:  Math.max(0, (parent.width - sl.pad * 2) * sl.value)
            height: sl.innerH
            clip: true
            Rectangle {
                width: parent.parent.width - sl.pad * 2
                height: sl.innerH
                radius: sl.innerH / 2
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: sl.gradA }
                    GradientStop { position: 1.0; color: sl.gradB }
                }
            }
        }

        // Thumb — dot-circle glyph sitting inside the trough
        Text {
            text: "󰟃"
            font.family: "Symbols Nerd Font Mono"
            font.pixelSize: sl.innerH + 2
            color: sl.accent
            style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.25)
            x: {
                const tw = parent.width - sl.pad * 2
                const cx = sl.pad + tw * sl.value - implicitWidth / 2
                return Math.max(sl.pad - implicitWidth/2 + 1,
                       Math.min(parent.width - sl.pad - implicitWidth/2 - 1, cx))
            }
            y: (sl.trackH - implicitHeight) / 2
        }
    }

    MouseArea {
        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        preventStealing: true
        onPressed: function(ev) {
            sl.value = Math.max(0, Math.min(1, ev.x / parent.width))
            sl.moved(sl.value)
        }
        onPositionChanged: function(ev) {
            if (pressedButtons) {
                sl.value = Math.max(0, Math.min(1, ev.x / parent.width))
                sl.moved(sl.value)
            }
        }
        onWheel: function(e) {
            const step = 0.02 * (e.angleDelta.y > 0 ? 1 : -1)
            const v = Math.max(0, Math.min(1, sl.value + step))
            sl.value = v
            sl.moved(v)
        }
    }
}
