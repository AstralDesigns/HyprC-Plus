import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  AppImagesTab.qml — launcher "AppImages" sub-tab (Apps | Groups | Packages |
//  AppImages).
//
//  Lists portable AppImage files discovered on disk (scripts/appimage-scan.sh)
//  and offers per-file actions through scripts/appimage-action.sh — all of them
//  user-level (no privilege):
//    • launch                         run the file (sets a new session)
//    • make / remove executable bit
//    • add / remove .desktop integration (per-user menu entry)
//    • move to ~/.Applications        organised home for the tab's AppImages
//    • open containing folder
//  The scan is cheap and local, so the shared search field filters the cached
//  list instantly (no subprocess per keystroke); it is re-run after any action.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: aiRoot

    property string query: ""

    property var records: []           // [{name,version,path,size,exe,integrated,icon}]
    property bool scanning: false
    property bool busy: false          // an action is running
    property string error: ""
    property bool _everScanned: false

    // Row context menu state.
    property var ctxMenu: ({ open: false, x: 0, y: 0, rec: null })

    // What the list shows: the whole cached set, or a name/path filter.
    readonly property var apps: {
        const q = query.trim().toLowerCase()
        if (q === "") return records
        return records.filter(r =>
            String(r.name).toLowerCase().includes(q)
            || String(r.path || "").toLowerCase().includes(q))
    }

    // Real home, resolved the same way PackagesIndex does (url -> path).
    readonly property string home: StandardPaths.writableLocation(StandardPaths.HomeLocation)
        .toString().replace(/^file:\/\//, "")

    function dirOf(p) {
        const i = String(p).lastIndexOf("/")
        return i > 0 ? String(p).substring(0, i) : "/"
    }
    function inHomeAppDir(r) {
        return String(r.path).startsWith(home + "/.Applications/")
    }

    // Best-effort icon: an integrated entry ships its themed Icon name; else the
    // generic package glyph.
    function iconFor(r) {
        if (r.icon) {
            const p = Quickshell.iconPath(String(r.icon), true)
            if (p) return p
        }
        return ""
    }

    function runScan() {
        if (scanProc.running) return
        scanning = true
        error = ""
        scanProc.running = false
        scanProc.running = true
    }

    // Dispatch a per-file action. `reveal` and `launch` don't mutate the tree in
    // a way the scan reports, so they skip the rescan; everything else refreshes.
    function dispatch(verb, r) {
        if (!r) return
        ctxMenu = ({ open: false, x: 0, y: 0, rec: null })
        if (verb === "reveal") {
            revealProc._dir = dirOf(r.path)
            revealProc.running = false
            revealProc.running = true
            return
        }
        if (busy) return
        busy = true
        actProc._verb = verb
        actProc._path = String(r.path)
        actProc._name = String(r.name || "")
        actProc._ver = String(r.version || "")
        actProc.running = false
        actProc.running = true
    }

    // Context menu rows for a record (dynamic on exe / integration state).
    function menuFor(r) {
        if (!r) return []
        const m = []
        m.push({ verb: "launch", text: "Launch" })
        m.push({ verb: r.exe ? "chmod-off" : "chmod-on",
                 text: r.exe ? "Remove executable bit" : "Make executable" })
        m.push({ verb: r.integrated ? "unintegrate" : "integrate",
                 text: r.integrated ? "Remove menu integration" : "Add menu integration" })
        if (!inHomeAppDir(r)) m.push({ verb: "move", text: "Move to ~/.Applications" })
        m.push({ verb: "reveal", text: "Open folder" })
        return m
    }

    // ── Scan process ──────────────────────────────────────────────────────────
    Process {
        id: scanProc
        command: ["bash", Config.barDir + "/scripts/appimage-scan.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    aiRoot.records = Array.isArray(d) ? d : []
                } catch (e) {
                    aiRoot.records = []
                    aiRoot.error = "Could not read AppImage list"
                }
            }
        }
        onExited: function (code) {
            aiRoot.scanning = false
            aiRoot._everScanned = true
            if (code !== 0 && aiRoot.error === "")
                aiRoot.error = "AppImage scan failed"
        }
    }

    // ── Action process (serialized; one at a time) ────────────────────────────
    Process {
        id: actProc
        property string _verb: ""
        property string _path: ""
        property string _name: ""
        property string _ver: ""
        command: ["bash", Config.barDir + "/scripts/appimage-action.sh",
                  _verb, _path, _name, _ver]
        onExited: function (code) {
            aiRoot.busy = false
            // Any state-changing verb refreshes the cached list.
            runScan()
        }
    }

    // ── Reveal (open containing folder) ───────────────────────────────────────
    Process {
        id: revealProc
        property string _dir: ""
        command: ["bash", "-c", "xdg-open '" + _dir.replace(/'/g, "'\\''") + "' >/dev/null 2>&1"]
    }

    onVisibleChanged: if (visible) {
        if (!_everScanned || records.length === 0) runScan()
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 2
        spacing: 6

        // Header bar: count + refresh
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            spacing: 8

            Text {
                text: aiRoot.apps.length + (aiRoot.apps.length === 1 ? " appimage" : " appimages")
                font.pixelSize: 11
                color: Theme.cOnSurf
                opacity: 0.75
            }

            Item { Layout.fillWidth: true }

            Rectangle {
                Layout.preferredHeight: 28
                Layout.preferredWidth: rfRow.implicitWidth + 22
                radius: 9
                enabled: !aiRoot.scanning && !aiRoot.busy
                opacity: enabled ? 1.0 : 0.45
                color: rfMa.containsMouse ? Theme.cPrimaryContainer
                                          : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                border.width: 1
                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.4)
                Behavior on color { ColorAnimation { duration: 120 } }
                Row {
                    id: rfRow
                    anchors.centerIn: parent
                    spacing: 6
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u{F0221}"   // refresh
                        font.family: Theme.fontFamily
                        font.pixelSize: 13
                        color: Theme.cPrimary
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: aiRoot.scanning ? "Scanning…" : "Rescan"
                        font.pixelSize: 11
                        font.bold: true
                        color: Theme.cPrimary
                    }
                }
                MouseArea {
                    id: rfMa
                    anchors.fill: parent
                    enabled: parent.enabled
                    hoverEnabled: true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: aiRoot.runScan()
                }
            }
        }

        // Busy hint
        Text {
            Layout.fillWidth: true
            visible: aiRoot.busy
            text: "\u{F04B3} Applying…"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Theme.cPrimary
            opacity: 0.85
        }

        // List
        ListView {
            id: aiList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 2
            boundsBehavior: Flickable.StopAtBounds
            model: aiRoot.apps

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
                readonly property var rec: modelData

                width: aiList.width
                height: 52
                radius: 12
                color: rowMa.containsMouse
                       ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.06)
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 110 } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 10

                    // Icon (image or ghost glyph)
                    Item {
                        Layout.alignment: Qt.AlignVCenter
                        width: 30; height: 30
                        Image {
                            anchors.fill: parent
                            source: aiRoot.iconFor(row.rec)
                            sourceSize: Qt.size(30, 30)
                            asynchronous: true
                            fillMode: Image.PreserveAspectFit
                            smooth: true
                            visible: status === Image.Ready
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: aiRoot.iconFor(row.rec) === ""
                            text: "\u{F04D6}"
                            font.family: Theme.fontFamily
                            font.pixelSize: 22
                            color: Theme.cSurfaceTint
                        }
                    }

                    // Name + path
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 1
                        Text {
                            Layout.fillWidth: true
                            text: row.rec.name
                            font.pixelSize: 12
                            font.bold: true
                            color: Theme.cOnSurf
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.rec.path
                            font.pixelSize: 10
                            color: Qt.alpha(Theme.cOnSurfVar, 0.8)
                            elide: Text.ElideMiddle
                        }
                    }

                    // Version
                    Text {
                        Layout.alignment: Qt.AlignVCenter
                        visible: String(row.rec.version || "").length > 0
                        text: row.rec.version || ""
                        font.pixelSize: 10
                        color: Qt.alpha(Theme.cOnSurfVar, 0.9)
                    }

                    // AppImage chip
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        height: 18
                        width: chipTxt.implicitWidth + 12
                        radius: 9
                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.14)
                        Text {
                            id: chipTxt
                            anchors.centerIn: parent
                            text: "AppImage"
                            font.pixelSize: 9
                            font.bold: true
                            color: Theme.cPrimary
                        }
                    }

                    // State badge: needs exec / integrated / ready
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        height: 18
                        width: badgeTxt.implicitWidth + 12
                        radius: 9
                        readonly property bool _warn: row.rec.exe !== true
                        readonly property bool _int: row.rec.integrated === true
                        color: _warn
                               ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.16)
                               : (_int ? Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.18)
                                       : "transparent")
                        border.width: 1
                        border.color: _warn
                                      ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.4)
                                      : Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.25)
                        Text {
                            id: badgeTxt
                            anchors.centerIn: parent
                            text: !row.rec.exe ? "not executable"
                                 : (row.rec.integrated ? "integrated" : "ready")
                            font.pixelSize: 9
                            color: !row.rec.exe ? Theme.cErr
                                 : (row.rec.integrated ? Theme.cOnSurf
                                                       : Qt.alpha(Theme.cOnSurfVar, 0.7))
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
                            aiRoot.ctxMenu = { open: true, x: mouse.x, y: mouse.y,
                                               rec: row.rec }
                        } else {
                            // Left-click launches; a missing exec bit is set by
                            // the action script before running.
                            aiRoot.dispatch("launch", row.rec)
                        }
                    }
                }
            }

            // Empty / error overlay
            Text {
                anchors.centerIn: parent
                visible: aiRoot.apps.length === 0
                text: aiRoot.error !== "" ? aiRoot.error
                      : aiRoot.scanning ? "Scanning for AppImages…"
                      : (aiRoot.query.trim() === ""
                            ? "No AppImages found in your usual folders"
                            : "No matching AppImages")
                font.pixelSize: 12
                color: Theme.cOnSurf
                opacity: 0.55
            }
        }
    }

    // ── Row context menu ──────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        visible: aiRoot.ctxMenu.open
        onClicked: aiRoot.ctxMenu = ({ open: false, x: 0, y: 0, rec: null })
    }
    Rectangle {
        id: aiCtxCard
        visible: aiRoot.ctxMenu.open && aiRoot.ctxMenu.rec !== null
        width: 208
        height: aiCtxCol.implicitHeight + 10
        x: Math.min(aiRoot.ctxMenu.x, aiRoot.width - width - 6)
        y: Math.min(aiRoot.ctxMenu.y, aiRoot.height - height - 6)
        radius: 12
        color: Theme.cOnSecondary
        border.width: 1
        border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.4)
        Column {
            id: aiCtxCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 5
            spacing: 2
            Repeater {
                model: aiRoot.menuFor(aiRoot.ctxMenu.rec)
                delegate: Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 28
                    radius: 8
                    color: aiCtxMa.containsMouse
                           ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.12)
                           : "transparent"
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        text: modelData.text
                        font.pixelSize: 11
                        color: Theme.cOnSurf
                    }
                    MouseArea {
                        id: aiCtxMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: aiRoot.dispatch(modelData.verb, aiRoot.ctxMenu.rec)
                    }
                }
            }
        }
    }
}
