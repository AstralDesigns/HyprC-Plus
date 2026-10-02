pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  TrashState.qml — trash item count for the dock trash button.
//
//  Exact GJS parity (dock-main.js queries the "trash::item-count" GIO
//  attribute on trash:///). quickshell has no GIO file query, so a tiny
//  PyGObject helper does the identical call. Refreshed on boot, on watchable
//  changes under ~/.local/share/Trash/files, and on demand (dock show,
//  trash click).
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string _filesDir: _home + "/.local/share/Trash/files"
    readonly property string _script: Config.barDir + "/scripts/trash-count.py"

    property int count: 0

    // Glyph thresholds ported from dock-main.js (GLYPH_TRASH_*):
    //   empty 󰩺 U+F0A7A | 1–20 󰩹 U+F0A79 | >20 󰆴 U+F01B4
    readonly property string glyph: count <= 0 ? "\u{F0A7A}"
                              : count <= 20 ? "\u{F0A79}"
                              : "\u{F01B4}"

    function refresh() {
        if (!_countProc.running) _countProc.running = true
    }

    // FileView cannot watch directories ("Not a file"), so the count is kept
    // fresh via the boot read, the low-frequency poll, and on-demand refresh()
    // calls from the dock (show / trash click).
    property Process _countProc: Process {
        command: ["python3", root._script]
        stdout: StdioCollector {
            onStreamFinished: {
                const n = parseInt(this.text.trim(), 10)
                root.count = isNaN(n) ? 0 : Math.max(0, n)
            }
        }
    }

    // Boot read + low-frequency safety net (external volumes etc. don't
    // notify through the local dir). GJS only re-queried on monitor events;
    // the poll is a cheap belt-and-braces at 60 s.
    property Timer _bootTimer: Timer {
        interval: 1200
        repeat: false
        running: true
        onTriggered: root.refresh()
    }
    property Timer _pollTimer: Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }
}
