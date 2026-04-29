pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

QtObject {
    id: root

    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string _statePath: root._home + "/.config/desktop-pinned"

    property var apps: []
    property var _classList: []

    // Suppress the FileView re-read that fires after our own write —
    // we already updated _classList in memory, so re-reading is a no-op,
    // but we guard against it anyway to avoid double _resolveApps() calls.
    property var _fileView: FileView {
        path: root._statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const lines = text().split("\n").map(l => l.trim()).filter(l => l.length > 0)
            root._classList = lines
            root._resolveApps()
        }
        Component.onCompleted: reload()
    }

    // Re-resolve whenever DesktopEntries finishes (re-)loading
    property var _entriesReady: Connections {
        target: DesktopEntries.applications
        function onCountChanged() {
            if (DesktopEntries.applications.count > 0 && root._classList.length > 0)
                root._resolveApps()
        }
    }

    // ── Entry lookup ────────────────────────────────────────────────────
    // Quickshell's DesktopEntries.byId() matches only by desktop file ID,
    // not by StartupWMClass. For reverse-DNS class names like "org.cachyos.hello"
    // whose .desktop file is "cachyos-hello.desktop" (last-two-parts joined),
    // we must try several derived ID forms before falling back to a full scan.

    function _findEntry(cls) {
        const parts = cls.split('.')
        const last  = parts[parts.length - 1]
        const last2 = parts.length >= 2
                      ? parts.slice(-2).join('-')
                      : last

        // Ordered from most-specific to cheapest. Duplicates are harmless —
        // byId() is O(1) hash lookup.
        const variants = [
            cls,                                // "org.cachyos.hello"
            cls.toLowerCase(),
            last,                               // "hello"
            last.toLowerCase(),
            last2,                              // "cachyos-hello"
            last2.toLowerCase(),
            cls.replace(/\./g, '-'),            // "org-cachyos-hello"
            cls.replace(/\./g, '-').toLowerCase(),
            // camelCase last part → kebab-case: "KernelManager" → "kernel-manager"
            last.replace(/([A-Z])/g, '-$1').replace(/^-/, '').toLowerCase(),
        ]

        for (const v of variants) {
            const e = DesktopEntries.byId(v)
            if (e) return e
        }

        // Last-resort: linear scan over all installed entries.
        // Matches any entry whose id (without ".desktop") ends with the last
        // dot-segment of the class name, e.g. "hello" in "org.cachyos.hello".
        // Also matches entries whose id equals any of our derived variants.
        const normLast = last.toLowerCase()
        const normLast2 = last2.toLowerCase()
        const total = DesktopEntries.applications.count
        for (let i = 0; i < total; i++) {
            const e = DesktopEntries.applications.get(i)
            if (!e) continue
            const eid = (e.id || "").toLowerCase()
                        .replace(/\.desktop$/, "")
            if (eid === normLast || eid === normLast2
                    || eid.endsWith("-" + normLast)
                    || eid.endsWith("." + normLast)) {
                return e
            }
        }
        return null
    }

    function _resolveApps() {
        if (_classList.length === 0) { apps = []; return }

        const resolved = []
        for (const cls of _classList) {
            const entry = _findEntry(cls)
            // Store desktopId so DesktopLayer can call entry.execute() at
            // launch time — handles DBus activation, Wayland startup protocol,
            // and %u/%f URI substitution correctly for every app type.
            resolved.push(entry ? {
                "class":     cls,
                "name":      entry.name       || cls,
                "icon":      entry.icon       || cls.toLowerCase(),
                "exec":      entry.execString || cls.toLowerCase(),
                "desktopId": entry.id         || "",
            } : {
                "class": cls, "name": cls,
                "icon":  cls.toLowerCase(), "exec": cls.toLowerCase(),
                "desktopId": "",
            })
        }
        apps = resolved
    }

    // ── Write helpers ────────────────────────────────────────────────────

    // Emitted when the class list changes so DesktopLayer can persist it.
    signal saveRequested(var newList)

    // Write newList — update in-memory state immediately, emit signal so
    // DesktopLayer's Process (a direct PanelWindow child) does the disk write.
    function _saveClassList(newList) {
        _classList = newList
        _resolveApps()
        saveRequested(newList)
    }

    // Remove app by class name — called from DesktopLayer context menu
    function removeApp(cls) {
        const newList = _classList.filter(c => c !== cls)
        _saveClassList(newList)
    }

    // Reorder by moving draggedCls to immediately after afterCls.
    // Pass afterCls = "" to move draggedCls to the front.
    function reorderApp(draggedCls, afterCls) {
        let list = _classList.slice()
        const from = list.indexOf(draggedCls)
        if (from === -1) return
        list.splice(from, 1)
        if (afterCls === "") {
            list.unshift(draggedCls)
        } else {
            const toIdx = list.indexOf(afterCls)
            list.splice(toIdx === -1 ? list.length : toIdx + 1, 0, draggedCls)
        }
        _saveClassList(list)
    }

    function forceRefresh() { _fileView.reload() }
}
