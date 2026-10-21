pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  WebBookmarksState.qml — launcher web-search bookmarks.
//
//  Store: ~/.local/share/hyprcandy/launcher_web_state.json
//    { "searxBookmarks": [ { "url":…, "title":…, "added":… }, … ], … }
//
//  Bookmarks used to live in ~/.cache/hyprcandy/launcher_web_state.json (the
//  GJS launcher web-state file). Cache dirs are legitimately swept by every
//  browser-data / cleanup action -- that's how "clear cookies to reset
//  YouTube's adblock flag" also destroyed bookmarks -- so user data moves to
//  the share root next to websearch-startup-state.json. The legacy file is
//  copied up whenever it is newer than the store, and left in place for the
//  retired GJS phase.
//
//  Only the `searxBookmarks` key is owned here; every other key (open tabs,
//  active tab, …) is loaded, kept verbatim and re-emitted so the browser
//  phase can share the same file without clobbering bookmarks. The file is
//  watched, so edits from tooling reload in place.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    // Strip the file:// scheme StandardPaths returns in Qt6 so the python3
    // writer targets the real ~/.local/share/hyprcandy state file.
    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")
    readonly property string statePath: _home + "/.local/share/hyprcandy/launcher_web_state.json"
    readonly property string _legacyPath: _home + "/.cache/hyprcandy/launcher_web_state.json"

    // Full parsed state object — other keys are preserved across writes.
    property var _state: ({})
    // Bookmarks: array of { url, title, added }.
    property var bookmarks: []
    // Bumped on every change so view bindings that call isBookmarked() re-evaluate.
    property int version: 0

    // Debounce guard against our own write echo.
    property bool _selfWrite: false
    property Timer _selfWriteReset: Timer {
        interval: 400
        repeat: false
        onTriggered: root._selfWrite = false
    }

    // ── Migration from the old cache location ────────────────────────
    // Copy when the legacy file is NEWER than the store (first run, or the
    // still-running old singleton wrote a bookmark to the cache path after
    // the store was seeded). Once this build is live nothing writes to the
    // cache copy again, so a stale legacy file can never clobber the store.
    property Process _migrate: Process {
        command: ["python3", "-c",
            "import os,shutil,sys\n" +
            "old,new=sys.argv[1],sys.argv[2]\n" +
            "os.makedirs(os.path.dirname(new),exist_ok=True)\n" +
            "if os.path.exists(old) and (not os.path.exists(new)\n" +
            "    or os.path.getmtime(old) > os.path.getmtime(new)):\n" +
            "    shutil.copy2(old,new)",
            root._legacyPath, root.statePath]
        onExited: root._view.reload()
    }
    Component.onCompleted: root._migrate.running = true

    // ── Reader ──────────────────────────────────────────────────────────────
    property FileView _view: FileView {
        path: root.statePath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            if (root._selfWrite) return
            root._loadFromText(text())
        }
    }

    function _loadFromText(t) {
        let obj = {}
        try { const p = JSON.parse(t); if (p && typeof p === "object") obj = p } catch (e) { obj = {} }
        root._state = obj
        root.bookmarks = Array.isArray(obj.searxBookmarks) ? obj.searxBookmarks : []
        root.version++
    }

    // ── Queries ───────────────────────────────────────────────────────────────
    function _clean(url) { return String(url ?? "").split("#")[0] }

    function indexOfUrl(url) {
        const c = _clean(url)
        for (let i = 0; i < bookmarks.length; i++)
            if (_clean(bookmarks[i].url) === c) return i
        return -1
    }
    function isBookmarked(url) { return indexOfUrl(url) !== -1 }

    // ── Mutations ───────────────────────────────────────────────────────────
    function add(url, title) {
        const c = _clean(url)
        if (c === "" || isBookmarked(c)) return
        const list = bookmarks.slice()
        list.push({ url: c, title: (title || c).trim(), added: Date.now() })
        root.bookmarks = list
        _persist()
    }

    function remove(url) {
        const c = _clean(url)
        const list = bookmarks.filter(b => _clean(b.url) !== c)
        if (list.length === bookmarks.length) return
        root.bookmarks = list
        _persist()
    }

    function toggle(url, title) {
        if (isBookmarked(url)) remove(url)
        else add(url, title)
    }

    function clear() {
        if (bookmarks.length === 0) return
        root.bookmarks = []
        _persist()
    }

    // ── Writer (preserves non-bookmark keys) ──────────────────────────────────
    function _persist() {
        root.version++
        root._selfWrite = true
        root._selfWriteReset.restart()
        const s = (_state && typeof _state === "object") ? _state : {}
        s.searxBookmarks = bookmarks
        root._state = s
        _writeFile._path = root.statePath
        _writeFile._content = JSON.stringify(s, null, 2) + "\n"
        _writeFile.running = true
    }

    property Process _writeFile: Process {
        property string _path: ""
        property string _content: ""
        command: ["python3", "-c",
            "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
            _writeFile._path, _writeFile._content]
    }
}
