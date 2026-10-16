pragma Singleton
import QtQuick

// Shared hover-tooltip state for the bar modules. A module calls show(text, item)
// on mouse-enter (passing its text + its own Item as the anchor target) and
// hide(item) on mouse-leave; BarTipWindow.qml renders the floating surface.
// show() accepts an optional third arg `dx` — a horizontal nudge (px) applied to
// the popup, for edge modules (e.g. the start-menu button) that want a side margin.
//
// Reveal feel is tuned to match the dock: the first appearance waits a short
// delay (so a mere sweep across the bar doesn't flash a tooltip), but once one
// is already up, moving to a neighbouring module swaps the text/target almost
// instantly. hide() only closes after a brief grace period, which the next
// show() cancels — so crossing the hairline gap between two modules never
// tears down and rebuilds the popup.
//
// The `item` argument to hide() is what makes left/right-island transitions
// reliable. Those islands are separate surfaces, so the previous module's
// onExited can be delivered AFTER the next module's onEntered has already
// swapped the target. hide(item) ignores any exit whose item is no longer the
// current target, so that trailing exit can't close the freshly-shown tooltip
// — no wall-clock guessing needed.
QtObject {
    id: root

    property bool visible: false
    property string text: ""
    property Item target: null
    property real offsetX: 0        // optional horizontal nudge set by show()'s dx arg

    readonly property int _showDelay: 450   // delay before a cold first show
    readonly property int _hideGrace: 140   // grace before closing after leave

    property Timer _pending: Timer {
        interval: root._showDelay
        onTriggered: root.visible = true
    }

    property Timer _grace: Timer {
        interval: root._hideGrace
        onTriggered: root.visible = false
    }

    function show(t, item, dx) {
        root._grace.stop()          // a neighbour re-entered — don't close
        root.text = t
        root.target = item
        root.offsetX = (dx === undefined ? 0 : dx)   // reset for callers that pass none
        if (root.visible) {
            root._pending.stop()    // already up: swap in place, no delay
        } else {
            root._pending.restart()
        }
    }

    function hide(item) {
        // Stale exit: the tooltip already moved on to a different module, so
        // this leave belongs to the one we swapped away from — ignore it.
        if (item !== undefined && root.target !== item) return
        root._pending.stop()
        root._grace.restart()       // close soon, unless show() cancels it
    }
}
