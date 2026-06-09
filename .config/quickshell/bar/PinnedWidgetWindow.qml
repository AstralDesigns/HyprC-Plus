pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

// Bottom-layer draggable widget shell — sits below normal windows.
//
// Architecture: the PanelWindow spans the full screen and never moves.
// The content Item is positioned with x/y (Qt scene-graph reals), giving
// sub-pixel smooth dragging — no integer-truncation from margins.
//
// Input pass-through: mask is set to only the widget's bounding rect via
// Region { item: body }, so all pointer events outside that rect fall
// through to the bar, desktop icons, and other surfaces beneath.
PanelWindow {
    id: pinWin

    required property bool active
    property string widgetNamespace: "quickshell:widget"
    property real posX: 120
    property real posY: 160

    property real _originX: 0
    property real _originY: 0
    property bool _dragging: false

    signal positionCommitted(real x, real y)

    default property alias content: body.data

    screen: Quickshell.screens.length > 0 ? Quickshell.screens[0] : null

    visible: active && screen !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    aboveWindows: false
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: widgetNamespace

    // Full-screen fixed window — compositor never repositions this surface.
    anchors.left:   true
    anchors.top:    true
    anchors.right:  true
    anchors.bottom: true

    // Restrict pointer input to just the widget rectangle.
    // Everything outside body passes through to the bar and desktop below.
    mask: Region { item: body }

    function _dragBegan() {
        _dragging = true
        _originX  = body.x
        _originY  = body.y
    }

    function _dragMoved(dx, dy) {
        body.x = _originX + dx
        body.y = _originY + dy
    }

    function _dragEnded() {
        _dragging = false
        _clampPos()
        posX = Math.round(body.x)
        posY = Math.round(body.y)
        positionCommitted(posX, posY)
    }

    function _clampPos() {
        if (!screen) return
        const sw = screen.width
        const sh = screen.height
        const w  = body.implicitWidth  > 0 ? body.implicitWidth  : body.childrenRect.width
        const h  = body.implicitHeight > 0 ? body.implicitHeight : body.childrenRect.height
        body.x = Math.max(8, Math.min(body.x, sw - w - 8))
        body.y = Math.max(8, Math.min(body.y, sh - h - 8))
    }

    onActiveChanged: if (active) Qt.callLater(_clampPos)

    component WidgetDrag: DragHandler {
        required property var win
        target: null
        grabPermissions: PointerHandler.CanTakeOverFromAnything
        onActiveChanged: {
            if (active)
                win._dragBegan()
            else
                win._dragEnded()
        }
        onTranslationChanged: win._dragMoved(translation.x, translation.y)
    }

    // Content container — positioned by x/y, drag from any empty space.
    Item {
        id: body
        x: posX
        y: posY
        implicitWidth:  childrenRect.width
        implicitHeight: childrenRect.height

        WidgetDrag { win: pinWin }
    }
}
