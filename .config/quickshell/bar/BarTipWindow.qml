import QtQuick
import Quickshell
import Quickshell.Widgets

// Floating hover tooltip for the bar modules (driven by BarTipState). Rendered
// as its own PopupWindow anchored to the hovered module's own window via
// mapFromItem — mirroring Quickshell's built-in Tooltip — so it escapes the
// thin island surfaces it would otherwise be clipped by and follows the module
// across islands/monitors. Multi-line text stacks one action per line.
//
// Position is driven by a Binding on anchor.rect rather than an onAnchoring
// handler: onAnchoring only re-runs when the anchor *window* changes, so it
// would leave the popup stranded when BarTipState swaps between two modules in
// the same island. The Binding re-evaluates on every anchorItem / size change,
// which is what makes the dock-style sweep feel seamless.
PopupWindow {
    id: popup
    color: "transparent"
    visible: BarTipState.visible

    readonly property Item anchorItem: BarTipState.target
    readonly property bool _below: Config.barPosition !== "bottom"

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight

    function _anchoredRect() {
        if (!anchorItem || !anchorItem.QsWindow.window) return Qt.rect(0, 0, 0, 0)
        const gx = anchorItem.width / 2 - popup.width / 2 + BarTipState.offsetX
        const gy = popup._below ? anchorItem.height + 6 : -(popup.height + 6)
        const pos = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, gx, gy)
        return Qt.rect(pos.x, pos.y, 0, 0)
    }

    anchor {
        window: anchorItem ? anchorItem.QsWindow.window : null
        adjustment: PopupAdjustment.None
        gravity: Edges.Bottom | Edges.Right
    }

    Binding {
        target: popup.anchor
        property: "rect"
        value: popup._anchoredRect()
        when: popup.anchorItem !== null
    }

    Rectangle {
        id: box
        radius: BarTipState.radius
        color: Theme.cOnSecondary
        border.color: Theme.cInversePrimary
        border.width: 1

        implicitWidth: label.implicitWidth + 18
        implicitHeight: label.implicitHeight + 12

        Text {
            id: label
            anchors.centerIn: parent
            text: BarTipState.text
            color: Theme.cPrimary
            font.family: Config.labelFont
            font.pixelSize: Config.labelFontSize
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
