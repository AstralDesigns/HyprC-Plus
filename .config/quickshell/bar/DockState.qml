pragma Singleton

import QtQuick
import QtCore
import Quickshell

// ═══════════════════════════════════════════════════════════════════════════
//  DockState.qml — qs dock visibility + position.
//
//  Everything is backed by Config, which autosaves to
//  ~/.config/hyprcandy/hyprcandy-bar.conf ([qs-bar-config-v1]).
//    position → Config.dockPosition
//    visible  → Config.dockVisible
//  The dock is fully QML now, so the legacy GJS state mirrors
//  (<candyDir>/GJS/hyprcandydock/dock.pos and dock.state) are gone.
//  Index map kept for reference: 0=bottom, 1=right, 2=top, 3=left.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property var _positions: ["bottom", "right", "top", "left"]

    // Current position — straight proxy onto Config so ControlCenter writes
    // land here without any IPC round-trip.
    property string position: Config.dockPosition
    readonly property bool isVertical: position === "left" || position === "right"

    // Shown / user-hidden, persisted via Config.dockVisible.
    readonly property bool visible: Config.dockVisible

    function toggle() { Config.dockVisible = !Config.dockVisible }
    function open()   { if (!Config.dockVisible) Config.dockVisible = true }
    function close()  { if ( Config.dockVisible) Config.dockVisible = false }

    function setPosition(pos) {
        if (_positions.indexOf(pos) === -1) return
        Config.dockPosition = pos
    }

    // Cycle bottom → right → top → left → bottom
    function cyclePosition() {
        const idx = _positions.indexOf(Config.dockPosition)
        setPosition(_positions[((idx === -1 ? 0 : idx) + 1) % 4])
    }
}
