pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  GroupsState.qml — launcher app-groups + favorites.
//
//  Owns the two shared file contracts (byte-compatible with GJS and the
//  DesktopLayer tooling):
//    ~/.config/hyprcandy-launcher-groups    JSON map name -> [class ids],
//                                           2-space pretty format + newline,
//                                           insertion order kept on rename
//    ~/.config/hyprcandy-launcher-favorites newline list of class ids
//  Both files are watched, so writes from other tools reload in place.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string groupsPath: _home + "/.config/hyprcandy-launcher-groups"
    readonly property string favoritesPath: _home + "/.config/hyprcandy-launcher-favorites"

    // groups: plain JS object { name: [ids] } — QML keeps key insertion
    // order for string keys, matching the GJS iteration order.
    property var groups: ({})
    property var favorites: []

    // Debounce guards against our own write echoes.
    property bool _selfWriteGroups: false
    property bool _selfWriteFavs: false
    property Timer _selfWriteReset: Timer {
        interval: 400
        repeat: false
        onTriggered: { root._selfWriteGroups = false; root._selfWriteFavs = false }
    }

    // ── Readers ─────────────────────────────────────────────────────────────

    property FileView _groupsView: FileView {
        path: root.groupsPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (root._selfWriteGroups) return
            try {
                const obj = JSON.parse(text())
                root.groups = (obj && typeof obj === "object") ? obj : {}
            } catch (e) { root.groups = ({}) }
        }
        Component.onCompleted: reload()
    }

    property FileView _favoritesView: FileView {
        path: root.favoritesPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (root._selfWriteFavs) return
            root.favorites = text().split("\n").map(l => l.trim()).filter(l => l.length > 0)
        }
        Component.onCompleted: reload()
    }

    // ── Queries ─────────────────────────────────────────────────────────────

    readonly property var groupNames: Object.keys(groups)

    function groupsForApp(id) {
        const out = []
        for (const name of Object.keys(groups))
            if ((groups[name] || []).indexOf(id) !== -1) out.push(name)
        return out
    }

    function isFavorite(id) { return favorites.indexOf(id) !== -1 }

    // ── Group mutations ─────────────────────────────────────────────────────

    function addGroup(name, ids) {
        name = (name || "").trim()
        if (!name) return
        const g = JSON.parse(JSON.stringify(groups))
        g[name] = (ids || []).slice()
        _writeGroups(g)
    }

    // Rename preserving insertion order and members.
    function renameGroup(oldName, newName) {
        newName = (newName || "").trim()
        if (!newName || !Object.prototype.hasOwnProperty.call(groups, oldName)) return
        if (Object.prototype.hasOwnProperty.call(groups, newName)) return
        const src = groups[oldName] || []
        const out = {}
        for (const k of Object.keys(groups))
            out[k === oldName ? newName : k] = (k === oldName ? src.slice() : groups[k])
        _writeGroups(out)
    }

    function deleteGroup(name) {
        if (!Object.prototype.hasOwnProperty.call(groups, name)) return
        const out = {}
        for (const k of Object.keys(groups))
            if (k !== name) out[k] = groups[k]
        _writeGroups(out)
    }

    function addAppToGroup(name, id) {
        if (!Object.prototype.hasOwnProperty.call(groups, name) || !id) return
        const list = (groups[name] || []).slice()
        if (list.indexOf(id) === -1) list.push(id)
        const g = JSON.parse(JSON.stringify(groups))
        g[name] = list
        _writeGroups(g)
    }

    // Removing the last member deletes the group (GJS parity).
    function removeAppFromGroup(name, id) {
        if (!Object.prototype.hasOwnProperty.call(groups, name)) return
        const list = (groups[name] || []).filter(x => x !== id)
        const out = {}
        for (const k of Object.keys(groups)) {
            if (k === name) { if (list.length > 0) out[k] = list }
            else out[k] = groups[k]
        }
        _writeGroups(out)
    }

    // Toggle membership across every group (launcher menu parity).
    function toggleAppInGroup(name, id) {
        const list = groups[name] || []
        if (list.indexOf(id) === -1) addAppToGroup(name, id)
        else removeAppFromGroup(name, id)
    }

    // ── Favorites ───────────────────────────────────────────────────────────

    function toggleFavorite(id) {
        if (!id) return
        const list = favorites.slice()
        const idx = list.indexOf(id)
        if (idx === -1) list.push(id)
        else list.splice(idx, 1)
        root._selfWriteFavs = true
        root._selfWriteReset.restart()
        root.favorites = list
        _enqueue(root.favoritesPath, list.join("\n") + (list.length ? "\n" : ""))
    }

    // ── Writers ───────────────────────────────────────────────────────────
    // A single shared Process, but SERIALIZED through a queue: group mutations
    // often fire in a loop (multi-select "Add to:" calls addAppToGroup once per
    // id), and re-arming an already-running Process silently drops the write —
    // which is how Steam-game group members never reached the groups file.
    property var _writeQueue: []
    property bool _writeBusy: false

    function _enqueue(path, content) {
        root._writeQueue.push([path, content])
        root._pumpWrites()
    }

    function _pumpWrites() {
        if (root._writeBusy || root._writeQueue.length === 0) return
        const job = root._writeQueue.shift()
        root._writeBusy = true
        _writeFile._path = job[0]
        _writeFile._content = job[1]
        _writeFile.running = true
    }

    function _writeGroups(g) {
        root._selfWriteGroups = true
        root._selfWriteReset.restart()
        root.groups = g
        _enqueue(root.groupsPath, JSON.stringify(g, null, 2) + "\n")
    }

    property Process _writeFile: Process {
        property string _path: ""
        property string _content: ""
        command: ["python3", "-c",
            "import sys; open(sys.argv[1],'w').write(sys.argv[2])",
            _writeFile._path, _writeFile._content]
        onExited: {
            root._writeBusy = false
            root._pumpWrites()
        }
    }
}
