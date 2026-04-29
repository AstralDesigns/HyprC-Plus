import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

// ══════════════════════════════════════════════════════════════════════════
//  DesktopLayer — pinned app icons on the Background Wayland layer.
//
//  Layer:      Background  (below Bottom)
//  Namespace:  quickshell:desktop
//  Exclusive:  Ignore  (never steals space from tiling)
//  Background: transparent
//
//  Add to hyprland.conf:
//    layerrule = blur,              quickshell:desktop
//    layerrule = ignorealpha 0.01,  quickshell:desktop
// ══════════════════════════════════════════════════════════════════════════

Item {
    id: desktopScope

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            color:         "transparent"
            visible:       Config.desktopVisible

            WlrLayershell.namespace: "quickshell:desktop"
            WlrLayershell.layer:     WlrLayer.Bottom

            anchors { top: true; bottom: true; left: true; right: true }

            // ── dGPU detection via switcheroo-control ──────────────────────
            property var  _gpuList:  []
            property bool _gpuReady: false

            Process {
                id: _gpuProc
                property string _buf: ""
                running: true
                command: ["bash", "-c",
                    "python3 -c \"\n" +
                    "import sys, json\n" +
                    "try:\n" +
                    "    import gi; gi.require_version('GLib','2.0'); from gi.repository import GLib, Gio\n" +
                    "    r = Gio.DBus.get_sync(Gio.BusType.SYSTEM,None).call_sync(" +
                    "'net.hadess.SwitcherooControl','/net/hadess/SwitcherooControl'," +
                    "'org.freedesktop.DBus.Properties','Get'," +
                    "GLib.Variant('(ss)',['net.hadess.SwitcherooControl','GPUs'])," +
                    "None,Gio.DBusCallFlags.NONE,-1,None)\n" +
                    "    gpus=[]\n" +
                    "    for g in r.unpack()[0]:\n" +
                    "        if g.get('Default',True): continue\n" +
                    "        ev=g.get('Environment',[]); env={}\n" +
                    "        for i in range(0,len(ev)-1,2): env[ev[i]]=ev[i+1]\n" +
                    "        gpus.append({'name':g.get('Name','dGPU'),'env':env})\n" +
                    "    print(json.dumps(gpus))\n" +
                    "except: print('[]')\n" +
                    "\" 2>/dev/null || echo '[]'"
                ]
                stdout: SplitParser {
                    splitMarker: "\n"
                    onRead: function(line) { _gpuProc._buf += line }
                }
                onExited: {
                    try { win._gpuList = JSON.parse(_gpuProc._buf) } catch (_) { win._gpuList = [] }
                    win._gpuReady = true
                }
            }

            // ── Drag state ────────────────────────────────────────────────
            // Track by class string rather than index so the opacity binding
            // stays correct across the brief period between _isDragging being
            // cleared and the Repeater rebuilding its delegates.
            property string _dragCls:      ""   // class of item being dragged
            property int    _dropAfterIdx: -1   // insert position (-1 = prepend)
            property bool   _isDragging:   false

            // ── Right-click context menu state ────────────────────────────
            property int    _menuAppIdx: -1
            property real   _menuX:       0
            property real   _menuY:       0
            property bool   _menuVisible: false

            function _showMenu(idx, mx, my) {
                _menuAppIdx = idx
                const mw = contextMenu.width
                const mh = contextMenu.implicitHeight
                _menuX = Math.min(mx, win.width  - mw - 8)
                _menuY = Math.min(my, win.height - mh - 8)
                _menuVisible = true
            }

            function _hideMenu() {
                _menuVisible = false
                _menuAppIdx  = -1
            }

            // ── Full-surface dismiss ───────────────────────────────────────
            MouseArea {
                anchors.fill: parent
                z: -1
                onClicked: win._hideMenu()
            }

            // ── Icon grid ─────────────────────────────────────────────────
            //  flow: TopToBottom with a height constraint makes the grid fill
            //  one column top-to-bottom, then wrap into a second column, etc.
            //  This way icons never go off the bottom of the screen.
            Flow {
                id: iconGrid
                anchors {
                    top:    parent.top
                    left:   parent.left
                    bottom: parent.bottom
                    margins: 18
                }
                // No explicit width — let it grow rightward as columns fill.
                // TopToBottom flow: items fill column top→bottom, wrap right.
                flow:    Flow.TopToBottom
                spacing: 16

                Repeater {
                    id: iconRepeater
                    model: DesktopPinnedState.apps

                    delegate: Item {
                        id: iconItem
                        required property var modelData
                        required property int index

                        readonly property string _cls:       modelData["class"]     ?? ""
                        readonly property string _name:      modelData["name"]      ?? _cls
                        readonly property string _exec:      modelData["exec"]      ?? _cls
                        readonly property string _icon:      modelData["icon"]      ?? _cls.toLowerCase()
                        readonly property string _desktopId: modelData["desktopId"] ?? ""

                        // Fixed cell size — both dimensions explicit so Flow
                        // can pack them correctly in TopToBottom mode.
                        width:  Config.desktopIconSize + 16
                        height: Config.desktopIconSize + Config.desktopLabelSize + 22

                        readonly property string _iconSrc: {
                            if (_icon.startsWith("/"))
                                return "file://" + _icon
                            return Quickshell.iconPath(_icon, "application-x-executable")
                        }

                        // Fade the item being dragged. Compare by class string,
                        // not index — index can be stale for one frame after the
                        // model changes and gives the wrong item a ghost shadow.
                        opacity: (win._isDragging && win._dragCls === _cls) ? 0.35 : 1.0
                        Behavior on opacity { NumberAnimation { duration: 80 } }

                        // Drop-indicator: thin bar above this item when the drag
                        // cursor is positioned to insert before it.
                        Rectangle {
                            anchors.top:              parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            width:  parent.width - 8
                            height: 3
                            radius: 2
                            color:  Theme.cPrimary
                            visible: win._isDragging
                                     && win._dropAfterIdx === (index - 1)
                                     && win._dragCls !== _cls
                                     && (index === 0
                                         || win._dragCls !== (DesktopPinnedState.apps[index - 1]?.["class"] ?? ""))
                        }

                        // ── Icon image ────────────────────────────────────
                        Image {
                            id: appIcon
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: parent.top
                            width:    Config.desktopIconSize
                            height:   Config.desktopIconSize
                            source:   iconItem._iconSrc
                            sourceSize: Qt.size(Config.desktopIconSize, Config.desktopIconSize)
                            smooth:   true
                            mipmap:   true
                            fillMode: Image.PreserveAspectFit

                            Text {
                                anchors.centerIn: parent
                                visible: appIcon.status !== Image.Ready
                                text:    ""
                                font.pixelSize: Config.desktopIconSize * 0.6
                                color:   Theme.cPrimary
                            }
                        }

                        // ── Label ─────────────────────────────────────────
                        Rectangle {
                            id: labelBg
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: appIcon.bottom
                            anchors.topMargin: 4
                            width:  Math.min(nameLabel.implicitWidth + 10, parent.width)
                            height: nameLabel.implicitHeight + 5
                            radius: 4
                            color:  Theme.cPanelBg

                            Text {
                                id: nameLabel
                                anchors.centerIn: parent
                                width:            parent.width - 10
                                text:             iconItem._name
                                font.pixelSize:   Config.desktopLabelSize
                                color:            Theme.cPrimary
                                elide:            Text.ElideRight
                                maximumLineCount: 1
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }

                        // ── Hover scale (suppressed while dragging) ───────
                        scale: (!win._isDragging && iconMouse.containsMouse) ? 1.07 : 1.0
                        Behavior on scale { NumberAnimation { duration: 100 } }

                        // ── Input ─────────────────────────────────────────
                        MouseArea {
                            id: iconMouse
                            anchors.fill:    parent
                            hoverEnabled:    true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape:     win._isDragging
                                             ? Qt.ClosedHandCursor
                                             : Qt.PointingHandCursor

                            // Single-click: right = context menu, left = launch.
                            // Guard: ignore release if we just finished a drag.
                            onClicked: function(mouse) {
                                if (win._isDragging) return
                                if (mouse.button === Qt.RightButton) {
                                    const pt = iconItem.mapToItem(win.contentItem, mouse.x, mouse.y)
                                    win._showMenu(iconItem.index, pt.x, pt.y)
                                } else {
                                    _launchEntry(iconItem._desktopId, iconItem._exec, iconItem._cls)
                                    win._hideMenu()
                                }
                            }

                            // ── Drag: 200 ms hold disambiguates from click ──
                            onPressed: function(mouse) { dragStartTimer.start() }

                            onReleased: function(mouse) {
                                dragStartTimer.stop()
                                if (win._isDragging && win._dragCls === iconItem._cls) {
                                    // Commit reorder only if drop position changed
                                    const di    = win._dropAfterIdx
                                    const myIdx = iconItem.index
                                    const moved = (di !== myIdx) && (di !== myIdx - 1)
                                    // Always clear drag state first — prevents the
                                    // ghost from lingering while reorderApp runs
                                    win._isDragging   = false
                                    win._dragCls      = ""
                                    win._dropAfterIdx = -1
                                    if (moved) {
                                        const apps     = DesktopPinnedState.apps
                                        const afterCls = (di < 0) ? ""
                                                       : (apps[di]?.["class"] ?? "")
                                        DesktopPinnedState.reorderApp(iconItem._cls, afterCls)
                                    }
                                }
                            }

                            onPositionChanged: function(mouse) {
                                if (!win._isDragging || win._dragCls !== iconItem._cls) return

                                // Map pointer into iconGrid space.
                                // In TopToBottom flow the items are arranged in columns,
                                // so we need to find the closest item by 2D distance
                                // rather than just Y position.
                                const gpt = iconItem.mapToItem(iconGrid, mouse.x, mouse.y)

                                const cellW = Config.desktopIconSize + 16
                                const cellH = Config.desktopIconSize + Config.desktopLabelSize + 22 + 16
                                const total = DesktopPinnedState.apps.length

                                // How many items fit in one column?
                                const colCap = Math.max(1, Math.floor(
                                    (win.height - 36) / cellH  // 36 = 18*2 margins
                                ))

                                // Which column and row is the pointer in?
                                const col = Math.max(0, Math.floor(gpt.x / cellW))
                                const row = Math.max(0, Math.floor(gpt.y / cellH))
                                const hitIdx = Math.min(col * colCap + row, total - 1)

                                // Is pointer in the top half or bottom half of that cell?
                                const cellLocalY = gpt.y - row * cellH
                                const dropAfter  = (cellLocalY >= cellH / 2) ? hitIdx : hitIdx - 1

                                win._dropAfterIdx = Math.max(-1, Math.min(dropAfter, total - 1))
                            }

                            onCanceled: {
                                dragStartTimer.stop()
                                if (win._isDragging && win._dragCls === iconItem._cls) {
                                    win._isDragging   = false
                                    win._dragCls      = ""
                                    win._dropAfterIdx = -1
                                }
                            }

                            Timer {
                                id: dragStartTimer
                                interval: 200
                                repeat:   false
                                onTriggered: {
                                    if (iconMouse.pressed) {
                                        win._isDragging   = true
                                        win._dragCls      = iconItem._cls
                                        win._dropAfterIdx = iconItem.index
                                        win._hideMenu()
                                    }
                                }
                            }
                        }
                    }
                }

                // Drop-indicator at the very end (insert after last item).
                Item {
                    width:  Config.desktopIconSize + 16
                    height: 8
                    Rectangle {
                        anchors.top:              parent.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        width:  parent.width - 8
                        height: 3
                        radius: 2
                        color:  Theme.cPrimary
                        visible: win._isDragging
                                 && win._dropAfterIdx === DesktopPinnedState.apps.length - 1
                                 && win._dragCls !== (DesktopPinnedState.apps[DesktopPinnedState.apps.length - 1]?.["class"] ?? "_")
                    }
                }
            }

            // ── Inline context menu ────────────────────────────────────────
            Rectangle {
                id: contextMenu
                x: win._menuX
                y: win._menuY
                visible:        win._menuVisible && win._menuAppIdx >= 0
                z:              100
                color:          Theme.cOnSecondary
                radius:         8
                width:          180
                implicitHeight: menuCol.implicitHeight + 16
                border.width:   0
                layer.enabled:  true

                readonly property var _app: (win._menuAppIdx >= 0 && win._menuAppIdx < DesktopPinnedState.apps.length)
                                            ? DesktopPinnedState.apps[win._menuAppIdx]
                                            : null

                MouseArea { anchors.fill: parent; onClicked: {} }

                Column {
                    id: menuCol
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
                    spacing: 2

                    Text {
                        width:          parent.width
                        text:           contextMenu._app ? (contextMenu._app["name"] ?? "") : ""
                        font.pixelSize: Config.desktopLabelSize + 1
                        font.bold:      true
                        color:          Theme.cPrimary
                        elide:          Text.ElideRight
                        horizontalAlignment: Text.AlignHCenter
                        bottomPadding:  4
                    }

                    Rectangle { width: parent.width; height: 1; color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2) }

                    DeskMenuBtn {
                        label: "Launch"
                        onTriggered: {
                            if (contextMenu._app)
                                _launchEntry(contextMenu._app["desktopId"] ?? "",
                                             contextMenu._app["exec"]      ?? "",
                                             contextMenu._app["class"]     ?? "")
                            win._hideMenu()
                        }
                    }

                    // dGPU launch section — only on hybrid-graphics systems
                    Loader {
                        active: win._gpuReady && win._gpuList.length > 0
                        width:  parent.width
                        sourceComponent: Column {
                            spacing: 2
                            Rectangle {
                                width: parent.width; height: 1
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                            }
                            Text {
                                width: parent.width
                                text: "Launch with dGPU"
                                font.pixelSize: Config.desktopLabelSize - 1
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.6)
                                horizontalAlignment: Text.AlignHCenter
                                topPadding: 2; bottomPadding: 2
                            }
                            Repeater {
                                model: win._gpuList
                                delegate: DeskMenuBtn {
                                    required property var modelData
                                    label: _abbrevGpu(modelData.name ?? "dGPU")
                                    onTriggered: {
                                        if (contextMenu._app)
                                            _launchOnGpu(contextMenu._app["exec"] || contextMenu._app["class"],
                                                         modelData.env ?? {})
                                        win._hideMenu()
                                    }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width; height: 1
                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
                    }

                    DeskMenuBtn {
                        label: "Unpin from desktop"
                        onTriggered: {
                            if (contextMenu._app) {
                                const cls = contextMenu._app["class"]
                                win._hideMenu()
                                DesktopPinnedState.removeApp(cls)
                            }
                        }
                    }
                }
            }

            // ── Reusable menu button ───────────────────────────────────────
            component DeskMenuBtn: Rectangle {
                id: _btn
                property string label: ""
                signal triggered()
                width:  parent?.width ?? 164
                height: _btnLabel.implicitHeight + 10
                radius: 6
                color:  _btnMa.containsMouse
                        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                        : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                Text {
                    id: _btnLabel
                    anchors.centerIn: parent
                    text:           _btn.label
                    font.pixelSize: Config.desktopLabelSize
                    color:          Theme.cPrimary
                }
                MouseArea {
                    id: _btnMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape:  Qt.PointingHandCursor
                    onClicked:    _btn.triggered()
                }
            }

            // ── Launch helpers ─────────────────────────────────────────────
            // Prefer DesktopEntries.byId(desktopId).execute() — this handles
            // DBus activation, startup notification, env propagation, and
            // Wayland-specific startup protocols correctly for every app type
            // (Flatpak, native GTK, Qt, Electron, etc.).
            // Falls back to bash exec for entries whose desktopId is unknown.

            property string _pendingCmd: ""

            Timer {
                id: _launchTimer
                interval: 0
                repeat:   false
                onTriggered: {
                    if (win._pendingCmd !== "") {
                        _launchProc.command = ["bash", "-c", win._pendingCmd]
                        _launchProc.running = true
                        win._pendingCmd = ""
                    }
                }
            }

            // Primary launch path: use entry.execute() when we have a valid ID.
            function _launchEntry(desktopId, exec, cls) {
                // Try DesktopEntries.byId with all the same variants that
                // _resolveApps() tried so we never miss an entry at launch time.
                if (desktopId && desktopId !== "") {
                    const entry = DesktopEntries.byId(desktopId)
                    if (entry) { entry.execute(); return }
                }
                // byId miss — try common variants of the class name
                const variants = [cls, cls.toLowerCase(),
                                  cls.split('.').pop(),
                                  cls.split('.').pop().toLowerCase()]
                for (const v of variants) {
                    const e = DesktopEntries.byId(v)
                    if (e) { e.execute(); return }
                }
                // Final fallback: strip field codes and run via bash
                _launchApp(exec || cls)
            }

            function _launchApp(exec) {
                if (!exec || exec === "") return
                const clean = exec.replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
                _launchProc.running = false
                win._pendingCmd = clean + " &"
                _launchTimer.restart()
            }

            function _launchOnGpu(exec, envObj) {
                if (!exec || exec === "") return
                const clean = exec.replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
                let envStr = ""
                for (const [k, v] of Object.entries(envObj ?? {}))
                    envStr += k + "=" + v + " "
                _launchProc.running = false
                win._pendingCmd = envStr + clean + " &"
                _launchTimer.restart()
            }

            function _abbrevGpu(name) {
                return name
                    .replace(/^Advanced Micro Devices,?\s*Inc\.?\s*\[AMD\/ATI\]\s*/i, "")
                    .replace(/^NVIDIA\s+Corporation\s*/i, "")
                    .replace(/^Intel\s+Corporation\s*/i, "")
                    .slice(0, 32)
            }

            Process {
                id: _launchProc
                running: false
            }

            // One-shot timer: re-resolve icons after startup so any that
            // missed the icon theme index window get a second chance.
            Timer {
                interval: 500
                repeat:   false
                running:  true
                onTriggered: DesktopPinnedState.forceRefresh()
            }

            Process {
                id: _writeProc
                running: false
            }

            Connections {
                target: DesktopPinnedState
                function onSaveRequested(newList) {
                    const scriptPath = Config.barDir + "/scripts/desktop-pinned-write.sh"
                    _writeProc.command = [scriptPath, ...newList]
                    _writeProc.running = false
                    _writeProc.running = true
                }
            }
        }
    }
}
