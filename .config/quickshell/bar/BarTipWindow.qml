import QtQuick
import Quickshell
import Quickshell.Widgets

// Floating hover tooltip for the bar modules (driven by BarTipState). Rendered
// as its own PopupWindow anchored to the hovered module's own window via
// mapFromItem — mirroring Quickshell's built-in Tooltip — so it escapes the
// thin island surfaces it would otherwise be clipped by and follows the module
// across islands/monitors. Multi-line text stacks one action per line.
PopupWindow {
    id: popup
    color: "transparent"
    visible: BarTipState.visible

    readonly property Item anchorItem: BarTipState.target
    readonly property bool _below: Config.barPosition !== "bottom"

    implicitWidth: box.implicitWidth
    implicitHeight: box.implicitHeight

    anchor {
        window: anchorItem ? anchorItem.QsWindow.window : null
        adjustment: PopupAdjustment.None
        gravity: Edges.Bottom | Edges.Right

        onAnchoring: {
            if (!anchorItem) return
            const gx = anchorItem.width / 2 - popup.width / 2
            const gy = popup._below ? anchorItem.height + 6 : -(popup.height + 6)
            const pos = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, gx, gy)
            anchor.rect.x = pos.x
            anchor.rect.y = pos.y
        }
    }

    Rectangle {
        id: box
        radius: 7
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
