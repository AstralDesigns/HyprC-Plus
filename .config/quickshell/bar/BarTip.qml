// BarTip — styled ToolTip replacement. Usage:
// Usage in any module:
//   BarTip { visible: ma.containsMouse; text: "Label"; delay: 500 }
//
// Styling matches waybar tooltips:
//   background: @on_primary (dark fill)   border: 2px @inverse_primary   radius: 6px
//   text:       @primary                  font: labelFont / labelFontSize
//
// Position: below parent for top bar, above for bottom bar.

import QtQuick
import QtQuick.Controls

ToolTip {
    id: tip

    padding: 0
    closePolicy: Popup.NoAutoClose

    // Position below the triggering item (works for top bar)
    // The parent is the Item that contains this BarTip
    x: parent ? Math.max(2, (parent.width - implicitWidth) / 2) : 0
    y: parent ? parent.height + 4 : 0

    background: Rectangle {
        color:        Theme.cOnPrimary
        border.color: Theme.cInversePrimary
        border.width: 2
        radius:       6
        layer.enabled: true
    }

    contentItem: Text {
        text:             tip.text
        color:            Theme.cPrimary
        font.family:      Config.labelFont
        font.pixelSize:   Config.labelFontSize
        font.weight:      Font.Normal
        leftPadding:  8;  rightPadding:  8
        topPadding:   5;  bottomPadding: 5
        wrapMode:         Text.WordWrap
        maximumLineCount: 4
    }
}
