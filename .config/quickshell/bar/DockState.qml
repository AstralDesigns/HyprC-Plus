pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  DockState.qml — qs dock visibility + position.
//
//  Config.dockPosition is the source of truth; the legacy GJS state files
//  (<candyDir>/GJS/hyprcandydock/dock.pos and dock.state) are mirrored on
//  every change so old tooling keeps working. Index map:
//  0=bottom, 1=right, 2=top, 3=left (identical to cycle.sh/toggle.sh).
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property string _gjsDir: Config.candyDir + "/GJS/hyprcandydock"

    // Boot visible unless the legacy dock.state explicitly says "0"
    // (user intentionally hid the dock last session).
    property bool visible: true
    property bool booted: false

    // Legacy position mirror (read once at boot to seed Config if desired).
    property int _legacyPosIdx: 0

    readonly property var _positions: ["bottom", "right", "top", "left"]

    // Current position — straight proxy onto Config so ControlCenter writes
    // land here without any IPC round-trip.
    property string position: Config.dockPosition
    readonly property bool isVertical: position === "left" || position === "right"

    function toggle() {
        visible = !visible
        _writeState()
    }
    function open()  { if (!visible) { visible = true;  _writeState() } }
    function close() { if (visible)  { visible = false; _writeState() } }

    function setPosition(pos) {
        if (_positions.indexOf(pos) === -1) return
        Config.dockPosition = pos
        _writePos(pos)
    }

    // Cycle like cycle.sh: bottom → right → top → left → bottom
    function cyclePosition() {
        const idx = _positions.indexOf(Config.dockPosition)
        setPosition(_positions[((idx === -1 ? 0 : idx) + 1) % 4])
    }

    // ── Legacy file mirrors ─────────────────────────────────────────────────

    property Process _posWriter: Process {
        command: ["python3", "-c",
            "import sys; open(sys.argv[1],'w').write(sys.argv[2])",
            root._gjsDir + "/dock.pos", root._posWriter._content]
        property string _content: "0"
    }
    property Process _stateWriter: Process {
        command: ["python3", "-c",
            "import sys; open(sys.argv[1],'w').write(sys.argv[2])",
            root._gjsDir + "/dock.state", root._stateWriter._content]
        property string _content: "1"
    }

    function _writePos(pos) {
        _posWriter._content = String(_positions.indexOf(pos)) + "\n"
        _posWriter.running = true
    }
    function _writeState() {
        _stateWriter._content = visible ? "1" : "0"
        _stateWriter.running = true
    }

    // Read dock.state once at boot to honour an explicit "hidden" choice,
    // and keep Config.dockPosition authoritative (seeded from Settings).
    property FileView _legacyStateView: FileView {
        path: root._gjsDir + "/dock.state"
        watchChanges: false
        onLoaded: {
            if (root.booted) return
            root.booted = true
            const t = text().trim()
            if (t === "0") root.visible = false
        }
        Component.onCompleted: reload()
    }
}
