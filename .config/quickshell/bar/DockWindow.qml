pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "."

// ═══════════════════════════════════════════════════════════════════════════
//  DockWindow.qml — native qs dock (GJS hyprcandydock port).
//
//  Phase-2 scope: pinned + running apps, indicators, start/trash badges,
//  glass/gradient island theming, per-position anchoring.
//  Menus / DnD / GPU / auto-hide / position pills land in phase 3.
//
//  Layer namespace stays "hyprcandy-dock" so the existing hyprviz.lua
//  layer_rule (blur / xray / no_anim / ignore_alpha) keeps applying.
// ═══════════════════════════════════════════════════════════════════════════

PanelWindow {
    id: dock

    required property var screen

    readonly property string position: DockState.position
    readonly property bool isHorizontal: position === "bottom" || position === "top"
    readonly property bool isTop:    position === "top"
    readonly property bool isBottom: position === "bottom"
    readonly property bool isLeft:   position === "left"
    readonly property bool isRight:  position === "right"

    readonly property HyprlandMonitor monitor: Hyprland.monitorFor(screen)

    visible: true
    color: "transparent"

    WlrLayershell.namespace: "hyprcandy-dock"
    WlrLayershell.layer: Config.dockLayer === "overlay" ? WlrLayer.Overlay : WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Compact island (GJS dock parity): anchor ONE perpendicular edge plus
    // the bar edge, and centre along the edge via margins. Anchoring both
    // left+right (or top+bottom) would stretch the surface to the full
    // screen extent and override the implicit content size.
    readonly property real scrW: dock.screen.width
    readonly property real scrH: dock.screen.height

    // Screen-space origin of the compact island, derived from the same
    // centring math as the margins below (PanelWindow.x/y are not reliably
    // populated for auto-positioned surfaces in this qs build).
    readonly property real originX: isLeft ? Config.dockMargin
        : isRight ? dock.scrW - dock.width - Config.dockMargin
        : Math.round((dock.scrW - dock.width) / 2)
    readonly property real originY: isTop ? Config.dockMargin
        : isBottom ? dock.scrH - dock.height - Config.dockMargin
        : Math.round((dock.scrH - dock.height) / 2)

    anchors {
        top:    isTop    || isLeft || isRight
        bottom: isBottom
        left:   isLeft   || isTop  || isBottom
        right:  isRight
    }
    margins {
        top:    isTop    ? Config.dockMargin
                          : Math.round((dock.scrH - dock.height) / 2)
        bottom: isBottom ? Config.dockMargin : 0
        left:   isLeft   ? Config.dockMargin
                          : Math.round((dock.scrW - dock.width) / 2)
        right:  isRight  ? Config.dockMargin : 0
    }

    // Content thickness across the perpendicular axis: uniform ring —
    // dockInnerPadding on every side around the button strip, each button
    // carrying its own dockPadding around the icon.
    readonly property real buttonSize: Config.dockIconSize + 2 * Config.dockPadding
    readonly property real contentThickness: dock.buttonSize + 2 * Config.dockInnerPadding

    // Dock reserves desktop space by default (user request) — the CC
    // Reserve toggle stays removed; the behaviour is applied internally.
    // Auto: Quickshell computes the zone from surface size + margins
    // (Normal + explicit exclusiveZone was ignored by hyprland here).
    exclusionMode: ExclusionMode.Auto

    implicitWidth:  isHorizontal ? rowOuter.implicitWidth  + 2 * Config.dockInnerPadding
                                 : dock.contentThickness
    implicitHeight: isHorizontal ? dock.contentThickness
                                 : colOuter.implicitHeight + 2 * Config.dockInnerPadding

    readonly property real dockPadding: Config.dockPadding

    // ── Dock model: pinned order first, then running-unpinned classes ──────
    // Steam games (steam_app_<id>) fold into the plain "steam" class, ported
    // from dock-main.js.
    function _normClass(cls) {
        if (!cls) return ""
        let c = String(cls).toLowerCase()
        if (/^steam_app_\d+$/.test(c)) c = "steam"
        return c
    }

    // ── Window tracking ────────────────────────────────────────────────────
    // This qs build exposes Hyprland.toplevels : ObjectModel<HyprlandToplevel>.
    // `.values` notifies reactively on insert/remove, so dockModel + per-button
    // `instances` bindings re-run automatically. class/initialClass live in
    // lastIpcObject (raw `windows` JSON) and are only populated after a
    // refreshToplevels(), so we refresh on boot and debounced after openwindow.
    function _toplevelClass(tl) {
        const o = (tl && tl.lastIpcObject) || {}
        return String(o.class || o.initialClass || "")
    }

    // Reactivity anchor: touch values.length so bindings re-evaluate on changes.
    readonly property int toplevelCount: Hyprland.toplevels ? Hyprland.toplevels.values.length : 0
    // Bumped after every refreshToplevels() — lastIpcObject (class/title)
    // fills in without values.length changing, so dockModel/clientsFor must
    // also watch this or boot-time windows never resolve their icons.
    property int _classEpoch: 0
    
    Timer {
        id: _tlRefresh
        interval: 150
        repeat: false
        onTriggered: { Hyprland.refreshToplevels(); dock._classEpoch++ }
    }
    // Safety second pass — some clients register their class slowly after qs
    // boots (e.g. after a restart with windows already open).
    Timer {
        id: _tlRefreshLate
        interval: 900
        repeat: false
        onTriggered: { Hyprland.refreshToplevels(); dock._classEpoch++ }
    }

    // openwindow fires before lastIpcObject is filled; a debounced refresh
    // pulls the class/title so the icon + indicator resolve.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event && (event.name === "openwindow" || event.name === "movewindow"))
                _tlRefresh.restart()
        }
    }

    Component.onCompleted: {
        Hyprland.refreshToplevels()
        dock._classEpoch++
        _tlRefresh.restart()
        _tlRefreshLate.restart()
        _pixmapScan.running = true
        _steamScan.running = true
    }

    function _allToplevels() {
        const m = Hyprland.toplevels
        return (m && m.values) ? m.values : []
    }

    function clientsFor(appClass) {
        dock._classEpoch   // re-evaluate after a toplevels refresh
        const target = dock._normClass(appClass)
        const out = []
        const tls = dock._allToplevels()
        for (let i = 0; i < tls.length; i++) {
            const tl = tls[i]
            if (!tl) continue
            const o = tl.lastIpcObject || {}
            const c1 = dock._normClass(dock._toplevelClass(tl))
            const c2 = dock._normClass(o.initialClass)
            if ((c1 && c1 === target) || (c2 && c2 === target)) out.push(tl)
        }
        return out
    }

    // class → matched pinned id (so running-unpinned dedup respects the
    // tiered matcher's desktopId too).
    readonly property var dockModel: {
        dock.pinnedOrderKey  // dependency anchor
        dock.toplevelCount   // window set changes (open/close)
        dock._classEpoch     // class/title fill-in after refresh
        const out = []
        const seen = []
        for (const a of PinnedAppsState.orderedApps) {
            out.push({
                "id": a.class, "name": a.name, "icon": a.icon,
                "desktopId": a.desktopId, "exec": a.exec, "pinned": true,
            })
            seen.push(dock._normClass(a.class))
            if (a.desktopId) seen.push(dock._normClass(a.desktopId.replace(/\.desktop$/, "")))
        }
        const tls = dock._allToplevels()
        for (let i = 0; i < tls.length; i++) {
            const tl = tls[i]
            if (!tl) continue
            const c = dock._normClass(dock._toplevelClass(tl))
            if (!c || seen.indexOf(c) !== -1) continue
            seen.push(c)
            const entry = DesktopPinnedState._findEntry(c)
            out.push({
                "id": c,
                "name": entry ? entry.name : ((tl.lastIpcObject && tl.lastIpcObject.title) || c),
                "icon": entry ? entry.icon : c.toLowerCase(),
                "desktopId": entry ? entry.id : "",
                "exec": entry ? entry.execString : "",
                "pinned": false,
            })
        }
        return out
    }
    // Recompute dockModel whenever the pin order or client set shifts.
    readonly property string pinnedOrderKey: PinnedAppsState.pinnedOrderKey

    // ── /usr/share/pixmaps fallback map ─────────────────────────────────
    // Quickshell.iconPath only searches themed dirs; many installers drop
    // <class>.png straight into pixmaps (GTK finds those, we must too).
    // Scanned once at boot: lowercase basename → absolute path.
    property var _pixmapIcons: ({})
    Process {
        id: _pixmapScan
        command: ["bash", "-c",
            'for d in "$HOME/.local/share/pixmaps" /usr/share/pixmaps; do ' +
            '[ -d "$d" ] || continue; ' +
            'find "$d" -maxdepth 1 -type f \\( -iname "*.png" -o -iname "*.svg" -o -iname "*.xpm" -o -iname "*.ico" \\); done']
        running: false
        property var _lines: []
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { _pixmapScan._lines.push(l.trim()) }
        }
        onExited: {
            const map = {}
            for (const l of _lines) {
                const m = l.match(/\/([^/]+)\.(png|svg|xpm|ico)$/i)
                if (m && !(m[1].toLowerCase() in map)) map[m[1].toLowerCase()] = l
            }
            _lines = []
            dock._pixmapIcons = map
            running = false
        }
    }

    // ── Steam game shortcut icon map (~/Desktop) ─────────────────────────
    // Steam shortcuts live on ~/Desktop, outside the XDG app dirs, so neither
    // DesktopEntries nor Quickshell.iconPath can see them and pinned/running
    // Steam games fell through to the ghost glyph. DesktopLayer sidesteps this
    // by running tray-icon-resolve.py (which has a ~/Desktop step); the dock
    // gets the same reach via a boot-time scan: lowercase desktop basename
    // (the class we pin Steam games by) → the shortcut's Icon= field.
    property var _steamIcons: ({})
    Process {
        id: _steamScan
        running: false
        command: ["python3", "-c",
            "import os,glob,json,re\n" +
            "out={}\n" +
            "d=os.path.expanduser('~/Desktop')\n" +
            "for f in glob.glob(d+'/*.desktop'):\n" +
            "    try: txt=open(f,encoding='utf-8',errors='ignore').read()\n" +
            "    except: continue\n" +
            "    if not re.search(r'^Type=Application$',txt,re.M): continue\n" +
            "    m=re.search(r'^Exec=(.*)$',txt,re.M)\n" +
            "    if not m or 'steam://rungameid' not in m.group(1): continue\n" +
            "    ic=re.search(r'^Icon=(.*)$',txt,re.M)\n" +
            "    out[os.path.basename(f)[:-8].lower()]=(ic.group(1) if ic else 'steam')\n" +
            "print(json.dumps(out))"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { dock._steamIcons = JSON.parse(text) } catch (_) { dock._steamIcons = ({}) }
            }
        }
    }

    // ── Start-button glyph (bar distro module parity) ────────────────────
    // Mirrors modules/ControlCenter.qml: default Config.ccGlyph, overridden by
    // ~/.config/hyprcandy/candy-start-icon.txt when present so the dock start
    // button always shows the same distro glyph as the bar.
    property string _startGlyph: Config.ccGlyph !== "" ? Config.ccGlyph : "\u{F15FC}"
    FileView {
        path: Config.home + "/.config/hyprcandy/candy-start-icon.txt"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            const g = text().trim()
            if (g.length > 0) dock._startGlyph = g
        }
    }

    // ── Background ─────────────────────────────────────────────────────────
    //  glass    → Theme.blurBackground fill (compositor blur via the
    //             hyprviz.lua layer_rule rounds + blurs the surface)
    //  gradient → scrim → inverse_primary → scrim (dock-main.js parity; the
    //             3-stop is symmetric so only the axis matters)
    Rectangle {
        id: bg
        anchors.fill: parent
        radius: Config.dockRadius
        topLeftRadius: Config.dockTopLeftRadius
        topRightRadius: Config.dockTopRightRadius
        bottomLeftRadius: Config.dockBottomLeftRadius
        bottomRightRadius: Config.dockBottomRightRadius
        color: Config.dockBackgroundStyle === "gradient"
            ? "transparent" : Theme.blurBackground
        clip: true
        opacity: dock._ahHidden ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Rectangle {
            anchors.fill: parent
            radius: bg.radius
            visible: Config.dockBackgroundStyle === "gradient"
            gradient: Gradient {
                orientation: dock.isHorizontal ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0.0; color: Theme.cScrim }
                GradientStop { position: 0.5; color: Theme.cInversePrimary }
                GradientStop { position: 1.0; color: Theme.cScrim }
            }
        }
    }

    // Island border follows the bar border settings (GJS dock-border.sh
    // mirrored them; the CC Border W slider + Bar Border Color pickers are
    // the single control surface).
    Rectangle {
        anchors.fill: parent
        radius: bg.radius
        topLeftRadius: bg.topLeftRadius
        topRightRadius: bg.topRightRadius
        bottomLeftRadius: bg.bottomLeftRadius
        bottomRightRadius: bg.bottomRightRadius
        color: "transparent"
        border.width: Config.dockBackgroundStyle === "gradient"
                    ? 0 : Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                              Config.barBorderColor.b, Config.barBorderAlpha)
        opacity: dock._ahHidden ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    }

    // ── Buttons: start | apps | trash ──────────────────────────────────
    // Auto-hide fade (Bar.qml parity): content animates out before the
    // surface unmaps via _ahAnimExitTimer.
    Item {
        id: dockContent
        anchors.centerIn: parent
        width:  dock.isHorizontal ? rowOuter.implicitWidth  : colOuter.implicitWidth
        height: dock.isHorizontal ? rowOuter.implicitHeight : colOuter.implicitHeight
        opacity: dock._ahHidden ? 0.0 : 1.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        Row {
            id: rowOuter
            visible: dock.isHorizontal
            anchors.centerIn: parent
            spacing: Config.dockButtonSpacing

            DockBadge {
                id: startBadgeH
                kind: "start"
                glyph: dock._startGlyph
                onClicked: dock._startClicked()
                onRightClicked: dock._openMenu("start", null, startBadgeH)
            }
            Repeater {
                id: rowRepeaterH
                model: dock.dockModel
                DockAppButton {
                    id: appBtnSelf
                    required property var modelData
                    app: modelData
                    instances: dock.clientsFor(modelData.id)
                    onActivated: dock._buttonClicked(app, appBtnSelf)
                    onMenuRequested: dock._openMenu("app", app, appBtnSelf)
                }
            }
            DockBadge {
                id: trashBadgeH
                kind: "trash"
                glyph: TrashState.glyph
                tipText: TrashState.count === 0 ? "Trash (empty)"
                       : TrashState.count === 1 ? "Trash (1 item)"
                       : "Trash (" + TrashState.count + " items)"
                onClicked: dock._trashBadgeClicked()
                onRightClicked: dock._openMenu("trash", null, trashBadgeH)
            }
        }

        Column {
            id: colOuter
            visible: !dock.isHorizontal
            anchors.centerIn: parent
            spacing: Config.dockButtonSpacing

            DockBadge {
                id: startBadgeV
                kind: "start"
                glyph: dock._startGlyph
                onClicked: dock._startClicked()
                onRightClicked: dock._openMenu("start", null, startBadgeV)
            }
            Repeater {
                id: rowRepeaterV
                model: dock.dockModel
                DockAppButton {
                    id: appBtnSelf
                    required property var modelData
                    app: modelData
                    instances: dock.clientsFor(modelData.id)
                    vertical: true
                    onActivated: dock._buttonClicked(app, appBtnSelf)
                    onMenuRequested: dock._openMenu("app", app, appBtnSelf)
                }
            }
            DockBadge {
                id: trashBadgeV
                kind: "trash"
                glyph: TrashState.glyph
                tipText: TrashState.count === 0 ? "Trash (empty)"
                       : TrashState.count === 1 ? "Trash (1 item)"
                       : "Trash (" + TrashState.count + " items)"
                onClicked: dock._trashBadgeClicked()
                onRightClicked: dock._openMenu("trash", null, trashBadgeV)
            }
        }
    }

    // Right-click on empty dock surface → position / auto-hide menu.
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.RightButton
        onClicked: function(mouse) {
            dock._openMenu("background", null, dockBgAnchorAt(mouse.x, mouse.y))
        }
    }

    // Invisible anchor item so _openMenu can mapToItem() an arbitrary point
    // (the dock surface itself has no Item child at the click position).
    property Item dockBgAnchorItem: Item { x: 0; y: 0; width: 1; height: 1 }
    function dockBgAnchorAt(mx, my) {
        dockBgAnchorItem.x = mx
        dockBgAnchorItem.y = my
        return dockBgAnchorItem
    }

    // ── Menu state (phase 3) ─────────────────────────────────────────────
    // kind: "" | "app" | "picker" | "background" | "start"
    property string _menuKind: ""
    property var    _menuApp: null     // dockModel entry for app/picker
    property real   _menuAX: 0         // anchor point, dock-window coords
    property real   _menuAY: 0
    property bool   _menuVisible: false
    property bool   _trashDlg: false

    function _openMenu(kind, app, item) {
        dock._menuKind = kind
        dock._menuApp = app ?? null
        const p = item.mapToItem(dock.contentItem, item.width / 2, item.height / 2)
        dock._menuAX = p.x
        dock._menuAY = p.y
        dock._menuVisible = true
        dock._tipVisible = false
        _menuDismissTimer.restart()
    }
    function _hideMenu() {
        dock._menuVisible = false
        dock._menuKind = ""
        dock._menuApp = null
        dock._closeSide()
    }
    // Position section is shared by the dock-background AND the start-badge
    // menus (directional dock-pos buttons + Control Center). Auto-hide /
    // reserve / hide-dock live in the Control Center Dock tab instead, and
    // the hyprviz toggle is gone (hyprviz now uses the new Hyprland lua).
    readonly property bool _posMenu: _menuKind === "background" || _menuKind === "start"

    // ── Secondary (side) hover menu — GJS side-popover parity ────────────
    // mode: "" | "instance" (per-window actions + move-to-ws)
    //       | "launch"      (open-on-ws for _sideApp, optional GPU env)
    property string _sideMode: ""
    property var    _sideTl:  null
    property var    _sideApp: null
    property var    _sideEnv: null
    property bool   _sideVisible: false
    property real   _sideAY: 0        // screen-space row centre y

    function _openSide(mode, tl, app, env, rowItem) {
        dock._sideMode = mode
        dock._sideTl = tl ?? null
        dock._sideApp = app ?? null
        dock._sideEnv = env ?? null
        // Rows live inside menuWin; its screen pos is the (top-left) margins.
        // mapToItem needs a QQuickItem — PanelWindow itself throws TypeErrors.
        const p = rowItem.mapToItem(menuWin.contentItem, rowItem.width, rowItem.height / 2)
        dock._sideAY = menuWin.sy + p.y
        dock._sideVisible = true
        _sideDismissTimer.restart()
    }
    function _closeSide() {
        dock._sideVisible = false
        dock._sideMode = ""
        dock._sideTl = null
        dock._sideApp = null
        dock._sideEnv = null
    }
    Timer {
        id: _sideDismissTimer
        interval: 350
        repeat: false
        onTriggered: {
            if (!dock._sideVisible) return
            if (sideHover.hovered || menuHover.hovered) _sideDismissTimer.restart()
            else dock._closeSide()
        }
    }

    // GPU + workspace-targeted launch (focus ws, +50 ms env launch).
    property var _gpuWsApp: null
    property var _gpuWsEnv: null
    Timer {
        id: _gpuWsTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (dock._gpuWsApp) dock._launchOnGpu(dock._execLine(dock._gpuWsApp)
                                                  || dock._gpuWsApp.exec || dock._gpuWsApp.id,
                                                  dock._gpuWsEnv ?? {})
            dock._gpuWsApp = null
            dock._gpuWsEnv = null
        }
    }
    function _launchOnGpuWs(app, envObj, wsNum) {
        dock._hlDispatch("hl.dsp.focus({ workspace = " + wsNum + " })")
        dock._gpuWsApp = app
        dock._gpuWsEnv = envObj
        _gpuWsTimer.restart()
    }

    // ── Hover tooltip (GJS set_tooltip_text parity) ──────────────────────
    property bool   _tipVisible: false
    property string _tipText: ""
    property real   _tipSX: 0         // screen-space button centre
    property real   _tipSY: 0
    property Item   _tipBtn: null

    function _setTip(btn, on) {
        if (on && !dock._isDragging && !dock._menuVisible) {
            dock._tipBtn = btn
            _tipTimer.restart()
        } else {
            if (dock._tipBtn === btn) _tipTimer.stop()
            if (!on && dock._tipBtn === btn) dock._tipVisible = false
        }
    }

    Timer {
        id: _tipTimer
        interval: 300
        repeat: false
        onTriggered: {
            const b = dock._tipBtn
            if (!b || !b.hovered || dock._menuVisible || dock._isDragging) return
            // Badges expose a precomputed tipText; app buttons derive from
            // the window list (name + instance count).
            if (b.tipText !== undefined) {
                dock._tipText = b.tipText
            } else {
                const n = String(b.app.name ?? "")
                dock._tipText = b.instances.length > 1 ? n + " (" + b.instances.length + ")" : n
            }
            const p = b.mapToItem(dock.contentItem, b.width / 2, b.height / 2)
            dock._tipSX = dock.originX + p.x
            dock._tipSY = dock.originY + p.y
            if (dock._tipText !== "") dock._tipVisible = true
        }
    }

    // Shared icon resolution chain (buttons + picker rows):
    // desktop-entry icon → desktopId → class variants → theme → live
    // tiered matcher → /usr/share/pixmaps map.
    function _iconSource(a) {
        const base = String(a.icon || "")
        if (base.startsWith("/")) return base
        const cands = [base]
        const d = String(a.desktopId || "").replace(/\.desktop$/, "")
        if (d) cands.push(d)
        const id = String(a.id || "")
        if (id) {
            const parts = id.split(".")
            const last = parts[parts.length - 1]
            const last2 = parts.length >= 2 ? parts.slice(-2).join("-") : last
            cands.push(id, id.toLowerCase(), last, last.toLowerCase(),
                       last2, last2.toLowerCase())
            // kitty-scratchpad / foo-gtk3 style variants → base name
            const stripped = id.replace(/-(gtk3?|adwaita|qt5?|scratchpad|browser)$/, "")
            if (stripped && stripped !== id) cands.push(stripped, stripped.toLowerCase())
        }
        for (const c of cands) {
            if (!c) continue
            const p = Quickshell.iconPath(c, true)
            if (p) return p
        }
        // PinnedAppsState may cache an early failed lookup — rerun the
        // tiered matcher live (last resort, linear scan) before giving up.
        const lid = String(a.desktopId || a.id || "")
        if (lid) {
            const e2 = DesktopPinnedState._findEntry(lid)
            const ei = String((e2 && e2.icon) || "")
            if (ei.startsWith("/")) return ei
            if (ei) {
                const p = Quickshell.iconPath(ei, true)
                if (p) return p
                const pp = dock._pixmapIcons[ei.toLowerCase()]
                if (pp) return pp
            }
        }
        const pm = dock._pixmapIcons
        for (const c of cands) {
            if (!c) continue
            const p = pm[c.toLowerCase()]
            if (p) return p
        }
        // Steam shortcuts live on ~/Desktop (outside XDG app dirs) so the tiers
        // above never see them; consult the boot-time scan map keyed by the
        // lowercase desktop basename we pin Steam games by.
        const sm = dock._steamIcons
        for (const key of [String(a.class || "").toLowerCase(),
                           String(a.id || "").toLowerCase(),
                           base.toLowerCase()]) {
            const f = sm[key]
            if (!f) continue
            if (f.startsWith("/")) return f
            const p = Quickshell.iconPath(f, true)
            if (p) return p
            const pp = pm[f.toLowerCase()]
            if (pp) return pp
        }
        return ""
    }

    // ── Hyprland window actions (dock-main.js / daemon.js parity) ────────
    // Lua-style dispatches go through hyprctl exactly like the GJS daemon —
    // Quickshell's Hyprland.dispatch mangles the brace arguments, which
    // silently breaks focus / move / minimize.
    function _hlDispatch(cmd) {
        Quickshell.execDetached(["hyprctl", "dispatch", cmd])
    }

    function _wsName(tl) { return tl && tl.workspace ? String(tl.workspace.name) : "" }
    // Robust against both plain and special-workspace naming.
    function _isMin(tl) {
        const w = dock._wsName(tl)
        return w === "hidden" || w === "special:hidden"
    }
    // Quickshell exposes toplevel addresses WITHOUT the 0x prefix — hyprland
    // address: lookups need the full form, else every window op silently
    // resolves to nothing ("window not found").
    function _addr(a) {
        const s = String(a ?? "")
        if (s === "") return ""
        return s.startsWith("0x") ? s : "0x" + s
    }
    function _titleOf(tl) {
        return (tl && tl.lastIpcObject && tl.lastIpcObject.title) || (tl && tl.title) || ""
    }
    function _minimizeAddr(a) {
        dock._hlDispatch("hl.dsp.window.move({ window = 'address:" + dock._addr(a)
            + "', workspace = 'name:hidden', silent = true, follow = false })")
    }
    // Restore = move to current ws, THEN focus. The focus dispatch is
    // serialised behind a short timer: two back-to-back async hyprctl
    // spawns can reorder, and a focus that wins the race drags the view
    // onto the hidden workspace instead of bringing the window back.
    property string _restorePendingAddr: ""
    Timer {
        id: _restoreFocusTimer
        interval: 80
        repeat: false
        onTriggered: {
            if (dock._restorePendingAddr !== "")
                dock._hlDispatch("hl.dsp.focus({ window = 'address:" + dock._restorePendingAddr + "' })")
            dock._restorePendingAddr = ""
        }
    }
    function _restoreAddr(a) {
        const addr = dock._addr(a)
        dock._hlDispatch("hl.dsp.window.move({ window = 'address:" + addr + "', workspace = 'e+0' })")
        dock._restorePendingAddr = addr
        _restoreFocusTimer.restart()
    }
    function _closeAddr(a) {
        dock._hlDispatch("hl.dsp.window.close({ window = 'address:" + dock._addr(a) + "' })")
    }
    function _floatAddr(a) {
        dock._hlDispatch("hl.dsp.window.float({ window = 'address:" + dock._addr(a) + "', action = 'toggle' })")
    }
    function _fullscreenAddr(a) {
        dock._hlDispatch("hl.dsp.window.fullscreen({ window = 'address:" + dock._addr(a) + "', action = 'toggle' })")
    }
    function _moveWsAddr(a, n) {
        dock._hlDispatch("hl.dsp.window.move({ window = 'address:" + dock._addr(a) + "', workspace = " + n + " })")
    }
    function _focusAddr(a) {
        dock._hlDispatch("hl.dsp.focus({ window = 'address:" + dock._addr(a) + "' })")
    }
    function _raiseToplevel(tl) {
        if (!tl || !tl.address) return
        if (dock._isMin(tl)) dock._restoreAddr(tl.address)
        else dock._focusAddr(tl.address)
    }

    // ── dGPU list via switcheroo DBus (identical to DesktopLayer) ────────
    property var _gpuList: []
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
            "    bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)\n" +
            "    r = bus.call_sync(" +
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
            try { dock._gpuList = JSON.parse(_gpuProc._buf) } catch (_) { dock._gpuList = [] }
            dock._gpuReady = true
        }
    }

    function _abbrevGpu(name) {
        return String(name)
            .replace(/^Advanced Micro Devices,?\s*Inc\.?\s*\[AMD\/ATI\]\s*/i, "")
            .replace(/^NVIDIA\s+Corporation\s*/i, "")
            .replace(/^Intel\s+Corporation\s*/i, "")
            .slice(0, 32)
    }

    function _launchOnGpu(exec, envObj) {
        if (!exec || exec === "") return
        const clean = String(exec).replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
        let envStr = ""
        for (const [k, v] of Object.entries(envObj ?? {}))
            envStr += k + "=" + v + " "
        launchProc._cmd = "env " + envStr + clean + " &"
        launchProc.running = true
    }

    // ── Workspace-targeted launch (GJS: focus ws, +50 ms exec_cmd rule) ──
    property string _wsPendingExec: ""
    property int    _wsPendingWs: 0

    Timer {
        id: _wsLaunchTimer
        interval: 50
        repeat: false
        onTriggered: {
            if (dock._wsPendingExec === "") return
            dock._hlDispatch("hl.dsp.exec_cmd('" + dock._wsPendingExec +
                "', { workspace = " + dock._wsPendingWs + " })")
            dock._wsPendingExec = ""
            dock._wsPendingWs = 0
        }
    }

    function _openOnWs(app, wsNum) {
        const exec = dock._execLine(app) || String(app.exec || app.id || "").replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
        if (exec === "") return
        dock._hlDispatch("hl.dsp.focus({ workspace = " + wsNum + " })")
        dock._wsPendingExec = exec.replace(/'/g, "")
        dock._wsPendingWs = wsNum
        _wsLaunchTimer.restart()
    }

    function _startClicked() {
        if (!LicenseState.activated) return
        HCCLauncherState.toggle()
    }

    // GJS click semantics: 0 → launch, 1 → focus/restore, >1 → picker.
    function _buttonClicked(app, item) {
        const inst = clientsFor(app.id)
        if (inst.length === 0) {
            _launch(app)
            return
        }
        if (inst.length === 1) {
            // GJS parity: restore-if-minimized else focus. No "already
            // front" shortcut — activated stays true across workspaces,
            // which made cross-workspace dispatches a no-op.
            _raiseToplevel(inst[0])
            return
        }
        dock._openMenu("picker", app, item)
    }

    function _trashBadgeClicked() {
        TrashState.refresh()
        if (TrashState.count > 0) dock._trashDlg = true
    }

    // ── Drag-reorder state (pinned apps only) ───────────────────────────
    property var    _dragBtn: null     // DockAppButton being dragged
    property string _dragId: ""        // pinned id under drag
    property int    _dropIdx: -1       // insertion index within pinned subset
    property bool   _isDragging: false
    property bool   _dragConsumed: false

    function _pinnedIds() {
        const ids = []
        for (const a of dock.dockModel) if (a.pinned) ids.push(a.id)
        return ids
    }

    function _beginDrag(btn) {
        if (!btn.app.pinned) return
        dock._dragBtn = btn
        dock._dragId = btn.app.id
        dock._isDragging = true
        dock._tipVisible = false
        dock._dropIdx = btn._pinIdx >= 0 ? btn._pinIdx : 0
    }

    // pointerAlong: drag pointer coordinate along the strip axis (dock coords).
    function _updateDrop(pointerAlong) {
        if (!dock._isDragging) return
        const ids = dock._pinnedIds()
        let idx = 0
        const items = dock._repeaterItems()
        for (let i = 0; i < items.length; i++) {
            const it = items[i]
            if (!it || !it.app || !it.app.pinned || it === dock._dragBtn) continue
            const p = it.mapToItem(dock.contentItem, it.width / 2, it.height / 2)
            const along = dock.isHorizontal ? p.x : p.y
            if (along < pointerAlong && it._pinIdx + 1 > idx) idx = it._pinIdx + 1
        }
        dock._dropIdx = Math.max(0, Math.min(idx, ids.length))
    }

    function _repeaterItems() {
        const out = []
        const src = dock.isHorizontal ? rowRepeaterH : rowRepeaterV
        const n = src ? src.count : 0
        for (let i = 0; i < n; i++) { const it = src.itemAt(i); if (it) out.push(it) }
        return out
    }

    function _endDrag() {
        if (!dock._isDragging) return
        const ids = dock._pinnedIds()
        const from = ids.indexOf(dock._dragId)
        let to = dock._dropIdx
        if (from !== -1 && to > from) to -= 1   // list shrinks when removed
        if (from !== -1 && to !== from) {
            const rest = ids.filter((_, i) => i !== from)
            const afterId = to === 0 ? "" : (rest[to - 1] ?? "")
            PinnedAppsState.reorder(dock._dragId, afterId)
        }
        dock._isDragging = false
        dock._dragConsumed = true
        dock._dragBtn = null
        dock._dragId = ""
        dock._dropIdx = -1
    }

    // ── Auto-hide trio (Bar.qml parity) ─────────────────────────────────
    property bool _ahEnabled: Config.dockAutoHide
    property int  _ahDelaySec: Config.dockAutoHideDelay
    property bool _ahHidden: false
    // One-shot manual hide (start-popup row): unmaps the surface but keeps
    // the shell loaded so the hotspot can reveal it — no re-hide timer.
    property bool _manualHidden: false
    onVisibleChanged: if (dock.visible) dock._manualHidden = false
    readonly property bool anyPanelOpen: ControlCenterState.visible
                                         || HCCLauncherState.visible
                                         || dock._menuVisible
    readonly property bool _fullscreen: {
        const mon = dock.monitor
        return !!(mon && mon.activeWindow && mon.activeWindow.fullscreen)
    }

    Timer {
        id: _ahHideTimer
        interval: dock._ahDelaySec * 1000
        repeat: false
        onTriggered: {
            if (dock._fullscreen) return
            dock._ahHidden = true
        }
    }
    Timer {
        id: _ahAnimExitTimer
        interval: 230
        repeat: false
        onTriggered: { if (dock._ahHidden) dock.visible = false }
    }

    HoverHandler {
        id: _dockHover
        onHoveredChanged: {
            if (!dock._ahEnabled) return
            if (hovered) {
                _ahHideTimer.stop()
                _ahAnimExitTimer.stop()
                if (dock._ahHidden) { dock._ahHidden = false; dock.visible = true }
            } else if (!dock.anyPanelOpen) {
                _ahHideTimer.restart()
            }
        }
    }

    on_AhHiddenChanged: {
        if (!_ahHidden) { dock.visible = true }
        else { _ahAnimExitTimer.restart() }
    }
    on_AhEnabledChanged: {
        if (!_ahEnabled) {
            _ahHideTimer.stop()
            _ahAnimExitTimer.stop()
            dock._ahHidden = false
            dock.visible = true
        } else if (!dock._ahHidden && !dock.anyPanelOpen) {
            _ahHideTimer.restart()
        }
    }
    on_AhDelaySecChanged: {
        if (dock._ahEnabled && !dock._ahHidden && !dock.anyPanelOpen) _ahHideTimer.restart()
    }
    onAnyPanelOpenChanged: {
        if (dock.anyPanelOpen) _ahHideTimer.stop()
        else if (dock._ahEnabled && !dock._ahHidden && !_dockHover.hovered) _ahHideTimer.restart()
    }

    // Menu auto-dismiss: close once the pointer has left both the dock and
    // the menu surface for 400 ms (layer surfaces get no outside-click).
    Timer {
        id: _menuDismissTimer
        interval: 400
        repeat: false
        onTriggered: {
            if (!dock._menuVisible) return
            if (menuHover.hovered || _dockHover.hovered || sideHover.hovered)
                _menuDismissTimer.restart()
            else dock._hideMenu()
        }
    }

    // ── Context menu surface (phase 3) ────────────────────────────────
    // Separate overlay surface so the menu can extend past the dock strip.
    // Layer surfaces get no outside-click, so dismissal is hover-exit
    // timed (_menuDismissTimer) plus explicit hide on every action.
    PanelWindow {
        id: menuWin
        screen: dock.screen
        visible: dock._menuVisible
        color: "transparent"

        WlrLayershell.namespace: "hyprcandy-dock-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        // Anchor-point in screen coords (dock is compact + centred, so its
        // window origin is a live offset).
        readonly property real absX: dock.originX + dock._menuAX
        readonly property real absY: dock.originY + dock._menuAY

        // Actual screen position of this surface (top-left anchored) — the
        // side menu hangs off these (PanelWindow.x/y are unreliable here).
        readonly property real sx: margins.left
        readonly property real sy: margins.top

        implicitWidth: menuCard.implicitWidth
        implicitHeight: menuCard.implicitHeight
        anchors { top: true; left: true }
        // PanelWindow.width/height only update after a compositor roundtrip —
        // sizing margins off them leaves stale values and floats the menu far
        // from the dock, so use the card's implicit size (evaluated now).
        margins {
            left: Math.round(dock.isLeft ? dock.originX + dock.width + 6
                : dock.isRight ? Math.max(4, menuWin.absX - menuCard.implicitWidth - 6)
                : Math.max(4, Math.min(menuWin.absX - menuCard.implicitWidth / 2,
                                       dock.scrW - menuCard.implicitWidth - 4)))
            top: Math.round(dock.isTop ? dock.originY + dock.height + 6
                : dock.isBottom ? Math.max(4, dock.originY - menuCard.implicitHeight - 6)
                : Math.max(4, Math.min(menuWin.absY - menuCard.implicitHeight / 2,
                                       dock.scrH - menuCard.implicitHeight - 4)))
        }

        Rectangle {
            id: menuCard
            width: implicitWidth
            height: implicitHeight
            implicitWidth: dock._posMenu ? 248 : (dock._menuKind === "picker" ? 260 : 200)
            implicitHeight: menuCol.implicitHeight + 16
            color: Theme.cOnSecondary
            radius: 12
            border.width: 1
            border.color: Qt.rgba(Theme.cSecondary.r, Theme.cSecondary.g,
                                  Theme.cSecondary.b, 0.5)

            readonly property var menuInst: dock._menuApp ? dock.clientsFor(dock._menuApp.id) : []
            readonly property var actTl: menuInst.length > 0 ? menuInst[0] : null

            HoverHandler {
                id: menuHover
                onHoveredChanged: {
                    if (hovered) _menuDismissTimer.stop()
                    else if (dock._menuVisible) _menuDismissTimer.restart()
                }
            }

            Column {
                id: menuCol
                x: 8; y: 8
                width: menuCard.width - 16
                spacing: 2

                // ── header (app menu only; picker is a bare row list) ────
                Text {
                    visible: dock._menuKind === "app"
                    width: parent.width
                    text: dock._menuApp ? (dock._menuApp.name ?? "") : ""
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.cPrimary
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 2; bottomPadding: 2
                }
                DockMenuDivider {
                    show: dock._menuKind === "app" && menuCard.menuInst.length > 0
                }

                // ── running: per-instance rows (hover → side actions) ────
                Repeater {
                    // Repeater has no `visible` — the model must be gated
                    // or rows leak into every other menu (GPU rows showed
                    // up in start/picker popups this way).
                    model: (dock._menuKind === "app" || dock._menuKind === "picker")
                           ? menuCard.menuInst : []
                    delegate: DockMenuBtn {
                        id: instRow
                        required property var modelData
                        readonly property bool _isApp: dock._menuKind === "app"
                        readonly property bool _pick: dock._menuKind === "picker"
                        readonly property string _t: dock._titleOf(modelData)
                        // Picker rows carry the GJS anatomy (app icon + short
                        // title + state glyph); app-menu rows keep the
                        // "title (ws|min)" + chevron form.
                        label: _pick
                               ? (_t === "" ? "Window" : (_t.length > 30 ? _t.slice(0, 30) + "…" : _t))
                               : (_t === "" ? "Window" : (_t.length > 24 ? _t.slice(0, 24) + "…" : _t))
                                 + "  (" + (dock._isMin(modelData) ? "min" : "WS " + dock._wsName(modelData)) + ")"
                        iconSrc: _pick && dock._menuApp ? dock._iconSource(dock._menuApp) : ""
                        sub: _pick ? (dock._isMin(modelData) ? "\u21a9" : "\u25b8") : ""
                        chevron: _isApp ? "\u203a" : ""
                        // Side actions only in the right-click app menu —
                        // picker rows just dispatch to the window.
                        onEntered: if (_isApp) dock._openSide("instance", modelData, dock._menuApp, null, instRow)
                        onTriggered: { dock._raiseToplevel(modelData); dock._hideMenu() }
                    }
                }

                // ── app: New Window (hover → open-on-ws side menu) ───────
                DockMenuBtn {
                    id: newWinRow
                    visible: dock._menuKind === "app"
                    label: "New Window"
                    chevron: "\u203a"
                    onEntered: dock._openSide("launch", null, dock._menuApp, null, newWinRow)
                    onTriggered: { if (dock._menuApp) dock._launch(dock._menuApp); dock._hideMenu() }
                }

                // ── app: dGPU launch (switcheroo, hybrid GPUs only) ───
                DockMenuDivider {
                    show: dock._menuKind === "app" && dock._gpuReady && dock._gpuList.length > 0
                }
                Text {
                    visible: dock._menuKind === "app" && dock._gpuReady && dock._gpuList.length > 0
                    width: parent.width
                    text: "Launch on GPU"
                    font.pixelSize: 10
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.6)
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 2; bottomPadding: 2
                }
                Repeater {
                    model: (dock._menuKind === "app" && dock._gpuReady && dock._gpuList.length > 0)
                           ? dock._gpuList : []
                    delegate: DockMenuBtn {
                        id: gpuRow
                        required property var modelData
                        label: dock._abbrevGpu(modelData.name ?? "dGPU")
                        chevron: "\u203a"
                        onEntered: dock._openSide("launch", null, dock._menuApp,
                                                  modelData.env ?? {}, gpuRow)
                        onTriggered: {
                            const a = dock._menuApp
                            if (a) dock._launchOnGpu(dock._execLine(a) || a.exec || a.id,
                                                     modelData.env ?? {})
                            dock._hideMenu()
                        }
                    }
                }

                // ── app: close-all + pin rows ───────────────────────
                DockMenuDivider { show: dock._menuKind === "app" }
                DockMenuBtn {
                    visible: dock._menuKind === "app" && menuCard.menuInst.length > 1
                    label: "Close All Windows"
                    onTriggered: {
                        for (const tl of menuCard.menuInst)
                            if (tl) dock._closeAddr(String(tl.address))
                        dock._hideMenu()
                    }
                }
                DockMenuBtn {
                    visible: dock._menuKind === "app"
                    label: dock._menuApp && PinnedAppsState.isPinned(dock._menuApp.id)
                           ? "Unpin from Dock" : "Pin to Dock"
                    onTriggered: {
                        if (dock._menuApp) PinnedAppsState.togglePin(dock._menuApp.id)
                        dock._hideMenu()
                    }
                }
                DockMenuBtn {
                    visible: dock._menuKind === "app"
                    label: dock._menuApp
                           && DesktopPinnedState._classList.indexOf(dock._menuApp.id) !== -1
                           ? "Unpin from Desktop" : "Pin to Desktop"
                    onTriggered: {
                        const cls = dock._menuApp ? String(dock._menuApp.id) : ""
                        dock._hideMenu()
                        if (cls === "") return
                        if (DesktopPinnedState._classList.indexOf(cls) !== -1)
                            DesktopPinnedState.removeApp(cls)
                        else
                            DesktopPinnedState.addApp(cls)
                    }
                }

                // ── trash badge: open / empty ──────────────────────
                Text {
                    visible: dock._menuKind === "trash"
                    width: parent.width
                    text: TrashState.count > 0 ? "Trash (" + TrashState.count + " items)" : "Trash (empty)"
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.cPrimary
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 2; bottomPadding: 2
                }
                DockMenuDivider { show: dock._menuKind === "trash" }
                DockMenuBtn {
                    visible: dock._menuKind === "trash"
                    label: "Open Trash"
                    onTriggered: {
                        Quickshell.execDetached(["bash", "-c",
                            "xdg-open trash:/// 2>/dev/null || gio open trash:/// 2>/dev/null || nautilus trash:/// &"])
                        dock._hideMenu()
                    }
                }
                DockMenuBtn {
                    visible: dock._menuKind === "trash" && TrashState.count > 0
                    label: "Empty Trash"
                    onTriggered: { dock._hideMenu(); dock._trashDlg = true }
                }

                // ── start badge: no extra rows (position section below) ──

                // ── background + start: pills, Open CC centre, hide last ──
                Text {
                    visible: dock._posMenu
                    width: parent.width
                    text: "Dock Position"
                    font.pixelSize: 10
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.6)
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 2; bottomPadding: 2
                }
                Grid {
                    visible: dock._posMenu
                    width: parent.width
                    columns: 4
                    spacing: 3
                    Repeater {
                        model: ["bottom", "left", "top", "right"]
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool _active: DockState.position === modelData
                            width: (menuCol.width - 9) / 4
                            height: 26
                            radius: 13
                            color: _maPill.containsMouse || _active
                                   ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b,
                                             _active ? 0.30 : 0.15)
                                   : "transparent"
                            border.width: 1
                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                                  Theme.cPrimary.b, 0.25)
                            Text {
                                anchors.centerIn: parent
                                text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                font.pixelSize: 10
                                color: Theme.cPrimary
                            }
                            MouseArea {
                                id: _maPill
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: DockState.setPosition(modelData)
                            }
                        }
                    }
                }
                // No cycle option — the pills above already offer every
                // position directly (CC Dock tab mirrors this).
                DockMenuDivider { show: dock._posMenu }
                DockMenuBtn {
                    visible: dock._posMenu
                    label: "Open Control Center"
                    onTriggered: { dock._hideMenu(); ControlCenterState.visible = true }
                }
                // One-shot manual hide as the bottom row (nearest the dock):
                // unmaps the dock, edge hotspot reveals it again (no re-hide
                // timer — auto-hide stays in the CC).
                DockMenuDivider { show: dock._posMenu }
                DockMenuBtn {
                    visible: dock._posMenu
                    label: dock._manualHidden ? "\u{F0208} Show Dock" : "\u{F0701} Hide Dock"
                    onTriggered: {
                        dock._hideMenu()
                        dock._manualHidden = !dock._manualHidden
                        dock.visible = !dock._manualHidden
                    }
                }
            }
        }
    }
    
    // ── Secondary hover menu surface (GJS side-popover parity) ──────────
    PanelWindow {
        id: sideWin
        screen: dock.screen
        visible: dock._sideVisible && dock._menuVisible
        color: "transparent"
    
        WlrLayershell.namespace: "hyprcandy-dock-menu"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
    
        implicitWidth: sideCard.implicitWidth
        implicitHeight: sideCard.implicitHeight
        anchors { top: true; left: true }
        margins {
            // Hang beside the main card (left of it when the dock sits on
            // the right edge, so the chain never leaves the screen). Implicit
            // sizes — surface width/height are stale until the map lands.
            left: Math.round(dock.isRight
                ? Math.max(4, menuWin.sx - sideCard.implicitWidth - 6)
                : Math.min(dock.scrW - sideCard.implicitWidth - 4, menuWin.sx + menuCard.implicitWidth + 6))
            top: Math.round(Math.max(4, Math.min(dock.scrH - sideCard.implicitHeight - 4,
                                                 dock._sideAY - sideCard.implicitHeight / 2)))
        }
    
        Rectangle {
            id: sideCard
            width: implicitWidth
            height: implicitHeight
            implicitWidth: 168
            implicitHeight: sideCol.implicitHeight + 16
            color: Theme.cOnSecondary
            radius: 12
            border.width: 1
            border.color: Qt.rgba(Theme.cSecondary.r, Theme.cSecondary.g,
                                  Theme.cSecondary.b, 0.5)
    
            HoverHandler {
                id: sideHover
                onHoveredChanged: {
                    if (hovered) _sideDismissTimer.stop()
                    else if (dock._sideVisible) _sideDismissTimer.restart()
                }
            }
    
            Column {
                id: sideCol
                x: 8; y: 8
                width: sideCard.width - 16
                spacing: 2
    
                // ── instance variant: window actions + move-to-ws ────
                DockMenuBtn {
                    visible: dock._sideMode === "instance"
                    label: dock._sideTl && dock._isMin(dock._sideTl) ? "Restore" : "Minimize"
                    onTriggered: {
                        const t = dock._sideTl
                        dock._hideMenu()
                        if (!t) return
                        if (dock._isMin(t)) dock._restoreAddr(String(t.address))
                        else dock._minimizeAddr(String(t.address))
                    }
                }
                DockMenuBtn {
                    visible: dock._sideMode === "instance"
                    label: "Close Window"
                    onTriggered: {
                        const t = dock._sideTl
                        dock._hideMenu()
                        if (t) dock._closeAddr(String(t.address))
                    }
                }
                DockMenuBtn {
                    visible: dock._sideMode === "instance"
                    label: "Toggle Floating"
                    onTriggered: {
                        const t = dock._sideTl
                        dock._hideMenu()
                        if (t) dock._floatAddr(String(t.address))
                    }
                }
                DockMenuBtn {
                    visible: dock._sideMode === "instance"
                    label: "Fullscreen"
                    onTriggered: {
                        const t = dock._sideTl
                        dock._hideMenu()
                        if (t) dock._fullscreenAddr(String(t.address))
                    }
                }
                DockMenuDivider { show: dock._sideMode === "instance" }
                Text {
                    visible: dock._sideMode === "instance"
                    width: parent.width
                    text: "Move to Workspace"
                    font.pixelSize: 10
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.6)
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 2; bottomPadding: 2
                }
                Repeater {
                    model: dock._sideMode === "instance" ? 10 : 0
                    delegate: DockMenuBtn {
                        required property int index
                        label: "\u2192 WS " + (index + 1)
                        onTriggered: {
                            const t = dock._sideTl
                            dock._hideMenu()
                            if (t) dock._moveWsAddr(String(t.address), index + 1)
                        }
                    }
                }
    
                // ── launch variant: open on workspace ────────────────
                Text {
                    visible: dock._sideMode === "launch"
                    width: parent.width
                    text: "Open on Workspace"
                    font.pixelSize: 10
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.6)
                    horizontalAlignment: Text.AlignHCenter
                    topPadding: 2; bottomPadding: 2
                }
                Repeater {
                    model: dock._sideMode === "launch" ? 10 : 0
                    delegate: DockMenuBtn {
                        required property int index
                        label: "\u2192 WS " + (index + 1)
                        onTriggered: {
                            const a = dock._sideApp
                            const env = dock._sideEnv
                            const n = index + 1
                            dock._hideMenu()
                            if (!a) return
                            if (env) dock._launchOnGpuWs(a, env, n)
                            else dock._openOnWs(a, n)
                        }
                    }
                }
            }
        }
    }
    
    // ── Hover tooltip surface (minimal name label, popup-facing edge) ────
    PanelWindow {
        id: tipWin
        screen: dock.screen
        visible: dock._tipVisible && !dock._menuVisible && !dock._isDragging
        color: "transparent"
    
        WlrLayershell.namespace: "hyprcandy-dock-tip"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
    
        implicitWidth: tipCard.implicitWidth
        implicitHeight: tipCard.implicitHeight
        anchors { top: true; left: true }
        margins {
            left: Math.round(dock.isLeft  ? dock.originX + dock.width + 8
                : dock.isRight ? Math.max(4, dock.originX - tipCard.implicitWidth - 8)
                : Math.max(4, Math.min(dock._tipSX - tipCard.implicitWidth / 2,
                                       dock.scrW - tipCard.implicitWidth - 4)))
            top: Math.round(dock.isTop    ? dock.originY + dock.height + 8
                : dock.isBottom ? Math.max(4, dock.originY - tipCard.implicitHeight - 8)
                : Math.max(4, Math.min(dock._tipSY - tipCard.implicitHeight / 2,
                                       dock.scrH - tipCard.implicitHeight - 4)))
        }
    
        Rectangle {
            id: tipCard
            implicitWidth: tipLabel.implicitWidth + 20
            implicitHeight: 26
            width: implicitWidth
            height: implicitHeight
            radius: 8
            color: Theme.cOnSecondary
            border.width: 1
            border.color: Qt.rgba(Theme.cSecondary.r, Theme.cSecondary.g,
                                  Theme.cSecondary.b, 0.5)
            Text {
                id: tipLabel
                anchors.centerIn: parent
                text: dock._tipText
                font.pixelSize: 11
                color: Theme.cPrimary
            }
        }
    }

    // Same fallback chain as DesktopLayer._launchEntry.
    // Resolve the desktop entry for a dock app (id/desktopId → byId
    // variants → linear exec-bin scan). Shared by _launch and the
    // exec-line resolution below so GPU / open-on-ws launches use the
    // real entry command, not a bare app id (flatpak ids aren't binaries).
    function _desktopEntry(app) {
        if (app.desktopId && app.desktopId !== "") {
            const e = DesktopEntries.byId(app.desktopId)
            if (e) return e
        }
        const cls = app.id
        const variants = [cls, cls.toLowerCase(),
                          cls.split('.').pop(), cls.split('.').pop().toLowerCase()]
        for (const v of variants) {
            const e = DesktopEntries.byId(v)
            if (e) return e
        }
        const norm = String(cls).toLowerCase()
        const total = DesktopEntries.applications.count
        for (let i = 0; i < total; i++) {
            const e = DesktopEntries.applications.get(i)
            if (!e || !e.execString) continue
            const bin = e.execString.trim().split(/\s+/)[0].split('/').pop().toLowerCase()
            if (bin === norm || bin.startsWith(norm + "-") || bin.endsWith("-" + norm))
                return e
        }
        return null
    }

    // Shell-safe exec line for env/workspace launches (codes stripped).
    function _execLine(app) {
        const e = dock._desktopEntry(app)
        if (e && e.execString)
            return String(e.execString).replace(/%[a-zA-Z]/g, "").trim()
        return String(app.exec || "").replace(/%[a-zA-Z]/g, "").trim()
    }

    function _launch(app) {
        const e = dock._desktopEntry(app)
        if (e) { e.execute(); return }
        if (app.exec && app.exec !== "") {
            launchProc._cmd = app.exec.replace(/%[a-zA-Z]/g, "").trim()
            launchProc.running = true
        }
    }

    // ── TEMP PROBE REMOVED ───────────────────────────────────────────────

    Process {
        id: launchProc
        property string _cmd: ""
        command: ["bash", "-c", launchProc._cmd]
    }

    // ── Auto-hide hotspot (Bar.qml pattern, compact: same along-edge
    //    extent as the island, centred, 2 px strip at the screen edge) ──
    PanelWindow {
        id: dockHotspot
        screen: dock.screen
        readonly property bool _fs: !!(dock.monitor && dock.monitor.activeWindow
                                      && dock.monitor.activeWindow.fullscreen)
        visible: ((dock._ahEnabled && dock._ahHidden) || dock._manualHidden) && !dockHotspot._fs
        color: "transparent"

        WlrLayershell.namespace: "hyprcandy-dock-hotspot"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        anchors {
            top:    dock.isTop    || dock.isLeft || dock.isRight
            bottom: dock.isBottom
            left:   dock.isLeft   || dock.isTop  || dock.isBottom
            right:  dock.isRight
        }
        implicitWidth:  dock.isHorizontal ? dock.width : 2
        implicitHeight: dock.isHorizontal ? 2 : dock.height
        margins {
            top:    dock.isTop    ? 0
                                   : Math.round((dock.scrH - dockHotspot.height) / 2)
            bottom: dock.isBottom ? 0 : 0
            left:   dock.isLeft   ? 0
                                   : Math.round((dock.scrW - dockHotspot.width) / 2)
            right:  dock.isRight  ? 0 : 0
        }

        HoverHandler {
            onHoveredChanged: {
                if (!hovered) return
                if (dock._manualHidden) {
                    // Manual hide is one-shot: reveal and stay put — the
                    // re-hide timer belongs to auto-hide only.
                    dock._manualHidden = false
                    dock.visible = true
                } else if (dock._ahEnabled) {
                    dock._ahHidden = false
                    dock.visible = true
                    // Arm the hide timer immediately: if the pointer never
                    // travels onto the dock, _dockHover never fires, so this
                    // restart is what makes the dock re-hide (GJS parity).
                    if (!dock.anyPanelOpen) _ahHideTimer.restart()
                }
            }
        }
    }

    // ── Trash confirm dialog ──────────────────────────────────────────
    TrashDialog {
        screen: dock.screen
        visible: dock._trashDlg
        onDismissed: dock._trashDlg = false
    }

    // ── Sub-components ─────────────────────────────────────────────────────

    // Start / trash badge: cSurfaceTint (or island-gradient stops) circle,
    // cOnSecondary glyph, island border (dock-main.js badge parity).
    component DockBadge: Rectangle {
        id: badge
        required property string kind
        required property string glyph
        property string tipText: ""
        readonly property bool hovered: hover.hovered
        signal clicked
        signal rightClicked

        readonly property real iconD: dock.buttonSize - 2 * dock.dockPadding
        width: iconD + 2 * dock.dockPadding
        height: width
        radius: 999
        color: Config.islandBgStyle === "gradient" ? "transparent" : Theme.cSurfaceTint
        border.width: Config.islandBorder
        border.color: Qt.rgba(Config.islandBorderColor.r, Config.islandBorderColor.g,
                              Config.islandBorderColor.b, Config.islandBorderAlpha)
        opacity: hover.hovered ? 0.45 : 1.0
        Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            visible: Config.islandBgStyle === "gradient"
            gradient: Gradient {
                orientation: dock.isHorizontal ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0.0;  color: Theme.cInversePrimary }
                GradientStop { position: 0.35; color: Theme.cSurfaceTint }
                GradientStop { position: 0.7;  color: Theme.cSurfaceTint }
                GradientStop { position: 1.0;  color: Theme.cInversePrimary }
            }
        }

        Text {
            anchors.centerIn: parent
            text: badge.glyph
            color: Theme.cOnSecondary
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(badge.iconD * 0.62)
        }
        HoverHandler { id: hover; onHoveredChanged: dock._setTip(badge, hovered) }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) badge.rightClicked()
                else badge.clicked()
            }
        }
    }

    // App icon button with active-window indicator dots, right-click menu
    // signal and press-and-hold drag-reorder (pinned entries only).
    component DockAppButton: Item {
        id: btn
        required property var app
        required property var instances
        property bool vertical: false
        signal activated
        signal menuRequested
        readonly property bool hovered: hover.hovered

        readonly property real iconSize: dock.buttonSize - 2 * dock.dockPadding
        width: iconSize + 2 * dock.dockPadding
        height: width   // square; indicator dots overlay the screen-facing edge

        // Slot within the pinned subset (-1 → running-unpinned button).
        readonly property int _pinIdx: dock._pinnedIds().indexOf(btn.app.id)
        property bool _dragArmed: false
        property point _pressPos

        // Drop-indicator edge logic: _dropIdx is an insertion point in the
        // pinned id list; show before this button when it matches its slot,
        // after the last pinned button when the insertion point is the end.
        readonly property bool _dropBefore: dock._isDragging && dock._dragBtn !== btn
            && btn.app.pinned && dock._dropIdx === btn._pinIdx
        readonly property bool _dropAfter: dock._isDragging && dock._dragBtn !== btn
            && btn.app.pinned && dock._dropIdx === dock._pinnedIds().length
            && btn._pinIdx === dock._pinnedIds().length - 1

        opacity: hover.hovered ? 0.45 : 1.0
        Behavior on opacity { NumberAnimation { duration: Config.hoverDuration } }

        Image {
            id: icon
            anchors.centerIn: vertical ? undefined : parent
            anchors.top: vertical ? parent.top : undefined
            anchors.horizontalCenter: vertical ? parent.horizontalCenter : undefined
            width: btn.iconSize
            height: btn.iconSize
            fillMode: Image.PreserveAspectFit
            sourceSize: Qt.size(btn.iconSize, btn.iconSize)
            // Candidate chain lives in dock._iconSource (shared with picker).
            source: dock._iconSource(btn.app)
            asynchronous: true
        }

        // Fallback nerd-font glyph (U+F165D) when there is no icon —
        // surface-tint coloured at the SAME factor the start/trash DockBadge
        // glyphs use (iconD * 0.62), so the ghost reads at scale 1 beside those
        // badges instead of towering over them (1.0 was app-icon sized).
        Text {
            visible: icon.status !== Image.Ready
            anchors.centerIn: icon
            text: "\u200a\u200a\u200a\u200a\u{F165D}\u200a\u200a\u200a\u200a"
            color: Theme.cSurfaceTint
            font.family: Theme.fontFamily
            font.pixelSize: Math.round(btn.iconSize * 0.62)
        }

        // Indicator dots: radius 2.5, gap 2, max 2, cSurfaceTint. Placed
        // just OUTSIDE the button face on the screen-facing side (inside the
        // island's inner-padding ring) — flush past the start/trash badge
        // edges so they read clearly separated from the icons. Plain x/y
        // bindings: conditional anchor targets are not settable in QML.
        Row {
            id: dotRow
            spacing: 2
            visible: !btn.vertical && btn.instances.length > 0
            x: (btn.width - width) / 2
            y: dock.isTop ? -2 - height : btn.height + 2
            Repeater {
                model: Math.min(2, btn.instances.length)
                Rectangle {
                    width: 5; height: 5; radius: 2.5
                    color: Theme.cSurfaceTint
                }
            }
        }
        Column {
            id: dotCol
            spacing: 2
            visible: btn.vertical && btn.instances.length > 0
            y: (btn.height - height) / 2
            x: dock.isLeft ? -2 - width : btn.width + 2
            Repeater {
                model: Math.min(2, btn.instances.length)
                Rectangle { width: 5; height: 5; radius: 2.5; color: Theme.cSurfaceTint }
            }
        }

        HoverHandler {
            id: hover
            onHoveredChanged: dock._setTip(btn, hovered)
        }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            // Drag arms on a >12 px left-press move (NOT pressAndHold —
            // that swallows clicked, so slow clicks never launched nor
            // opened menus).
            onPressed: function(mouse) {
                dock._dragConsumed = false
                btn._dragArmed = mouse.button === Qt.LeftButton && btn.app.pinned
                btn._pressPos = Qt.point(mouse.x, mouse.y)
                dock._setTip(btn, false)
            }
            onPositionChanged: function(mouse) {
                if (btn._dragArmed && !dock._isDragging) {
                    const d = Math.abs(mouse.x - btn._pressPos.x)
                              + Math.abs(mouse.y - btn._pressPos.y)
                    if (d > 12) {
                        btn._dragArmed = false
                        dock._beginDrag(btn)
                    }
                }
                if (!dock._isDragging || dock._dragBtn !== btn) return
                if (!(mouse.buttons & Qt.LeftButton)) return
                const p = btn.mapToItem(dock.contentItem, mouse.x, mouse.y)
                dock._updateDrop(dock.isHorizontal ? p.x : p.y)
            }
            onReleased: {
                btn._dragArmed = false
                if (dock._isDragging && dock._dragBtn === btn) dock._endDrag()
            }
            onCanceled: {
                btn._dragArmed = false
                if (dock._isDragging && dock._dragBtn === btn) {
                    dock._isDragging = false
                    dock._dragBtn = null
                    dock._dropIdx = -1
                }
            }
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    btn.menuRequested()
                } else {
                    if (dock._dragConsumed) { dock._dragConsumed = false; return }
                    btn.activated()
                }
            }
        }

        // Drag drop-indicator: cPrimary line on the insertion edge.
        Rectangle {
            visible: btn._dropBefore || btn._dropAfter
            color: Theme.cPrimary
            radius: 1
            width:  dock.isHorizontal ? 2 : btn.width
            height: dock.isHorizontal ? btn.height : 2
            x: dock.isHorizontal ? (btn._dropBefore ? -3 : btn.width + 1) : 0
            y: dock.isHorizontal ? 0 : (btn._dropBefore ? -3 : btn.height + 1)
        }
    }

    // Menu row button — DesktopLayer DeskMenuBtn recipe at dock-menu scale,
    // left-aligned label + optional submenu chevron; entered() drives the
    // GJS-style hover side-menu.
    component DockMenuBtn: Rectangle {
        id: _dmb
        property string label: ""
        property string chevron: ""
        property string iconSrc: ""
        property string sub: ""
        signal triggered()
        signal entered()
        width: parent ? parent.width : 200
        height: Math.max(_dmbLabel.implicitHeight, _dmbIcon.visible ? 16 : 0) + 9
        radius: 6
        color: _dmbMa.containsMouse
               ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
               : "transparent"
        Behavior on color { ColorAnimation { duration: 80 } }
        Image {
            id: _dmbIcon
            visible: source !== ""
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 16; height: 16
            fillMode: Image.PreserveAspectFit
            source: _dmb.iconSrc
            asynchronous: true
        }
        Text {
            id: _dmbLabel
            anchors.left: _dmbIcon.visible ? _dmbIcon.right : parent.left
            anchors.right: _dmbSub.left
            anchors.leftMargin: _dmbIcon.visible ? 6 : 10
            anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: _dmb.label
            font.pixelSize: 11
            color: Theme.cPrimary
            elide: Text.ElideRight
        }
        Text {
            id: _dmbSub
            visible: text !== ""
            anchors.right: _dmbChev.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            text: _dmb.sub
            font.pixelSize: 10
            color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.65)
        }
        Text {
            id: _dmbChev
            visible: text !== ""
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: _dmb.chevron
            font.pixelSize: 12
            color: Theme.cPrimary
        }
        MouseArea {
            id: _dmbMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: _dmb.entered()
            onClicked: _dmb.triggered()
        }
    }

    component DockMenuDivider: Rectangle {
        property bool show: true
        visible: show
        width: parent ? parent.width : 200
        height: show ? 1 : 0
        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.2)
    }
}
