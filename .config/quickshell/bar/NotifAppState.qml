pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  NotifAppState — READ-ONLY singleton.
//  Watches ~/.config/notif-running-apps written by NotificationsState.
//  Provides _findEntry (copied from DesktopPinnedState) and lookup().
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property string _path: StandardPaths.writableLocation(
                                        StandardPaths.HomeLocation) + "/.config/notif-running-apps"

    // Map: lowercased appName → { cls, desktopId, url }
    property var _map: ({})

    property var _fileView: FileView {
        path: root._path
        watchChanges: true
        onFileChanged: root._reload()
        onLoaded:      root._reload()
        Component.onCompleted: reload()
    }

    // Re-resolve unresolved entries when DesktopEntries loads
    property var _entriesConn: Connections {
        target: DesktopEntries.applications
        function onCountChanged() {
            if (DesktopEntries.applications.count > 0 && Object.keys(root._map).length > 0)
                root._reResolve()
        }
    }

    function _reload() {
        try {
            const text = root._fileView.text()
            if (!text) return
            const m = {}
            for (const line of text.split("\n").map(l => l.trim()).filter(l => l)) {
                try {
                    const obj = JSON.parse(line)
                    if (obj && obj.cls) m[obj.cls] = obj
                } catch(_) {}
            }
            root._map = m
        } catch(e) { console.warn("NotifAppState._reload:", e) }
    }

    function _reResolve() {
        const m = Object.assign({}, root._map)
        let changed = false
        for (const cls of Object.keys(m)) {
            if (!m[cls].desktopId) {
                const entry = root._findEntry(cls)
                if (entry) {
                    m[cls] = Object.assign({}, m[cls], { desktopId: entry.id || "" })
                    changed = true
                }
            }
        }
        if (changed) root._map = m
        // No write here — NotificationsState owns writes
    }

    // ── _findEntry — direct copy of DesktopPinnedState._findEntry ───────────
    function _findEntry(cls) {
        const parts = cls.split(".")
        const last  = parts[parts.length - 1]
        const last2 = parts.length >= 2 ? parts.slice(-2).join("-") : last

        const variants = [
            cls, cls.toLowerCase(),
            last, last.toLowerCase(),
            last2, last2.toLowerCase(),
            cls.replace(/\./g, "-"), cls.replace(/\./g, "-").toLowerCase(),
            last.replace(/([A-Z])/g, "-$1").replace(/^-/, "").toLowerCase(),
        ]
        for (const v of variants) {
            const e = DesktopEntries.byId(v)
            if (e) return e
        }

        const normLast  = last.toLowerCase()
        const normLast2 = last2.toLowerCase()
        const total = DesktopEntries.applications.count

        for (let i = 0; i < total; i++) {
            const e   = DesktopEntries.applications.get(i)
            if (!e) continue
            const eid = (e.id || "").toLowerCase().replace(/\.desktop$/, "")
            if (eid === normLast || eid === normLast2
                    || eid.endsWith("-" + normLast)
                    || eid.endsWith("." + normLast)
                    || eid.startsWith(normLast + "-"))
                return e
        }

        for (let i = 0; i < total; i++) {
            const e = DesktopEntries.applications.get(i)
            if (!e || !e.execString) continue
            const bin = e.execString.trim().split(/\s+/)[0].split("/").pop().toLowerCase()
            if (bin === normLast || bin.startsWith(normLast + "-") || bin.endsWith("-" + normLast))
                return e
        }

        // Name-match fallback — handles "Spotify" vs "Spotify (Launcher)" etc.
        const normCls     = cls.toLowerCase()
        const strippedCls = normCls.replace(/\s*\(.*?\)\s*/g, "").trim()
        const clsHasQual  = normCls.includes("(")
        let nameMatch = null, nameRank = 99
        for (let i = 0; i < total; i++) {
            const e        = DesktopEntries.applications.get(i)
            if (!e) continue
            const eName     = (e.name || "").toLowerCase()
            const eStripped = eName.replace(/\s*\(.*?\)\s*/g, "").trim()
            let rank = 99
            if (eName === normCls) rank = 0
            else if (eStripped === strippedCls)
                rank = (clsHasQual === eName.includes("(")) ? 1 : 2
            if (rank < nameRank) { nameRank = rank; nameMatch = e }
            if (nameRank === 0) break
        }
        return nameMatch
    }

    function lookup(appName) {
        if (!appName) return null
        return root._map[appName.toLowerCase()] || null
    }
}
