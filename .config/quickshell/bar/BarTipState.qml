pragma Singleton
import QtQuick

// Shared hover-tooltip state for the bar modules. A module calls show() on
// mouse-enter (passing its text + its own Item as the anchor target) and hide()
// on mouse-leave; BarTipWindow.qml renders the floating surface. The short
// delay avoids flashing while the pointer sweeps across the bar.
QtObject {
    id: root

    property bool visible: false
    property string text: ""
    property Item target: null

    property Timer _pending: Timer {
        interval: 450
        onTriggered: root.visible = true
    }

    function show(t, item) {
        root.text = t
        root.target = item
        root._pending.restart()
    }

    function hide() {
        root._pending.stop()
        root.visible = false
    }
}
