// ~/.config/quickshell/wallpaper/shell.qml
// Quickshell wallpaper picker — launch with: qs -c wallpaper
//
// Keybinds:  ←/→/↑/↓  navigate   Enter  apply   Esc  close
// Mouse:     click to apply   scroll to navigate   click backdrop to close

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.settings 1.1

ShellRoot {
    id: root

    // ── Matugen colors ──────────────────────────────────────────────────────────
    // FileView watches ~/.cache/quickshell/wallpaper/MatugenColors.qml (outside
    // the QS config dir) so matugen rewrites never trigger a hot-reload.
    // onTextChanged fires live whenever the file changes → instant color update.
    property string _m3primary:                 ""
    property string _m3onPrimary:               ""
    property string _m3onSecondary:             ""
    property string _m3secondaryContainer:      ""
    property string _m3onSecondaryContainer:    ""
    property string _m3background:              ""
    property string _m3surfaceContainer:        ""
    property string _m3surfaceContainerHigh:    ""
    property string _m3onSurface:               ""
    property string _m3onSurfaceVariant:        ""
    property string _m3outline:                 ""
    property string _m3outlineVariant:          ""

    // Derived semantic colors
    readonly property color cBg:        Qt.color(_m3background)
    readonly property color cSurfHi:    Qt.color(_m3surfaceContainer)
    readonly property color cSurfHiHi:  Qt.color(_m3surfaceContainerHigh)
    readonly property color cOnSurface: Qt.color(_m3onSurface)
    readonly property color cOnSurfVar: Qt.color(_m3onSurfaceVariant)
    readonly property color cPrimary:   Qt.color(_m3primary)
    readonly property color cOnPrimary: Qt.color(_m3onPrimary)
    readonly property color cSecCont:   Qt.color(_m3secondaryContainer)
    readonly property color cOnSecCont: Qt.color(_m3onSecondaryContainer)
    readonly property color cOutline:   Qt.color(_m3outline)
    readonly property color cOutlineVar:Qt.color(_m3outlineVariant)
    readonly property color cPanelBg: Qt.rgba(
        Qt.color(_m3onSecondary).r,
        Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.4)
    readonly property color cScrim: Qt.rgba(
        Qt.color(_m3onSecondary).r,
        Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.55)

    function parseColors(text) {
        const re = /property color (\w+): "(#[0-9a-fA-F]+)"/g
        let m
        while ((m = re.exec(text)) !== null) {
            const key = m[1], val = m[2]
            switch (key) {
                case "m3primary":             root._m3primary = val; break
                case "m3onPrimary":           root._m3onPrimary = val; break
                case "m3onSecondary":         root._m3onSecondary = val; break
                case "m3secondaryContainer":  root._m3secondaryContainer = val; break
                case "m3onSecondaryContainer":root._m3onSecondaryContainer = val; break
                case "m3background":          root._m3background = val; break
                case "m3surfaceContainer":    root._m3surfaceContainer = val; break
                case "m3surfaceContainerHigh":root._m3surfaceContainerHigh = val; break
                case "m3onSurface":           root._m3onSurface = val; break
                case "m3onSurfaceVariant":    root._m3onSurfaceVariant = val; break
                case "m3outline":             root._m3outline = val; break
                case "m3outlineVariant":      root._m3outlineVariant = val; break
            }
        }
    }

    FileView {
        id: colorFile
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) +
              "/quickshell/wallpaper/MatugenColors.qml"
        watchChanges: true
        onFileChanged: reload()          // re-read when matugen rewrites the file
        onLoaded: root.parseColors(text()) // text() is a function; fires on initial load + after reload()
    }

    // ── Rounding (mirrors Appearance.qml) ────────────────────────────────────
    readonly property int rSm:   12
    readonly property int rLg:   23
    readonly property int rFull: 9999

    // ── App state ─────────────────────────────────────────────────────────────
    property string wallpaperDir:    appSettings.wallpaperDir
    property string currentWallpaper:""
    property string searchText:      ""
    property int    focusedIdx:      0
    property var    allWallpapers:   []
    property var    filtered:        []
    property bool   sidebarOpen:     false

    // ── Sidebar directory browsing state ─────────────────────────────────────
    property string sidebarPath:     appSettings.wallpaperDir !== ""
                                         ? _parentOf(appSettings.wallpaperDir)
                                         : (Quickshell.env("HOME") + "/Pictures")
    property var    sidebarDirs:     []

    function _parentOf(p) {
        if (!p) return Quickshell.env("HOME")
        const s = p.endsWith("/") ? p.slice(0, -1) : p
        const idx = s.lastIndexOf("/")
        return idx > 0 ? s.substring(0, idx) : "/"
    }

    // ── Settings persistence ──────────────────────────────────────────────────
    Settings {
        id: appSettings
        category: "wp-picker-v3"
        property string wallpaperDir:   ""
        property string sortMode:       "name"
        property string subfoldersMode: "All"
        property string fillMode:       "crop"
        property string transType:      "any"
        property string transAngle:     "0"
        property string transDuration:  "2"
        property string transStep:      "90"
        property string transFps:       "60"
    }

    property string sortMode:       appSettings.sortMode
    property string subfoldersMode: appSettings.subfoldersMode
    property string fillMode:       appSettings.fillMode
    property string transType:      appSettings.transType
    property string transAngle:     appSettings.transAngle
    property string transDuration:  appSettings.transDuration
    property string transStep:      appSettings.transStep
    property string transFps:       appSettings.transFps

    // ── File scanning ─────────────────────────────────────────────────────────
    Component.onCompleted: { if (wallpaperDir) scanDir() }
    onWallpaperDirChanged:  { if (wallpaperDir) scanDir() }
    onSearchTextChanged:    applyFilter()
    onSortModeChanged:      sortAndFilter()

    function scanDir() {
        scanProc._buf = []
        if (scanProc.running) scanProc.running = false
        Qt.callLater(function() { scanProc.running = true })
    }

    function sortAndFilter() {
        if (sortMode === "random") {
            var arr = allWallpapers.slice()
            for (var i = arr.length - 1; i > 0; i--) {
                var j = Math.floor(Math.random() * (i + 1))
                var tmp = arr[i]; arr[i] = arr[j]; arr[j] = tmp
            }
            allWallpapers = arr
        } else {
            allWallpapers = allWallpapers.slice().sort(function(a, b) {
                return a.split('/').pop().localeCompare(
                    b.split('/').pop(), undefined, { sensitivity: 'base' })
            })
        }
        applyFilter()
    }

    function applyFilter() {
        const q = searchText.trim().toLowerCase()
        filtered = q
            ? allWallpapers.filter(function(p) {
                  return p.split('/').pop().toLowerCase().includes(q)
              })
            : allWallpapers.slice()
        if (focusedIdx >= filtered.length)
            focusedIdx = Math.max(0, filtered.length - 1)
        // After any filter update (scan, search, sort) ensure the thumb pipeline
        // is draining. GridView may recycle existing delegates rather than
        // recreating them, so Component.onCompleted doesn't always re-fire.
        Qt.callLater(root._thumbDrain)
    }

    Process {
        id: scanProc
        property var _buf: []
        command: root.wallpaperDir ? [
            "bash", "-c",
            "find \"$1\" " +
            (root.subfoldersMode === "All" ? "" : "-maxdepth 1 ") +
            "-type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' " +
            "-o -iname '*.webp' -o -iname '*.gif' -o -iname '*.bmp' \\) -print",
            "--", root.wallpaperDir
        ] : ["bash", "-c", "exit 0"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (t) scanProc._buf.push(t)
            }
        }
        onRunningChanged: if (running) _buf = []
        onExited: function() {
            root.allWallpapers = _buf.slice().sort(function(a, b) {
                return a.split('/').pop().localeCompare(
                    b.split('/').pop(), undefined, { sensitivity: 'base' })
            })
            if (root.sortMode === "random") root.sortAndFilter()
            else root.applyFilter()
        }
    }

    // ── Sidebar directory listing ─────────────────────────────────────────────
    function scanSidebarDirs(path) {
        sidebarProc._buf = []
        sidebarProc._path = path
        if (sidebarProc.running) sidebarProc.running = false
        Qt.callLater(function() { sidebarProc.running = true })
    }

    onSidebarOpenChanged: {
        if (sidebarOpen) scanSidebarDirs(root.sidebarPath)
    }

    Process {
        id: sidebarProc
        property var    _buf:  []
        property string _path: ""
        command: _path ? [
            "bash", "-c",
            "find \"$1\" -maxdepth 1 -mindepth 1 -type d -not -name '.*' -print | sort",
            "--", _path
        ] : ["bash", "-c", "exit 0"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (t) sidebarProc._buf.push(t)
            }
        }
        onRunningChanged: if (running) _buf = []
        onExited: function() {
            root.sidebarDirs = _buf.slice()
        }
    }

    // ── Wallpaper application ─────────────────────────────────────────────────
    // Delegates to wallpaper-apply.sh (same directory as this QML file).
    // Using a script avoids all inline-bash quoting pitfalls and makes the
    // apply step independently testable / loggable.
    function applyWallpaper(path) {
        if (!path) return
        root.currentWallpaper = path
        // Never kill a running process — just let the script run to completion.
        // awww img is fast (sends IPC message then exits), so queuing isn't needed.
        if (!awwwProc.running) {
            awwwProc._path = path
            awwwProc.running = true
        }
        // If already running (rare: prev transition still active), the onExited
        // handler will pick up _pendingPath and launch immediately after.
        else {
            awwwProc._pendingPath = path
        }
    }

    Process {
        id: awwwProc
        property string _path: ""
        property string _pendingPath: ""

        command: _path ? [
            "bash", "-c",
            "exec \"${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/wallpaper/wallpaper-apply.sh\" \"$@\"",
            "--",
            _path,
            root.transType,
            root.transStep,
            root.transAngle,
            root.transDuration,
            root.transFps,
            root.fillMode
        ] : ["bash", "-c", "exit 0"]

        onExited: function(exitCode) {
            const next = _pendingPath
            _path = ""
            _pendingPath = ""
            if (next) {
                _path = next
                running = true
            }
        }
    }

    // ── Navigation ────────────────────────────────────────────────────────────
    function moveFocus(delta) {
        const n = filtered.length
        if (!n) return
        focusedIdx = Math.max(0, Math.min(n - 1, focusedIdx + delta))
        gridView.positionViewAtIndex(focusedIdx, GridView.Contain)
    }

    // ── Quit helper ──────────────────────────────────────────────────────────
    // Stops background work then exits the process so no zombie qs -c wallpaper
    // remains after the user closes the picker via backdrop click or Escape.
    function _quit() {
        if (scanProc.running)    scanProc.running = false
        if (sidebarProc.running) sidebarProc.running = false
        root._thumbQueue   = []
        root._thumbCurrent = ""
        Qt.quit()
    }

    // ── Rounded-thumbnail pipeline (ImageMagick → 160×100 rounded-rect PNG) ──
    // Thumbnails are cached permanently in ~/.local/share/quickshell/wp-thumbs/
    // so they survive reboots. The Refresh button wipes that dir and regenerates.
    // A single sequential Process avoids spawning hundreds of magick instances.
    // Delegates request via thumbRequest(); they receive the result via thumbReady().

    signal thumbReady(string origPath, string thumbSrc)

    // Permanent per-user cache — survives reboots, only cleared by Refresh button.
    readonly property string _thumbDir:
        (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) +
        "/quickshell/wp-thumbs"

    property var    _thumbQueue:   []
    property string _thumbCurrent: ""   // path currently being processed by thumbProc
    property bool   _thumbRunning: false

    // djb2 hash of path → deterministic 8-hex cache filename, no shell escaping needed
    function _pathHash(p) {
        let h = 5381
        for (let i = 0; i < p.length; i++)
            h = ((h << 5) + h + p.charCodeAt(i)) >>> 0
        return ('00000000' + h.toString(16)).slice(-8)
    }

    function thumbRequest(path) {
        if (!path) return
        // Skip if this path is already being processed or is already in the queue
        if (root._thumbCurrent === path) return
        if (root._thumbQueue.indexOf(path) >= 0) return
        root._thumbQueue.push(path)
        _thumbDrain()
    }

    function _thumbDrain() {
        if (root._thumbRunning || root._thumbQueue.length === 0) return
        const path  = root._thumbQueue.shift()
        const hash  = root._pathHash(path)
        const dir   = root._thumbDir
        const dst   = dir + "/" + hash + ".png"
        // Single-quote-escape both paths for bash
        const safe  = path.replace(/'/g, "'\\''")
        const safed = dst.replace(/'/g, "'\\''")
        const safeDir = dir.replace(/'/g, "'\\''")
        // For animated GIFs append [0] so magick only decodes the first frame —
        // processing all frames is ~10–100× slower and returns no rounded result.
        const isGif  = path.toLowerCase().endsWith(".gif")
        const srcArg = isGif ? ("'" + safe + "'[0]") : ("'" + safe + "'")
        root._thumbRunning  = true
        root._thumbCurrent  = path
        thumbProc._origPath = path
        thumbProc._dst      = dst
        // If cached file already exists, just echo and exit — no re-processing
        thumbProc._cmd =
            "mkdir -p '" + safeDir + "'; " +
            "[ -f '" + safed + "' ] && { echo ok; exit 0; }; " +
            "magick " + srcArg + " " +
            "-resize 160x100^ -gravity center -extent 160x100 " +
            "\\( +clone -alpha extract " +
            "   -fill black -colorize 100 " +
            "   -fill white -draw 'roundrectangle 0,0 159,99 20,20' \\) " +
            "-alpha off -compose CopyOpacity -composite " +
            "-strip '" + safed + "' 2>/dev/null && echo ok"
        thumbProc.running = true
    }

    Process {
        id: thumbProc
        property string _origPath: ""
        property string _dst:      ""
        property string _cmd:      "true"
        command: ["bash", "-c", thumbProc._cmd]
        onExited: function(code) {
            root._thumbCurrent = ""   // clear before draining so next item can start
            if (code === 0)
                // Append timestamp so QML Image sees a new URL even if file was replaced
                root.thumbReady(thumbProc._origPath,
                                "file://" + thumbProc._dst + "?" + Date.now())
            root._thumbRunning = false
            root._thumbDrain()
        }
    }

    // Hard-refresh: wipe the permanent on-disk thumb cache then re-scan so
    // every thumbnail is regenerated from scratch. Triggered by the refresh button.
    Process {
        id: thumbCacheClearProc
        command: ["bash", "-c",
            "rm -rf \"${XDG_DATA_HOME:-$HOME/.local/share}/quickshell/wp-thumbs\""]
        onExited: {
            root._thumbQueue   = []
            root._thumbCurrent = ""
            root._thumbRunning = false
            root.scanDir()
        }
    }

    // ── Window ────────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: true
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.namespace: "quickshell:wallpaper"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        color: "transparent"

        // Clip mask to panel only → no shadow on transparent fullscreen area
        mask: Region { item: panel }

        Item {
            anchors.fill: parent

            // ── Click-to-close backdrop (transparent — no full-screen tint) ──────
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    if (root.sidebarOpen) root.sidebarOpen = false
                    else root._quit()
                }
            }

            // ── Main panel ────────────────────────────────────────────────────
            Rectangle {
                id: panel
                anchors.centerIn: parent
                width:  Math.min(parent.width  - 80, 1380)
                height: Math.min(parent.height - 80, 880)
                radius: root.rLg
                // Same colOverviewBg transparent style as the overview
                color:  root.cPanelBg
                clip:   false

                // Border
                Rectangle {
                    anchors.fill: parent
                    radius:       root.rLg
                    color:        "transparent"
                    border.color: Qt.rgba(
                        root.cOutlineVar.r, root.cOutlineVar.g, root.cOutlineVar.b, 0.55)
                    border.width: 1
                    z: 99
                }

                MouseArea { anchors.fill: parent } // prevent scrim click-through

                // ── Sidebar overlay (left-slide) ──────────────────────────────
                Rectangle {
                    id: sidebar
                    anchors {
                        top:    parent.top
                        bottom: parent.bottom
                        left:   parent.left
                    }
                    width:   root.sidebarOpen ? 280 : 0
                    radius:  root.rLg
                    // right corners squared off when open
                    // clip so content doesn't overflow during animation
                    clip:    true
                    color:   Qt.rgba(root.cBg.r, root.cBg.g, root.cBg.b, 0.97)
                    z:       20

                    Behavior on width {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 6
                        visible: root.sidebarOpen

                        // Current path display
                        Rectangle {
                            Layout.fillWidth: true
                            height: 36
                            radius: root.rSm
                            color: Qt.rgba(root.cSurfHiHi.r, root.cSurfHiHi.g, root.cSurfHiHi.b, 0.6)

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 8
                                spacing: 6

                                // Up button
                                Text {
                                    text: "󰁞"
                                    color: root.cPrimary
                                    font.pixelSize: 16
                                    font.family: "Symbols Nerd Font Mono"
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.sidebarPath = root._parentOf(root.sidebarPath)
                                            root.scanSidebarDirs(root.sidebarPath)
                                        }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: root.sidebarPath.replace(Quickshell.env("HOME"), "~")
                                    color: root.cOnSurfVar
                                    font.pixelSize: 11
                                    elide: Text.ElideLeft
                                }
                            }
                        }

                        // Directory list
                        ScrollView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                            ListView {
                                id: dirList
                                model: root.sidebarDirs

                                // Loading spinner
                                Item {
                                    anchors.fill: parent
                                    visible: sidebarProc.running
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰑪"
                                        color: root.cOutlineVar
                                        font.pixelSize: 28
                                        font.family: "Symbols Nerd Font Mono"
                                        RotationAnimator on rotation {
                                            from: 0; to: 360
                                            duration: 1000
                                            loops: Animation.Infinite
                                            running: sidebarProc.running
                                        }
                                    }
                                }

                                delegate: Item {
                                    id: dirEntry
                                    required property string modelData
                                    required property int    index
                                    width: dirList.width
                                    height: 36

                                    readonly property string dirName: modelData.split('/').pop()
                                    readonly property bool   isSelected: modelData === root.wallpaperDir

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: 2
                                        radius: root.rSm
                                        color: dirEntry.isSelected
                                            ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.18)
                                            : (dirHov.containsMouse ? root.cSurfHiHi : root.cSecCont)
                                        Behavior on color { ColorAnimation { duration: 100 } }

                                        // Click anywhere on the row → navigate into subfolder
                                        MouseArea {
                                            id: dirHov
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.sidebarPath = dirEntry.modelData
                                                root.scanSidebarDirs(dirEntry.modelData)
                                            }
                                        }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 6
                                            spacing: 8

                                            Text {
                                                text: "󰉋"
                                                color: dirEntry.isSelected ? root.cPrimary : root.cOnSecCont
                                                font.pixelSize: 14
                                                font.family: "Symbols Nerd Font Mono"
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: dirEntry.dirName
                                                color: dirEntry.isSelected ? root.cPrimary : root.cOnSurface
                                                font.pixelSize: 13
                                                elide: Text.ElideRight
                                            }
                                            // Expand arrow (navigate into subfolder)
                                            Text {
                                                text: "󰁔"
                                                color: root.cOutlineVar
                                                font.pixelSize: 12
                                                font.family: "Symbols Nerd Font Mono"
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Empty state
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            visible: !sidebarProc.running && root.sidebarDirs.length === 0
                            text: "No subdirectories"
                            color: root.cOutline
                            font.pixelSize: 12
                        }

                        // ── "Use this folder" button ──────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            height: 32
                            radius: root.rSm
                            color: useFolderHov.containsMouse
                                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.25)
                                : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.12)
                            Behavior on color { ColorAnimation { duration: 100 } }

                            Text {
                                anchors.centerIn: parent
                                text: "Use this folder"
                                color: root.cPrimary
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }

                            MouseArea {
                                id: useFolderHov
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.wallpaperDir = root.sidebarPath
                                    appSettings.wallpaperDir = root.sidebarPath
                                    root.sidebarOpen = false
                                }
                            }
                        }
                    }
                }

                // ── Main content — fills whole panel width, left margin animates
                Item {
                    anchors.fill: parent

                    // Animated left margin so content slides without resizing the outer item
                    property real contentLeft: root.sidebarOpen ? sidebar.width : 0
                    Behavior on contentLeft {
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    ColumnLayout {
                        anchors {
                            top:         parent.top
                            bottom:      parent.bottom
                            right:       parent.right
                            left:        parent.left
                            leftMargin:  parent.contentLeft + 20
                            topMargin:   20
                            bottomMargin:20
                            rightMargin: 20
                        }
                        spacing: 10

                        // ── Header row ────────────────────────────────────────
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 10

                            // Folder / sidebar toggle button
                            Rectangle {
                                width: 120; height: 34
                                radius: root.rFull
                                color: root.sidebarOpen
                                    ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.18)
                                    : (fldHov.containsMouse ? root.cSurfHiHi : root.cSecCont)
                                border.color: root.sidebarOpen ? root.cPrimary : "transparent"
                                border.width: root.sidebarOpen ? 1 : 0
                                Behavior on color { ColorAnimation { duration: 130 } }

                                MouseArea {
                                    id: fldHov
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.sidebarOpen = !root.sidebarOpen
                                    }
                                }

                                RowLayout {
                                    anchors.centerIn: parent
                                    spacing: 6
                                    Text {
                                        text: "󰉋"
                                        color: root.sidebarOpen ? root.cPrimary : root.cOnSecCont
                                        font.pixelSize: 14
                                        font.family: "Symbols Nerd Font Mono"
                                    }
                                    Text {
                                        text: "Folder"
                                        color: root.sidebarOpen ? root.cPrimary : root.cOnSecCont
                                        font.pixelSize: 13
                                        font.weight: Font.Medium
                                    }
                                }
                            }

                            // Search bar
                            Rectangle {
                                Layout.fillWidth: true
                                height: 34
                                radius: root.rFull
                                color: Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                                border.color: searchIn.activeFocus ? root.cPrimary : root.cOutlineVar
                                border.width: searchIn.activeFocus ? 2 : 1
                                Behavior on border.color { ColorAnimation { duration: 180 } }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 14
                                    anchors.rightMargin: 10
                                    spacing: 8

                                    Text {
                                        text: "󰍉"
                                        color: searchIn.activeFocus ? root.cPrimary : root.cOutline
                                        font.pixelSize: 15
                                        font.family: "Symbols Nerd Font Mono"
                                        Behavior on color { ColorAnimation { duration: 180 } }
                                    }

                                    TextInput {
                                        id: searchIn
                                        Layout.fillWidth: true
                                        color: root.cOnSurface
                                        font.pixelSize: 14
                                        verticalAlignment: TextInput.AlignVCenter
                                        selectionColor: Qt.rgba(
                                            root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.35)
                                        selectedTextColor: root.cOnSurface

                                        Text {
                                            anchors.fill: parent
                                            text: "Search wallpapers…"
                                            color: root.cOutline
                                            font: parent.font
                                            visible: !parent.text
                                            verticalAlignment: Text.AlignVCenter
                                        }

                                        onTextChanged: root.searchText = text
                                        Component.onCompleted: forceActiveFocus()
                                        Keys.onEscapePressed: {
                                            if (root.sidebarOpen) root.sidebarOpen = false
                                            else root._quit()
                                        }
                                        Keys.onUpPressed:    function(e) { root.moveFocus(-gridView.cols); e.accepted = true }
                                        Keys.onDownPressed:  function(e) { root.moveFocus(+gridView.cols); e.accepted = true }
                                        Keys.onLeftPressed:  function(e) { root.moveFocus(-1); e.accepted = true }
                                        Keys.onRightPressed: function(e) { root.moveFocus(+1); e.accepted = true }
                                        Keys.onReturnPressed: {
                                            if (root.filtered.length > root.focusedIdx)
                                                root.applyWallpaper(root.filtered[root.focusedIdx])
                                        }
                                    }
                                }
                            }

                            // Clear search
                            Rectangle {
                                visible: root.searchText !== ""
                                width: 34; height: 34
                                radius: root.rFull
                                color: clrHov.containsMouse ? root.cSurfHiHi : "transparent"
                                border.color: root.cOutlineVar; border.width: 1
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Text {
                                    anchors.centerIn: parent; text: "󰅖"
                                    color: root.cOnSurfVar
                                    font.pixelSize: 14
                                    font.family: "Symbols Nerd Font Mono"
                                }
                                MouseArea {
                                    id: clrHov
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: searchIn.text = ""
                                }
                            }

                            // Name ↓ / Random sort toggle
                            Rectangle {
                                width: 80; height: 34
                                radius: root.rFull
                                color: sortHov.containsMouse ? root.cSurfHiHi : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                                border.color: root.cOutlineVar; border.width: 1
                                Behavior on color { ColorAnimation { duration: 130 } }
                                RowLayout {
                                    anchors.centerIn: parent; spacing: 5
                                    Text {
                                        text: root.sortMode === "random" ? "󰒝" : "󰒼"
                                        color: root.cPrimary
                                        font.pixelSize: 13; font.family: "Symbols Nerd Font Mono"
                                    }
                                    Text {
                                        text: root.sortMode === "random" ? "Random" : "Name ↓"
                                        color: root.cOnSurfVar; font.pixelSize: 12
                                    }
                                }
                                MouseArea {
                                    id: sortHov
                                    anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.sortMode = (root.sortMode === "name") ? "random" : "name"
                                        appSettings.sortMode = root.sortMode
                                        root.sortAndFilter()
                                    }
                                }
                            }

                            // Refresh
                            Rectangle {
                                width: 34; height: 34; radius: root.rFull
                                color: refHov.containsMouse ? root.cSurfHiHi : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                                border.color: root.cOutlineVar; border.width: 1
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Text {
                                    anchors.centerIn: parent; text: "↺"
                                    color: root.cPrimary; font.pixelSize: 17
                                }
                                MouseArea {
                                    id: refHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!thumbCacheClearProc.running)
                                            thumbCacheClearProc.running = true
                                    }
                                }
                            }

                            // Random pick
                            Rectangle {
                                width: 34; height: 34; radius: root.rFull
                                color: rndHov.containsMouse ? root.cSurfHiHi : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                                border.color: root.cOutlineVar; border.width: 1
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Text {
                                    anchors.centerIn: parent; text: "󰒅"
                                    color: root.cPrimary; font.pixelSize: 15; font.family: "Symbols Nerd Font Mono"
                                }
                                MouseArea {
                                    id: rndHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (root.filtered.length > 0) {
                                            const i = Math.floor(Math.random() * root.filtered.length)
                                            root.focusedIdx = i
                                            root.applyWallpaper(root.filtered[i])
                                        }
                                    }
                                }
                            }

                            // Clear awww cache
                            Rectangle {
                                id: cacheBtnRect
                                width: 34; height: 34; radius: root.rFull
                                color: cacheHov.containsMouse ? root.cSurfHiHi
                                       : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                                border.color: root.cOutlineVar; border.width: 1
                                Behavior on color { ColorAnimation { duration: 130 } }

                                // Default icon: broom (nf-md-broom)
                                Text {
                                    anchors.centerIn: parent
                                    text: "󱘗"
                                    color: root.cOnSurfVar
                                    font.pixelSize: 15; font.family: "Symbols Nerd Font Mono"
                                    visible: !cacheSpinning.running
                                }

                                // Spinning icon while cache is clearing or warming
                                Text {
                                    id: cacheSpinner
                                    anchors.centerIn: parent
                                    text: "󰑪"
                                    color: root.cPrimary
                                    font.pixelSize: 15; font.family: "Symbols Nerd Font Mono"
                                    visible: cacheSpinning.running
                                    RotationAnimator {
                                        id: cacheSpinning
                                        target: cacheSpinner
                                        from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                        running: cacheProc.running
                                    }
                                }

                                // awww does not expose a clear-cache subcommand.
                                // Its cache lives at $XDG_CACHE_HOME/awww (scaled image
                                // thumbnails). We delete that directory directly.
                                Process {
                                    id: cacheProc
                                    command: [
                                        "bash", "-c",
                                        "CACHE=\"${XDG_CACHE_HOME:-$HOME/.cache}\"; " +
                                        "rm -rf \"$CACHE/awww\" \"$CACHE/awww_cache\" 2>/dev/null; " +
                                        "echo 'awww cache cleared'"
                                    ]
                                    onRunningChanged: cacheSpinning.running = running
                                }

                                MouseArea {
                                    id: cacheHov; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        if (!cacheProc.running) {
                                            cacheProc.running = true
                                        }
                                    }
                                }
                            }

                            // Count badge
                            Rectangle {
                                visible: root.filtered.length > 0
                                width: Math.max(32, cntTxt.implicitWidth + 16); height: 34
                                radius: root.rFull
                                color: Qt.rgba(root.cSecCont.r, root.cSecCont.g, root.cSecCont.b, 0.7)
                                Text {
                                    id: cntTxt; anchors.centerIn: parent
                                    text: root.filtered.length
                                    color: root.cOnSecCont; font.pixelSize: 12
                                }
                            }
                        }

                        // ── Wallpaper grid ────────────────────────────────────
                        GridView {
                            id: gridView
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true

                            readonly property int thumbW: 160
                            readonly property int thumbH: 100
                            readonly property int gap:    10
                            readonly property int cols: Math.max(1,
                                Math.floor((width + gap) / (thumbW + gap)))

                            cellWidth:  Math.floor(width / cols)
                            cellHeight: thumbH + gap
                            leftMargin: Math.floor((width - (cols * cellWidth)) / 2)
                            rightMargin: leftMargin
                            model: root.filtered.length

                            WheelHandler {
                                onWheel: function(e) {
                                    root.moveFocus(e.angleDelta.y > 0 ? -1 : 1)
                                    e.accepted = true
                                }
                            }

                            delegate: Item {
                                id: thumb
                                required property int index

                                readonly property bool   isFocused: index === root.focusedIdx
                                readonly property bool   isActive:  root.currentWallpaper !== "" &&
                                                                    root.filtered[index] === root.currentWallpaper
                                readonly property string path:      root.filtered[index] ?? ""

                                width:  gridView.cellWidth
                                height: gridView.cellHeight

                                scale: isFocused ? 1.08 : 1.0
                                z:     isFocused ? 10 : 0
                                Behavior on scale {
                                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                                }

                                // Receives thumb path from the central pipeline
                                property string thumbSrc: ""
                                Connections {
                                    target: root
                                    function onThumbReady(origPath, src) {
                                        if (origPath === thumb.path) thumb.thumbSrc = src
                                    }
                                }

                                // Remove from queue when delegate is destroyed so we don't
                                // waste a magick slot on a tile that's no longer visible.
                                Component.onDestruction: {
                                    const i = root._thumbQueue.indexOf(path)
                                    if (i >= 0) root._thumbQueue.splice(i, 1)
                                }

                                // GridView recycles delegates for new paths on scroll/sort.
                                // _prevPath lets us splice the stale entry out of the queue
                                // before requesting the new path.
                                property string _prevPath: ""
                                onPathChanged: {
                                    if (_prevPath) {
                                        const i = root._thumbQueue.indexOf(_prevPath)
                                        if (i >= 0) root._thumbQueue.splice(i, 1)
                                    }
                                    _prevPath = path
                                    thumbSrc  = ""
                                    if (path) root.thumbRequest(path)
                                }
                                Component.onCompleted: {
                                    _prevPath = path
                                    root.thumbRequest(path)
                                }

                                // thumbCard — background card; radius 30 matches magick output
                                Rectangle {
                                    id: thumbCard
                                    anchors.centerIn: parent
                                    width:  gridView.thumbW
                                    height: gridView.thumbH
                                    radius: 20
                                    color:  "#1a1a1a"
                                    clip:   true

                                    // ImageMagick-generated rounded PNG (transparent corners
                                    // are naturally transparent over the card background)
                                    Image {
                                        id: wallImg
                                        anchors.fill: parent
                                        // thumbSrc when ready; empty string while generating
                                        source:      thumb.thumbSrc
                                        fillMode:    Image.PreserveAspectCrop
                                        asynchronous: true
                                        smooth:  true
                                        mipmap:  false   // avoid QSGPlainTexture warning on dynamic src
                                        cache:   false   // prevent accumulation in Qt image cache
                                        visible: status === Image.Ready && thumb.thumbSrc !== ""
                                    }

                                    // Placeholder — shown while magick generates the thumb
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 20
                                        color: "#252525"
                                        visible: !wallImg.visible
                                        Text {
                                            anchors.centerIn: parent
                                            text: thumb.thumbSrc === "" ? "󰋩" : (wallImg.status === Image.Error ? "󰋵" : "󰋩")
                                            color: "#888888"
                                            font.pixelSize: 30
                                            font.family: "Symbols Nerd Font Mono"
                                        }
                                    }

                                }

                                // Filename bar — sibling of thumbCard, overlaid on its
                                // bottom edge. An Item clip-wrapper masks the top portion
                                // of the bar rectangle so only the bottom two rounded
                                // corners are visible, flush with the card's own corners.
                                Item {
                                    anchors {
                                        left:   thumbCard.left
                                        right:  thumbCard.right
                                        bottom: thumbCard.bottom
                                    }
                                    height: thumb.isFocused ? 28 : 0
                                    clip: true
                                    z: 2
                                    Behavior on height {
                                        NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                    }
                                    Rectangle {
                                        anchors {
                                            left:   parent.left
                                            right:  parent.right
                                            bottom: parent.bottom
                                        }
                                        // Taller than the visible strip by the radius so the
                                        // top two rounded corners are hidden above parent's
                                        // clip boundary — only bottom corners show.
                                        height: (thumb.isFocused ? 28 : 0) + 20
                                        radius: 20
                                        color: root.cPanelBg
                                        Text {
                                            anchors {
                                                left:   parent.left
                                                right:  parent.right
                                                bottom: parent.bottom
                                                leftMargin:  10
                                                rightMargin: 10
                                                bottomMargin: 0
                                            }
                                            height: 28
                                            text: thumb.path.split('/').pop()
                                            color: root.cOnSecCont; font.pixelSize: 12
                                            elide: Text.ElideRight
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                    }
                                }

                                // Active badge — sibling of thumbCard, not inside
                                // the layer, so its radius renders without jagging.
                                Rectangle {
                                    anchors {
                                        top:    thumbCard.top
                                        right:  thumbCard.right
                                        topMargin:   6
                                        rightMargin: 6
                                    }
                                    width: 20; height: 20; radius: root.rFull
                                    color: root.cPrimary
                                    visible: thumb.isActive
                                    Text {
                                        anchors.centerIn: parent; text: "󰄬"
                                        color: root.cOnPrimary
                                        font.pixelSize: 11; font.family: "Symbols Nerd Font Mono"
                                    }
                                }

                                MouseArea {
                                    anchors.fill: thumbCard
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: root.focusedIdx = thumb.index
                                    onClicked: root.applyWallpaper(thumb.path)
                                }
                            } // delegate Item

                            // Empty / loading state
                            Item {
                                anchors.fill: parent
                                visible: root.filtered.length === 0
                                Column {
                                    anchors.centerIn: parent; spacing: 14
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: scanProc.running ? "󰑪"
                                            : root.wallpaperDir ? "󰋩" : "󰉋"
                                        color: root.cOutlineVar; font.pixelSize: 52
                                        font.family: "Symbols Nerd Font Mono"
                                        RotationAnimator on rotation {
                                            from: 0; to: 360; duration: 1200
                                            loops: Animation.Infinite
                                            running: scanProc.running
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: scanProc.running ? "Scanning…"
                                            : root.wallpaperDir
                                                ? (root.searchText
                                                    ? "No results for \"" + root.searchText + "\""
                                                    : "No wallpapers found in this folder")
                                                : "Click Folder to browse directories"
                                        color: root.cOutline; font.pixelSize: 15
                                    }
                                }
                            }
                        }

                        // ── Bottom transition bar ─────────────────────────────
                        Rectangle {
                            Layout.fillWidth: true
                            height: 42; radius: root.rSm
                            color: Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                            border.color: root.cOutlineVar; border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                spacing: 8

                                // Backend badge
                                Rectangle {
                                    width: 52; height: 26; radius: root.rFull
                                    color: Qt.rgba(root.cSecCont.r, root.cSecCont.g, root.cSecCont.b, 0.8)
                                    Text {
                                        anchors.centerIn: parent; text: "awww"
                                        color: root.cOnSecCont; font.pixelSize: 11; font.weight: Font.Medium
                                    }
                                }

                                // Transition type pills
                                Repeater {
                                    model: ["any","simple","fade","left","right","top","bottom",
                                            "wipe","wave","grow","center","outer","random"]
                                    delegate: Rectangle {
                                        required property string modelData
                                        visible: root.transType === modelData || ttHov.containsMouse
                                        width: ttLbl.implicitWidth + 14; height: 26; radius: root.rFull
                                        color: root.transType === modelData
                                               ? root.cPrimary
                                               : (ttHov.containsMouse ? root.cSurfHiHi : "transparent")
                                        Behavior on color { ColorAnimation { duration: 100 } }
                                        Text {
                                            id: ttLbl; anchors.centerIn: parent
                                            text: parent.modelData
                                            color: root.transType === parent.modelData ? root.cOnPrimary : root.cOutline
                                            font.pixelSize: 11
                                        }
                                        MouseArea {
                                            id: ttHov; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                root.transType = parent.modelData
                                                appSettings.transType = root.transType
                                            }
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                // Editable fields: duration, angle, fps, steps
                                Repeater {
                                    model: [
                                        { lbl: "durat…", prop: "transDuration" },
                                        { lbl: "angle",  prop: "transAngle"    },
                                        { lbl: "fps",    prop: "transFps"      },
                                        { lbl: "steps",  prop: "transStep"     }
                                    ]
                                    delegate: RowLayout {
                                        required property var modelData
                                        spacing: 4
                                        Text {
                                            text: parent.modelData.lbl
                                            color: root.cOutline; font.pixelSize: 11
                                        }
                                        Rectangle {
                                            width: 46; height: 26; radius: root.rFull
                                            color: Qt.rgba(root.cSecCont.r, root.cSecCont.g, root.cSecCont.b, 0.8)
                                            TextInput {
                                                anchors.centerIn: parent; width: parent.width - 10
                                                text: root[parent.parent.modelData.prop]
                                                color: root.cOnSecCont; font.pixelSize: 11
                                                horizontalAlignment: TextInput.AlignHCenter
                                                inputMethodHints: Qt.ImhFormattedNumbersOnly
                                                onEditingFinished: {
                                                    root[parent.parent.modelData.prop] = text
                                                    appSettings[parent.parent.modelData.prop] = text
                                                }
                                            }
                                        }
                                    }
                                }

                                // Fill badge
                                Rectangle {
                                    width: 52; height: 26; radius: root.rFull
                                    color: Qt.rgba(root.cSecCont.r, root.cSecCont.g, root.cSecCont.b, 0.8)
                                    Text {
                                        anchors.centerIn: parent
                                        text: root.fillMode.charAt(0).toUpperCase() + root.fillMode.slice(1)
                                        color: root.cOnSecCont; font.pixelSize: 11
                                    }
                                    MouseArea {
                                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            const modes = ["no","crop","fit","stretch"]
                                            const i = modes.indexOf(root.fillMode)
                                            root.fillMode = modes[(i + 1) % modes.length]
                                            appSettings.fillMode = root.fillMode
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
