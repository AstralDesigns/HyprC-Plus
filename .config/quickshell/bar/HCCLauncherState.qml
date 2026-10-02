pragma Singleton

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  HCCLauncherState.qml — qs app-launcher visibility + tab selection.
//  (Named HCC- prefix to avoid clashing with the existing LauncherState.)
//
//  Honors the GJS tab-select contract (app-launcher.js ~8219): env
//  HYPRCANDY_LAUNCHER_TAB or an explicit open(tab) request beat lastTab; the
//  ${XDG_RUNTIME_DIR}/hyprcandy-launcher-tab file overrides everything and is
//  unlinked after being read. Visibility is applied synchronously — the file
//  read only refines the tab afterwards. Writes the legacy
//  ~/.cache/hyprcandy/launcher.state ("open"/"closed") marker so external
//  autohide contracts keep working.
// ═══════════════════════════════════════════════════════════════════════════

QtObject {
    id: root

    readonly property string _home: StandardPaths.writableLocation(StandardPaths.HomeLocation)
    readonly property string _runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string _tabSelectPath: _runtimeDir + "/hyprcandy-launcher-tab"
    readonly property string _statePath: _home + "/.cache/hyprcandy/launcher.state"

    property bool visible: false
    property string lastTab: "launcher"
    // Tab currently shown; updated synchronously on open, refined once the
    // tab-select file has been read (async).
    property string activeTab: "launcher"

    readonly property var tabs: ["launcher", "clipboard", "emoji", "websearch", "agent"]

    signal opened
    signal closed

    function toggle() { visible ? close() : open("") }

    // tab: "" → honor env/tab-file/lastTab; explicit id → override all but
    // the tab-select file (external requests win, matching GJS).
    function open(tab: string) {
        const envTab = Quickshell.env("HYPRCANDY_LAUNCHER_TAB")
        let t = (tab && tab.length) ? tab
              : (envTab && tabs.indexOf(envTab) !== -1) ? envTab
              : (lastTab || "launcher")
        activeTab = t
        visible = true
        _writeState()
        opened()
        // Async: if a tab-select file exists it wins, then gets unlinked.
        _tabFileView.reload()
    }

    function close() {
        if (!visible) return
        visible = false
        _writeState()
        closed()
    }

    function setTab(tab) {
        if (tabs.indexOf(tab) !== -1) {
            activeTab = tab
            lastTab = tab
        }
    }

    property FileView _tabFileView: FileView {
        path: root._tabSelectPath
        watchChanges: false
        onLoaded: {
            const t = text().trim()
            if (t && root.tabs.indexOf(t) !== -1) root.setTab(t)
            root._unlinkTabFile()
        }
    }

    property Process _unlinkProc: Process {
        command: ["bash", "-c", "rm -f '" + root._tabSelectPath + "'"]
    }
    function _unlinkTabFile() { _unlinkProc.running = true }

    property Process _stateWriter: Process {
        command: ["python3", "-c",
            "import sys,os; os.makedirs(os.path.dirname(sys.argv[1]),exist_ok=True); open(sys.argv[1],'w').write(sys.argv[2])",
            root._statePath, root._stateWriter._content]
        property string _content: "closed"
    }
    function _writeState() {
        _stateWriter._content = visible ? "open\n" : "closed\n"
        _stateWriter.running = true
    }
}
