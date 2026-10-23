pragma Singleton

import QtQuick
import QtCore
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  PackagesIndex.qml — persisted installed-package index for the launcher
//  Packages tab.
//
//  A single scan of the locally-installed set (pkg-query.sh `installed`) is
//  cached at ~/.local/share/hyprcandy/pkg-index.json so the tab has instant
//  first availability and can fuzzy-filter without shelling out on every
//  keystroke. The cache lives in the share root, never ~/.cache (that is a
//  sweep target and would silently wipe the index).
//
//  Lifecycle:
//    • boot  — shell.qml calls ensureStartupScan() once (loads the cache, then
//      refreshes it in the background so anything installed since last boot
//      appears).
//    • write — the scan redirects straight to the file (atomic tmp+mv), then
//      FileView reloads so `installed` republishes to every binding.
//    • fresh — PackagesTab calls rescan() after an install/uninstall/update.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation).toString().replace(/^file:\/\//, "")
    readonly property string indexPath: _home + "/.local/share/hyprcandy/pkg-index.json"

    // Parsed installed records: [{name,version,source,description,repo,installed,icon}]
    property var installed: []
    property bool loaded: false
    property bool scanning: false

    // ── Reader: instant availability + live refresh on external edits ────────
    property FileView _view: FileView {
        path: root.indexPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            root.loaded = true
            try {
                const d = JSON.parse(text())
                root.installed = Array.isArray(d) ? d : []
            } catch (e) {
                root.installed = []
            }
        }
    }

    // ── Background scan → atomic write of the cache file ─────────────────────
    // $0 = index path, $1 = query script. Writes to a .tmp then renames so the
    // watcher never observes a half-written file; reload() is forced on exit.
    property Process _scan: Process {
        command: ["bash", "-c",
                  'd="$(dirname "$0")"; mkdir -p "$d"; '
                  + 'bash "$1" installed > "$0.tmp" 2>/dev/null '
                  + '&& mv -f "$0.tmp" "$0" || rm -f "$0.tmp"',
                  root.indexPath, Config.barDir + "/scripts/pkg-query.sh"]
        onExited: {
            root.scanning = false
            root._view.reload()
        }
    }

    function rescan() {
        if (scanning) return
        scanning = true
        _scan.running = false
        _scan.running = true
    }

    // Called once at boot: surface the persisted list immediately, then refresh.
    function ensureStartupScan() {
        _view.reload()
        rescan()
    }

    Component.onCompleted: _view.reload()
}
