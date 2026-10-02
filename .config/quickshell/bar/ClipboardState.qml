pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  ClipboardState.qml — cliphist-backed clipboard history for the launcher.
//
//  Parity with GJS app-launcher.js clipboard tab: "cliphist list" lines are
//  "INDEX\tCONTENT" (cliphist escapes newlines inside CONTENT), max 80 rows,
//  restore pipes the full line through "cliphist decode | wl-copy", clear is
//  "cliphist wipe". Refresh happens on tab open only (GJS behavior).
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    // entries: [{ index, raw, text }] — raw is the untouched list line.
    property var entries: []
    property bool loading: false
    property bool failed: false

    readonly property int maxEntries: 80

    function refresh() {
        loading = true
        failed = false
        if (!_listProc.running) _listProc.running = true
    }

    function clear() {
        entries = []
        _wipeProc.running = true
    }

    // Restore one history entry to the clipboard (then close the launcher).
    function restore(rawLine) {
        _decodeProc._line = rawLine
        _decodeProc.running = true
    }

    function _parse(text) {
        const out = []
        const lines = text.split("\n")
        for (const line of lines) {
            if (!line) continue
            const tab = line.indexOf("\t")
            if (tab === -1) continue
            const idx = parseInt(line.substring(0, tab), 10)
            let content = line.substring(tab + 1)
            out.push({
                "index": idx,
                "raw":   line,
                "text":  content.length > 120
                    ? content.substring(0, 120) + "…"
                    : content,
            })
            if (out.length >= maxEntries) break
        }
        entries = out
        loading = false
    }

    property Process _listProc: Process {
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                root._parse(this.text)
                if (this.text.trim().length === 0 && root.entries.length === 0)
                    root.failed = false // empty history is valid, not a failure
            }
        }
        onExited: function(exitCode) {
            if (exitCode !== 0) { root.failed = true; root.loading = false }
        }
    }

    property Process _wipeProc: Process {
        command: ["cliphist", "wipe"]
    }

    // Feed the raw list line to cliphist decode through wl-copy. The line
    // travels via argv ($0 of the sh -c script) — no quoting hazards, no
    // stdin-close ordering to fight with.
    property Process _decodeProc: Process {
        property string _line: ""
        command: ["sh", "-c",
            "printf %s \"$0\" | cliphist decode | wl-copy",
            _decodeProc._line]
    }
}
