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

    // Re-resolve once desktop entries become available after startup.
    property var _entriesPoller: Timer {
        interval: 250
        repeat: true
        running: root._classList.length > 0 && DesktopEntries.applications.count === 0
        property int _attempts: 0
        onTriggered: {
            _attempts++
            if (DesktopEntries.applications.count > 0 || _attempts >= 40)
                stop()
            if (DesktopEntries.applications.count > 0)
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
                    || eid.endsWith("." + normLast)
                    || eid.startsWith(normLast + "-")) {
                return e
            }
        }

        // Exec-binary match: cls="spotify" → Exec="spotify-launcher %U".
        // Extract the binary name (first word, strip any path) and apply the
        // same prefix/suffix patterns used above for desktop IDs.  This catches
        // wrapper-launcher desktops where the stored WM class is a prefix of
        // the real launcher binary (StartupWMClass=spotify, Exec=spotify-launcher).
        for (let i = 0; i < total; i++) {
            const e = DesktopEntries.applications.get(i)
            if (!e || !e.execString) continue
            const bin = e.execString.trim().split(/\s+/)[0].split('/').pop().toLowerCase()
            if (bin === normLast
                    || bin.startsWith(normLast + "-")
                    || bin.endsWith("-" + normLast)) {
                return e
            }
        }

        // Name-match fallback: the GJS dock may store the desktop entry Name
        // (e.g. "Spotify (Launcher)") rather than the desktop ID or WM class.
        // Collect ALL name candidates in one pass, ranked by match quality:
        //   rank 0 — exact name match
        //   rank 1 — stripped name matches AND qualifier presence agrees
        //             "Spotify (Launcher)" → prefers entries that also have "("
        //             "Spotify"            → prefers entries that have no "("
        //   rank 2 — stripped name matches regardless of qualifier
        // Pick the lowest rank; ties broken by whichever was seen first.
        const normCls     = cls.toLowerCase()
        const strippedCls = normCls.replace(/\s*\(.*?\)\s*/g, "").trim()
        const clsHasQual  = normCls.includes("(")
        let nameMatch = null
        let nameRank  = 99
        for (let i = 0; i < total; i++) {
            const e = DesktopEntries.applications.get(i)
            if (!e) continue
            const eName     = (e.name || "").toLowerCase()
            const eStripped = eName.replace(/\s*\(.*?\)\s*/g, "").trim()
            let rank = 99
            if (eName === normCls) {
                rank = 0
            } else if (eStripped === strippedCls) {
                rank = (clsHasQual === eName.includes("(")) ? 1 : 2
            }
            if (rank < nameRank) { nameRank = rank; nameMatch = e }
            if (nameRank === 0) break
        }
        return nameMatch
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
