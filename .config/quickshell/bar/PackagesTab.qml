import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  PackagesTab.qml — launcher "Packages" sub-tab (Apps | Groups | Packages).
//
//  A Material-You browser/searcher over the OS's active package backends:
//    • native  (pacman repos, incl. chaotic-aur)
//    • aur     (paru / yay, search only)
//    • flatpak (Flathub)
//  The tab only lists, searches and multi-selects. Every install / uninstall /
//  update is delegated to a pkexec-driven floating-installer kitty window (the
//  same model as the updater), so no root password is ever handled here.
//
//  Reads `query` (bound to the launcher's shared search field). Data comes from
//  scripts/pkg-query.sh (JSON); actions go through scripts/pkg-action.sh.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: tabRoot

    property string query: ""

    // The query the cached `remote` results correspond to. Used to skip re-running
    // (and killing) the remote search when the tab is re-shown with an unchanged
    // query — that re-run is what lost results across sub-tab switches.
    property string _lastRunQuery: ""
    // Latest query requested while a stream is still running; started on exit
    // (we never kill mid-stream — that raced and corrupted the NDJSON).
    property string _pendingQ: ""

    property var selected: []        // array of selected package records
    property bool busy: false        // a transaction terminal is open
    property string error: ""

    // Remote (repo / AUR / Flathub) search results, merged over the local index.
    property var remote: []
    property bool remoteLoading: false

    // Row context menu state.
    property var ctxMenu: ({ open: false, x: 0, y: 0, rec: null })

    // Persisted installed set (instant; refreshed by PackagesIndex).
    readonly property var index: PackagesIndex.installed

    // What the list shows. Empty query -> the whole installed index. Otherwise
    // the instant local fuzzy matches merged with any remote results, ordered
    // installed-first, then native / AUR / Flathub, then name.
    readonly property var packages: {
        const q = query.trim().toLowerCase()
        if (q === "") return index
        const seen = {}, out = []
        for (const r of localFilter(q).concat(remote)) {
            const k = r.source + ":" + r.name
            if (seen[k]) continue
            seen[k] = 1
            out.push(r)
        }
        const rank = { native: 0, aur: 1, flatpak: 2 }
        return out.sort((a, b) => {
            const ai = a.installed === true ? 0 : 1
            const bi = b.installed === true ? 0 : 1
            if (ai !== bi) return ai - bi
            const ar = rank[a.source] ?? 9, br = rank[b.source] ?? 9
            if (ar !== br) return ar - br
            return String(a.name).toLowerCase() < String(b.name).toLowerCase() ? -1 : 1
        })
    }

    readonly property int _count: selected.length
    readonly property bool _anyNotInstalled: selected.some(r => r.installed !== true)
    readonly property bool _anyInstalled: selected.some(r => r.installed === true)

    function keyOf(r) { return r.source + ":" + r.name }
    function isSelected(r) {
        const k = keyOf(r)
        for (const s of selected) if (keyOf(s) === k) return true
        return false
    }
    function toggle(r) {
        const k = keyOf(r)
        const cur = selected.slice()
        const i = cur.findIndex(s => keyOf(s) === k)
        if (i === -1) cur.push(r)
        else cur.splice(i, 1)
        selected = cur
    }
    function clearSelection() { selected = [] }
    function selectAllShown() {
        const cur = selected.slice()
        for (const r of packages) {
            const k = keyOf(r)
            if (!cur.some(s => keyOf(s) === k)) cur.push(r)
        }
        selected = cur
    }

    // Instant substring filter over the persisted installed index (no subprocess).
    function localFilter(q) {
        const out = []
        for (const r of index) {
            if (String(r.name).toLowerCase().includes(q)
                || String(r.description || "").toLowerCase().includes(q)) out.push(r)
        }
        return out
    }

    // Best-effort icon: flatpak ships its app-id as a themed icon name; native /
    // AUR names often match a desktop entry. "" => caller shows the ghost glyph.
    function iconFor(r) {
        if (r.source === "flatpak" && r.icon) {
            const p = Quickshell.iconPath(String(r.icon), true)
            if (p) return p
        }
        try {
            const e = DesktopEntries.byId(String(r.name))
            if (e && e.icon) {
                const p = Quickshell.iconPath(e.icon, true)
                if (p) return p
            }
        } catch (err) { /* byId throws on miss */ }
        return ""
    }

    function sourceLabel(s) {
        return s === "aur" ? "AUR" : s === "flatpak" ? "Flathub" : "Native"
    }

    // Remote search is only needed for a non-empty query; the installed view is
    // served straight from the persisted index (no subprocess).
    function refresh(force) {
        const q = query.trim()
        if (q === "") {
            remote = []
            remoteLoading = false
            error = ""
            _lastRunQuery = ""
            _pendingQ = ""
            queryProc._acc = []
            queryProc.running = false
            return
        }
        // Re-entering the tab with the same query reuses cached results instead of
        // re-issuing the subprocess (which raced with its own restart and surfaced
        // a spurious failure). `force` re-runs after an install/uninstall tx.
        if (!force && q === _lastRunQuery) return
        // A run is already streaming: don't kill it. Stash the latest query and
        // start it when the current one exits (serialized, race-free).
        if (queryProc.running) { _pendingQ = q; return }
        startSearch(q)
    }

    // Begin a fresh stream for `q`. Clears any prior results/accumulator.
    function startSearch(q) {
        error = ""
        remoteLoading = true
        remote = []
        queryProc._acc = []
        _lastRunQuery = q
        queryProc._q = q
        queryProc.running = true
    }

    // Build the argv group list (native:a,b aur:c flatpak:d) for pkg-action.sh.
    function buildGroups(recs) {
        const g = { native: [], aur: [], flatpak: [] }
        for (const r of recs) if (g[r.source]) g[r.source].push(r.name)
        const parts = []
        if (g.native.length)  parts.push("'native:" + g.native.join(",") + "'")
        if (g.aur.length)     parts.push("'aur:" + g.aur.join(",") + "'")
        if (g.flatpak.length) parts.push("'flatpak:" + g.flatpak.join(",") + "'")
        return parts
    }

    // Launch the privileged transaction in a floating-installer kitty.
    function dispatch(verb, recs) {
        if (busy || recs.length === 0) return
        const parts = buildGroups(recs)
        if (parts.length === 0) return
        const title = verb.charAt(0).toUpperCase() + verb.slice(1)
        dispatchProc._title = "   " + title
        dispatchProc._cmd = "'" + Config.barDir + "/scripts/pkg-action.sh' "
                            + verb + " " + parts.join(" ")
                            + "; echo; read -rn1 -p 'Done — press a key to close'"
        busy = true
        clearSelection()
        ctxMenu = ({ open: false, x: 0, y: 0, rec: null })
        dispatchProc.running = false
        dispatchProc.running = true
    }

    // ── Remote search process (native repo + AUR + Flathub) ──────────────────
    Process {
        id: queryProc
        property string _q: ""
        property var _acc: []          // accumulated records for the current stream
        command: ["bash", Config.barDir + "/scripts/pkg-query.sh", "search", _q]
        // NDJSON: the script streams one JSON array per backend as it finishes.
        // Append each to _acc and republish `remote` so native/AUR render before
        // Flathub lands. `packages` de-dupes + sorts the accumulated set.
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const s = line.trim()
                if (s === "") return
                let d
                try { d = JSON.parse(s) } catch (e) { return }
                if (!Array.isArray(d)) return
                // Capture scroll BEFORE republishing: a full model reassign makes
                // ListView reset to originY=0, snapping the user to the top when a
                // later source (Flathub) lands.
                const prevY = list.contentY
                queryProc._acc = queryProc._acc.concat(d)
                tabRoot.remote = queryProc._acc
                tabRoot.error = ""
                // Re-apply the offset once the view has re-laid out (streaming
                // appends grow the list downward, so the saved offset stays valid;
                // clamp in case the new content is shorter than the viewport).
                if (prevY > 0) {
                    Qt.callLater(function() {
                        list.contentY = Math.max(0,
                            Math.min(prevY, list.contentHeight - list.height))
                    })
                }
            }
        }
        onExited: function(exitCode) {
            running = false
            tabRoot.remoteLoading = false
            // Genuine failure = no records AND non-zero exit, and only while a
            // non-empty query is still the active one (a cleared/empty query that
            // killed the run must not surface an error).
            if (tabRoot.query.trim() !== "" && queryProc._acc.length === 0 && exitCode !== 0)
                tabRoot.error = "Package search failed"
            // Start the latest query typed while this run was in flight.
            if (tabRoot._pendingQ !== "") {
                const pq = tabRoot._pendingQ
                tabRoot._pendingQ = ""
                if (pq !== queryProc._q) tabRoot.startSearch(pq)
            }
        }
    }

    // ── Transaction process (visible elevated terminal) ──────────────────────
    Process {
        id: dispatchProc
        property string _cmd: ""
        property string _title: "Install"
        command: ["kitty", "--class", "floating-installer", "--title", _title,
                  "-e", "bash", "-ic", _cmd]
        onExited: {
            running = false
            tabRoot.busy = false
            PackagesIndex.rescan()   // refresh + persist the installed index
            tabRoot.refresh(true)    // re-run the active remote search after a tx
        }
    }

    // Debounced remote search on typing (local matches are already instant).
    Timer {
        id: debounce
        interval: 300
        repeat: false
        onTriggered: tabRoot.refresh()
    }
    onQueryChanged: debounce.restart()
    onVisibleChanged: if (visible) {
        if (!PackagesIndex.loaded) PackagesIndex.ensureStartupScan()
        refresh()
    }

    // ── Layout ──────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 6

        // Action bar
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 8

            Text {
                text: tabRoot._count > 0
                      ? (tabRoot._count + " selected")
                      : (tabRoot.packages.length + " packages")
                font.pixelSize: 11
                color: Theme.cOnSurf
                opacity: 0.75
            }
            Rectangle {
                visible: tabRoot._count > 0
                Layout.preferredHeight: 20
                Layout.preferredWidth: clrTxt.implicitWidth + 16
                radius: 10
                color: clrMa.containsMouse
                       ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.14)
                       : "transparent"
                border.width: 1
                border.color: Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.3)
                Text {
                    id: clrTxt
                    anchors.centerIn: parent
                    text: "Clear"
                    font.pixelSize: 10
                    color: Theme.cOnSurf
                }
                MouseArea {
                    id: clrMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tabRoot.clearSelection()
                }
            }

            Item { Layout.fillWidth: true }

            // Install / Uninstall / Update pills
            Repeater {
                model: [
                    { verb: "install",   label: "Install",   glyph: "\u{F1464}", enabled: tabRoot._anyNotInstalled },
                    { verb: "uninstall", label: "Uninstall", glyph: "\u{F057}", enabled: tabRoot._anyInstalled },
                    { verb: "update",    label: "Update",    glyph: "\u{F06B0}", enabled: tabRoot._anyInstalled },
                ]
                delegate: Rectangle {
                    id: actBtn
                    required property var modelData
                    Layout.preferredHeight: 28
                    Layout.preferredWidth: actRow.implicitWidth + 22
                    radius: 9
                    enabled: modelData.enabled && !tabRoot.busy
                    opacity: enabled ? 1.0 : 0.4
                    color: modelData.verb === "uninstall"
                           ? (actMa.containsMouse ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.22)
                                                  : Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.14))
                           : (actMa.containsMouse ? Theme.cPrimaryContainer
                                                  : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12))
                    border.width: 1
                    border.color: modelData.verb === "uninstall"
                                  ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.4)
                                  : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                        id: actRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.glyph
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: modelData.verb === "uninstall" ? Theme.cErr : Theme.cPrimary
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.pixelSize: 11
                            font.bold: true
                            color: modelData.verb === "uninstall" ? Theme.cErr : Theme.cPrimary
                        }
                    }
                    MouseArea {
                        id: actMa
                        anchors.fill: parent
                        enabled: actBtn.enabled
                        hoverEnabled: true
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: tabRoot.dispatch(modelData.verb, tabRoot.selected)
                    }
                }
            }
        }

        // Busy hint
        Text {
            Layout.fillWidth: true
            visible: tabRoot.busy
            text: "\u{F04B3} A terminal window is running the transaction — authenticate there."
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.cPrimary
            opacity: 0.85
        }

        // Package list
        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: tabRoot.packages

            // Minimal material-you scrollbar: 3px, translucent primary, overlay,
            // only when the list actually overflows (AsNeeded).
            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 3
                    radius: 2
                    color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                }
                background: Rectangle { color: "transparent" }
            }

            delegate: Rectangle {
                id: row
                required property var modelData
                required property int index
                readonly property string pk: tabRoot.keyOf(modelData)
                readonly property bool sel: tabRoot.isSelected(modelData)

                width: list.width
                height: 52
                radius: 12
                color: sel
                       ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                       : rowMa.containsMouse
                         ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.06)
                         : "transparent"
                border.width: sel ? 1 : 0
                border.color: Theme.cPrimary
                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // Selection checkbox
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        width: 18; height: 18; radius: 5
                        color: row.sel ? Theme.cPrimary : "transparent"
                        border.width: 1
                        border.color: row.sel ? Theme.cPrimary
                                              : Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.5)
                        Text {
                            anchors.centerIn: parent
                            visible: row.sel
                            text: "\u2713"
                            font.pixelSize: 12
                            color: Theme.cOnPrimary
                        }
                    }

                    // Icon (image or ghost glyph)
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        width: 30; height: 30
                        Image {
                            anchors.fill: parent
                            source: tabRoot.iconFor(modelData)
                            sourceSize: Qt.size(30, 30)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: tabRoot.iconFor(modelData) === ""
                            text: "\u{F04D6}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            color: Theme.cSurfaceTint
                        }
                    }

                    // Name + description
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: modelData.name
                            font.pixelSize: 12
                            font.bold: true
                            color: Theme.cOnSurf
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            visible: String(modelData.description || "").length > 0
                            text: modelData.description
                            font.pixelSize: 10
                            color: Qt.alpha(Theme.cOnSurfVar, 0.8)
                            elide: Text.ElideRight
                        }
                    }

                    // Version
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        text: modelData.version || ""
                        font.pixelSize: 10
                        color: Qt.alpha(Theme.cOnSurfVar, 0.9)
                    }

                    // Source chip
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        height: 18
                        width: srcTxt.implicitWidth + 12
                        radius: 9
                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.14)
                        Text {
                            id: srcTxt
                            anchors.centerIn: parent
                            text: tabRoot.sourceLabel(modelData.source)
                            font.pixelSize: 9
                            font.bold: true
                            color: Theme.cPrimary
                        }
                    }

                    // Installed / available badge
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        height: 18
                        width: badgeTxt.implicitWidth + 12
                        radius: 9
                        color: modelData.installed
                               ? Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.18)
                               : "transparent"
                        border.width: 1
                        border.color: modelData.installed
                                      ? Qt.rgba(Theme.cOnSurf.r, Theme.cOnSurf.g, Theme.cOnSurf.b, 0.3)
                                      : Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.25)
                        Text {
                            id: badgeTxt
                            anchors.centerIn: parent
                            text: modelData.installed ? "installed" : "available"
                            font.pixelSize: 9
                            color: modelData.installed ? Theme.cOnSurf
                                                       : Qt.alpha(Theme.cOnSurfVar, 0.7)
                        }
                    }
                }

                MouseArea {
                    id: rowMa
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function (mouse) {
                        if (mouse.button === Qt.RightButton) {
                            tabRoot.ctxMenu = { open: true, x: mouse.x, y: mouse.y,
                                                rec: modelData }
                        } else {
                            tabRoot.toggle(modelData)
                        }
                    }
                }
            }

            // Empty / error overlay
            Text {
                anchors.centerIn: parent
                visible: tabRoot.packages.length === 0
                text: tabRoot.error !== "" ? tabRoot.error
                      : tabRoot.remoteLoading ? "Searching…"
                      : (tabRoot.query.trim() === ""
                            ? (PackagesIndex.scanning ? "Scanning installed packages…"
                                                      : "No installed packages found")
                            : "No matching packages")
                font.pixelSize: 12
                color: Theme.cOnSurf
                opacity: 0.55
            }
        }
    }

    // ── Row context menu (single-package actions) ────────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: tabRoot.ctxMenu.open
        onClicked: tabRoot.ctxMenu = ({ open: false, x: 0, y: 0, rec: null })
    }
    Rectangle {
        id: ctxCard
        visible: tabRoot.ctxMenu.open && tabRoot.ctxMenu.rec !== null
        width: 168
        height: ctxCol.implicitHeight + 10
        x: Math.min(tabRoot.ctxMenu.x, tabRoot.width - width - 6)
        y: Math.min(tabRoot.ctxMenu.y, tabRoot.height - height - 6)
        radius: 12
        color: Theme.cOnSecondary
        border.width: 1
        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.4)
        Column {
            id: ctxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            spacing: 2
            Repeater {
                model: {
                    const r = tabRoot.ctxMenu.rec
                    if (!r) return []
                    const m = []
                    if (r.installed === true) {
                        m.push({ verb: "uninstall", text: "Uninstall" })
                        m.push({ verb: "update", text: "Update" })
                    } else {
                        m.push({ verb: "install", text: "Install" })
                    }
                    return m
                }
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 28
                    radius: 8
                    color: ctxMa.containsMouse
                           ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                           : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: modelData.text
                        font.pixelSize: 11
                        color: modelData.verb === "uninstall" ? Theme.cErr : Theme.cOnSurf
                    }
                    MouseArea {
                        id: ctxMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tabRoot.dispatch(modelData.verb, [tabRoot.ctxMenu.rec])
                    }
                }
            }
        }
    }
}
