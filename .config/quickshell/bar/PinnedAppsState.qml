pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  PinnedAppsState.qml — dock pin order source of truth (~/.config/pinned).
//
//  Same file contract as the GJS dock daemon: one desktop-entry id / WMClass
//  per line, line order == dock icon order. Resolution reuses the exact
//  tiered matcher from DesktopPinnedState (heuristicLookup → byId variants →
//  linear scan). Writes happen in-process (no SIGUSR2 plumbing needed).
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string _pinnedPath: root._home + "/.config/pinned"

    // Raw id list in file order + resolved app records (same shape as
    // DesktopPinnedState.apps: {class,name,icon,exec,desktopId}).
    property var idList: []
    property var orderedApps: []
    readonly property string pinnedOrderKey: root.idList.join("|")

    // True while a self-write is in flight so the FileView echo is ignored.
    property bool _selfWrite: false
    property Timer _selfWriteReset: Timer {
        interval: 400
        repeat: false
        onTriggered: root._selfWrite = false
    }

    property var _fileView: FileView {
        path: root._pinnedPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (root._selfWrite) return
            const lines = text().split("\n").map(l => l.trim()).filter(l => l.length > 0)
            root.idList = lines
            root._resolveApps()
        }
        Component.onCompleted: reload()
    }

    // DesktopEntries may not be populated yet right after qs start.
    property var _entriesPoller: Timer {
        interval: 250
        repeat: true
        running: root.idList.length > 0 && DesktopEntries.applications.count === 0
        property int _attempts: 0
        onTriggered: {
            _attempts++
            if (DesktopEntries.applications.count > 0 || _attempts >= 40)
                stop()
            if (DesktopEntries.applications.count > 0)
                root._resolveApps()
        }
    }

    function _findEntry(id) {
        // Tiered matcher lives in DesktopPinnedState — reuse verbatim so dock,
        // desktop icons and launcher resolve identically.
        return DesktopPinnedState._findEntry(id)
    }

    function _resolveApps() {
        if (root.idList.length === 0) { root.orderedApps = []; return }
        const resolved = []
        for (const id of root.idList) {
            const entry = _findEntry(id)
            resolved.push(entry ? {
                "class":     id,
                "name":      entry.name       || id,
                "icon":      entry.icon       || id.toLowerCase(),
                "exec":      entry.execString || id.toLowerCase(),
                "desktopId": entry.id         || "",
            } : {
                "class": id, "name": id,
                "icon":  id.toLowerCase(), "exec": id.toLowerCase(),
                "desktopId": "",
            })
        }
        root.orderedApps = resolved
    }

    function isPinned(id) { return root.idList.indexOf(id) !== -1 }

    // ── Mutation API ────────────────────────────────────────────────────────

    // Add to the end / remove from the pin list.
    function togglePin(id) {
        if (!id) return
        let list = root.idList.slice()
        const idx = list.indexOf(id)
        if (idx === -1) list.push(id)
        else list.splice(idx, 1)
        _saveIdList(list)
    }

    function pin(id) {
        if (!id || root.idList.indexOf(id) !== -1) return
        const list = root.idList.slice()
        list.push(id)
        _saveIdList(list)
    }

    function unpin(id) {
        const list = root.idList.filter(x => x !== id)
        if (list.length !== root.idList.length) _saveIdList(list)
    }

    // Move draggedId to immediately after afterId ("" → front).
    // Same semantics as DesktopPinnedState.reorderApp.
    function reorder(draggedId, afterId) {
        let list = root.idList.slice()
        const from = list.indexOf(draggedId)
        if (from === -1) return
        list.splice(from, 1)
        if (afterId === "") {
            list.unshift(draggedId)
        } else {
            const toIdx = list.indexOf(afterId)
            list.splice(toIdx === -1 ? list.length : toIdx + 1, 0, draggedId)
        }
        _saveIdList(list)
    }

    // ── Persistence ─────────────────────────────────────────────────────────

    // Same in-process writer recipe as Bar.qml's barStateProc: python3 with
    // content passed via argv (no shell-quoting hazards).
    property Process _writeProc: Process {
        command: ["python3", "-c",
            "import sys; open(sys.argv[1],'w').write(sys.argv[2])",
            root._pinnedPath,
            root._writeProc._content]
        property string _content: ""
    }

    function _saveIdList(list) {
        root._selfWrite = true
        root._selfWriteReset.restart()
        root.idList = list
        root._resolveApps()
        root._writeProc._content = list.join("\n") + (list.length ? "\n" : "")
        root._writeProc.running = true
    }

    function forceRefresh() { root._fileView.reload() }
}
