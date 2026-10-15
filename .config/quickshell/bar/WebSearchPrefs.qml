import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  WebSearchPrefs.qml — in-card overlay editor for the SearXNG settings.yml.
//
//  A scrim + Material-You card (matugen tokens via Theme) with tabbed
//  sections; each row renders a themed control (enum pills / toggle / stepper
//  / text) for a curated settings.yml key. Saving writes the file through the
//  bundled python helper, restarts the container, and status-toast polls the
//  service back to health. Values are held in a plain JS object mutated via
//  put(); the `rev` counter + comma-trick re-evaluates bindings on edit.
// ═══════════════════════════════════════════════════════════════════════════

Rectangle {
    id: root
    anchors.fill: parent
    color: Qt.rgba(0, 0, 0, 0.72)

    // Emitted when the user asks to close (scrim click / X). Parent connects.
    signal dismissed()

    // ── Paths & service ──────────────────────────────────────────────────
    readonly property string settingsPath: Config.barDir + "/scripts/searxng-settings/settings.yml"
    readonly property string prefsScript:  Config.barDir + "/scripts/searxng_prefs.py"
    readonly property string dockerScript: Config.barDir + "/scripts/hyprcandy-docker.sh"
    readonly property string searxBase: "http://127.0.0.1:8080"

    // ── Reactive value store ─────────────────────────────────────────────
    property var values: ({})
    property int rev: 0
    function val(id) { return (root.rev, root.values[id]) }
    function put(id, v) { root.values[id] = v; root.rev++ }

    property int tab: 0
    property bool busy: false
    property string toast: ""
    property string toastKind: "info"   // info | ok | err

    readonly property var tabs: [
        { name: "General",   glyph: "\u{F01E7}" },
        { name: "Interface", glyph: "\u{F1542}" },
        { name: "Privacy",   glyph: "\u{F0498}" },
        { name: "Plugins",   glyph: "\u{F0675}" },
    ]

    // ── Curated descriptor list (single source of truth) ─────────────────
    // type: enum | bool | int | text; keyed by dotted `path` or plugin `active`.
    readonly property var spec: [
        // General
        { id: "instance_name", col: 0, type: "text", path: "general.instance_name", def: "HyprCandy SearXNG",
          label: "Instance name", hint: "Title shown in the search header." },
        { id: "safe_search", col: 0, type: "enum", path: "search.safe_search", def: 0,
          label: "Safe search", hint: "Filter explicit results.",
          options: [ { v: 0, l: "Off" }, { v: 1, l: "Moderate" }, { v: 2, l: "Strict" } ] },
        { id: "default_lang", col: 0, type: "enum", path: "search.default_lang", def: "",
          label: "Default language", hint: "Preferred result language.",
          options: [ { v: "", l: "Auto" }, { v: "en", l: "English" }, { v: "de", l: "German" },
                     { v: "fr", l: "French" }, { v: "es", l: "Spanish" }, { v: "it", l: "Italian" },
                     { v: "ja", l: "Japanese" }, { v: "zh-CN", l: "Chinese" }, { v: "ru", l: "Russian" },
                     { v: "pt", l: "Portuguese" } ] },
        { id: "autocomplete_min", col: 0, type: "int", path: "search.autocomplete_min", def: 3, min: 1, max: 10,
          label: "Autocomplete after", hint: "Characters typed before suggestions appear." },

        // Interface
        { id: "simple_style", col: 1, type: "enum", path: "ui.theme_args.simple_style", def: "auto",
          label: "Theme", hint: "SearXNG color scheme.",
          options: [ { v: "auto", l: "Auto" }, { v: "light", l: "Light" }, { v: "dark", l: "Dark" }, { v: "black", l: "Black" } ] },
        { id: "center_alignment", col: 1, type: "bool", path: "ui.center_alignment", def: false,
          label: "Center layout", hint: "Center results on the page." },
        { id: "query_in_title", col: 1, type: "bool", path: "ui.query_in_title", def: false,
          label: "Query in title", hint: "Show the search term in the tab title." },
        { id: "results_on_new_tab", col: 1, type: "bool", path: "ui.results_on_new_tab", def: false,
          label: "Results in new tab", hint: "Open results in a new tab." },
        { id: "search_on_category_select", col: 1, type: "bool", path: "ui.search_on_category_select", def: true,
          label: "Search on category", hint: "Re-run the query when a category is chosen." },
        { id: "hotkeys", col: 1, type: "enum", path: "ui.hotkeys", def: "default",
          label: "Keyboard shortcuts", hint: "Navigation scheme.",
          options: [ { v: "default", l: "Default" }, { v: "vim", l: "Vim" } ] },
        { id: "url_formatting", col: 1, type: "enum", path: "ui.url_formatting", def: "pretty",
          label: "Result URL style", hint: "How target links are displayed.",
          options: [ { v: "pretty", l: "Pretty" }, { v: "full", l: "Full" }, { v: "host", l: "Host" } ] },

        // Privacy
        { id: "image_proxy", col: 2, type: "bool", path: "server.image_proxy", def: true,
          label: "Image proxy", hint: "Route result images through the server." },
        { id: "method", col: 2, type: "enum", path: "server.method", def: "GET",
          label: "Request method", hint: "HTTP verb for search requests.",
          options: [ { v: "GET", l: "GET" }, { v: "POST", l: "POST" } ] },
        { id: "limiter", col: 2, type: "bool", path: "server.limiter", def: false,
          label: "Rate limiter", hint: "Throttle requests (enable for public instances)." },

        // Plugins (plugins.<name>.active)
        { id: "p_infscroll", col: 3, type: "bool", plugin: "infinite_scroll", def: false,
          label: "Infinite scroll", hint: "Auto-load more results on reach bottom." },
        { id: "p_unitconv", col: 3, type: "bool", plugin: "unit_converter", def: false,
          label: "Unit converter", hint: "Convert units inline in results." },
        { id: "p_calculator", col: 3, type: "bool", plugin: "calculator", def: true,
          label: "Calculator", hint: "Evaluate math expressions in the result panel." },
        { id: "p_trackerremover", col: 3, type: "bool", plugin: "tracker_url_remover", def: true,
          label: "Tracker remover", hint: "Strip tracking parameters from result links." },
        { id: "p_hostnames", col: 3, type: "bool", plugin: "hostnames", def: false,
          label: "Hostname replace", hint: "Swap result domains for readable names." },
        { id: "p_timezone", col: 3, type: "bool", plugin: "time_zone", def: true,
          label: "Time zone", hint: "Show local time for UTC queries." },
        { id: "p_selfinfo", col: 3, type: "bool", plugin: "self_info", def: true,
          label: "Self info", hint: "Answer \u201Cwho are you\u201D with instance details." },
    ]

    // ── Build the python spec arg (only the relevant path|plugin key) ─────
    function _querySpec() {
        return JSON.stringify(root.spec.map(function (d) {
            var o = { id: d.id, default: d.def }
            if (d.plugin) o.plugin = d.plugin; else o.path = d.path
            return o
        }))
    }
    function _setSpec() {
        return JSON.stringify(root.spec.map(function (d) {
            var o = { id: d.id, value: root.values[d.id], default: d.def }
            if (d.plugin) o.plugin = d.plugin; else o.path = d.path
            return o
        }))
    }

    function load() {
        getProc._spec = root._querySpec()
        getProc.running = false
        getProc.running = true
    }

    function save() {
        if (root.busy) return
        root.busy = true
        root.toast = "Writing settings\u2026"
        root.toastKind = "info"
        setProc._spec = root._setSpec()
        setProc.running = false
        setProc.running = true
    }

    // ── get: read current settings.yml values ────────────────────────────
    Process {
        id: getProc
        property string _spec: "[]"
        command: ["python3", root.prefsScript, "get", root.settingsPath, getProc._spec]
        stdout: StdioCollector {
            onStreamFinished: {
                getProc.running = false
                var d = null
                try { d = JSON.parse(text) } catch (e) { d = null }
                if (d) { root.values = d; root.rev++ }
            }
        }
    }

    // ── set: apply values, then restart the container ────────────────────
    Process {
        id: setProc
        property string _spec: "[]"
        command: ["python3", root.prefsScript, "set", root.settingsPath, setProc._spec]
        stdout: StdioCollector {
            onStreamFinished: {
                setProc.running = false
                var ok = false
                try { ok = !!(JSON.parse(text).ok) } catch (e) { ok = false }
                if (!ok) {
                    root.busy = false
                    root.toast = "Failed to write settings"
                    root.toastKind = "err"
                    return
                }
                setProc.restart()
            }
        }
        // kick a container restart (stop + start re-reads the bind-mounted file)
        function restart() {
            root.toast = "Settings saved \u00B7 restarting service\u2026"
            root.toastKind = "info"
            restartProc.running = false
            restartProc.running = true
        }
    }

    Process {
        id: restartProc
        command: [root.dockerScript, "restart"]
        onExited: {
            restartProc.running = false
            root.toast = "Waiting for service\u2026"
            healthTimer.tries = 0
            healthTimer.restart()
        }
    }

    // ── health poll: curl status code until 200 (or give up) ─────────────
    // Uses the html search route, NOT format=json: the json format can 403 at
    // runtime (disabled/limiter) even when the service is healthy, which left
    // the busy state stuck on "Applying…" until the popup was reopened.
    Process {
        id: healthProc
        command: ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
                  "--max-time", "4", root.searxBase + "/search?q=ping"]
        stdout: StdioCollector {
            onStreamFinished: {
                healthProc.running = false
                var up = text.trim() === "200"
                if (up) {
                    healthTimer.stop()
                    root.busy = false
                    root.toast = "Saved \u2713 service is back"
                    root.toastKind = "ok"
                } else if (healthTimer.tries >= 20) {
                    healthTimer.stop()
                    root.busy = false
                    root.toast = "Saved, but service did not come back"
                    root.toastKind = "err"
                } else {
                    healthTimer.restart()
                }
            }
        }
    }

    Timer {
        id: healthTimer
        interval: 900
        repeat: false
        property int tries: 0
        onTriggered: { tries++; healthProc.running = false; healthProc.running = true }
    }

    Timer {
        id: toastTimer
        interval: 3200
        repeat: false
        onTriggered: root.toast = ""
    }
    onToastChanged: if (toast.length) toastTimer.restart()

    // ── Inline controls ──────────────────────────────────────────────────

    // Enum: a Flow of pills; the active value is highlighted. Wrapped in an
    // Item whose writable implicitHeight mirrors the Flow's laid-out (wrapped)
    // height, so a wide option list grows the row instead of overflowing when
    // PrefRow bounds the control width (Flow.implicitHeight is read-only).
    component EnumFlow: Item {
        id: ef
        required property var d
        implicitHeight: pillFlow.childrenRect.height
        Flow {
            id: pillFlow
            anchors { left: parent.left; top: parent.top; right: parent.right }
            spacing: 6
            height: childrenRect.height
            Repeater {
                model: ef.d.options
                delegate: Rectangle {
                    required property var modelData
                    height: 26
                    width: elbl.implicitWidth + 20
                    radius: 8
                    border.width: 1
                    readonly property bool active: root.val(ef.d.id) === modelData.v
                    color: active ? Theme.cPrimaryContainer
                           : (epiMa.containsMouse ? Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.7) : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.4))
                    border.color: active ? Theme.cPrimary : Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.3)
                    Text {
                        id: elbl
                        anchors.centerIn: parent
                        text: modelData.l
                        font.pixelSize: 11
                        color: parent.active ? Theme.cOnPrimaryContainer : Theme.cOnSurf
                    }
                    MouseArea {
                        id: epiMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.put(ef.d.id, modelData.v)
                    }
                }
            }
        }
    }

    // Bool: a Material toggle switch.
    component BoolToggle: Rectangle {
        id: bt
        required property var d
        readonly property bool on: !!root.val(bt.d.id)
        width: 46; height: 26; radius: 13
        color: on ? Theme.cPrimary : Theme.cSurfVariant
        border.width: 1
        border.color: on ? Theme.cPrimary : Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.4)
        Behavior on color { ColorAnimation { duration: 130 } }
        Rectangle {
            width: 18; height: 18; radius: 9
            y: 4
            x: bt.on ? 24 : 4
            color: bt.on ? Theme.cOnPrimary : Theme.cOnSurfVar
            Behavior on x { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.put(bt.d.id, !bt.on)
        }
    }

    // Int: minus / value / plus stepper.
    component IntStepper: Rectangle {
        id: is
        required property var d
        width: stepRow.implicitWidth + 8; height: 26; radius: 8
        color: Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.4)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.3)
        RowLayout {
            id: stepRow
            anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
            spacing: 2
            Repeater {
                model: [ { g: "\u{F0374}", dir: -1 }, { g: "", dir: 0 }, { g: "\u{F0415}", dir: 1 } ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.preferredWidth: modelData.dir === 0 ? 30 : 22
                    Layout.preferredHeight: 22
                    radius: 6
                    color: stepMa.containsMouse ? Qt.alpha(Theme.cOnSurf, 0.12) : "transparent"
                    Text {
                        id: stLbl
                        anchors.centerIn: parent
                        text: modelData.dir === 0 ? String(root.val(is.d.id)) : modelData.g
                        font.family: modelData.dir === 0 ? "" : Theme.fontFamily
                        font.pixelSize: 12
                        color: Theme.cOnSurf
                    }
                    MouseArea {
                        id: stepMa
                        anchors.fill: parent
                        hoverEnabled: modelData.dir !== 0
                        enabled: modelData.dir !== 0
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            var cur = Number(root.val(is.d.id)) || is.d.def
                            var nv = Math.max(is.d.min, Math.min(is.d.max, cur + modelData.dir))
                            root.put(is.d.id, nv)
                        }
                    }
                }
            }
        }
    }

    // Text: single-line field, commits on Enter / focus-out.
    component TextInputCtl: Rectangle {
        id: tc
        required property var d
        Layout.preferredWidth: 220; height: 28; radius: 8
        color: tcEdit.activeFocus ? Qt.rgba(Theme.cSurface.r, Theme.cSurface.g, Theme.cSurface.b, 0.85)
                                  : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.4)
        border.width: 1
        border.color: tcEdit.activeFocus ? Theme.cPrimary : Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.3)
        TextInput {
            id: tcEdit
            anchors { fill: parent; leftMargin: 10; rightMargin: 10; verticalCenter: parent.verticalCenter }
            clip: true
            selectByMouse: true
            color: Theme.cOnSurf
            font.pixelSize: 12
            verticalAlignment: TextInput.AlignVCenter
            text: String(root.val(tc.d.id) ?? "")
            onEditingFinished: root.put(tc.d.id, tcEdit.text)
            Keys.onEscapePressed: { tcEdit.text = String(root.val(tc.d.id) ?? ""); tcEdit.focus = false }
        }
    }

    // One labelled row: description on the left, the typed control on the right.
    // Used as the body Repeater delegate, so it declares `required property var
    // modelData` (the Repeater injects it; a `d: modelData` binding does not).
    component PrefRow: Rectangle {
        id: pr
        required property var modelData
        width: parent ? parent.width : 300
        height: Math.max(46, prRow.implicitHeight + 16)
        radius: 10
        color: Qt.rgba(Theme.cSurfMid.r, Theme.cSurfMid.g, Theme.cSurfMid.b, 0.35)
        RowLayout {
            id: prRow
            anchors { fill: parent; leftMargin: 12; rightMargin: 12; topMargin: 8; bottomMargin: 8 }
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 1
                Text {
                    Layout.fillWidth: true
                    text: pr.modelData.label
                    font.pixelSize: 12
                    font.bold: true
                    color: Theme.cOnSurf
                }
                Text {
                    Layout.fillWidth: true
                    visible: String(pr.modelData.hint || "").length > 0
                    text: pr.modelData.hint
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    color: Qt.alpha(Theme.cOnSurfVar, 0.8)
                }
            }
            EnumFlow { visible: pr.modelData.type === "enum"; d: pr.modelData; Layout.preferredWidth: 320; Layout.maximumWidth: 320; Layout.alignment: Qt.AlignVCenter }
            BoolToggle { visible: pr.modelData.type === "bool"; d: pr.modelData; Layout.alignment: Qt.AlignVCenter }
            IntStepper { visible: pr.modelData.type === "int"; d: pr.modelData; Layout.alignment: Qt.AlignVCenter }
            TextInputCtl { visible: pr.modelData.type === "text"; d: pr.modelData; Layout.alignment: Qt.AlignVCenter }
        }
    }

    // ── Card ─────────────────────────────────────────────────────────────
    // Scrim: click-away dismiss + absorb hover/wheel so pointer events never
    // leak to the web view underneath (the card itself is mouse-transparent,
    // so stray points over it fall through to this handler).
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        onWheel: (wheel) => { wheel.accepted = true }
        onClicked: root.dismissed()
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(600, parent.width - 40)
        height: Math.min(520, parent.height - 40)
        radius: 16
        color: Theme.cOnSecondary
        border.width: 1
        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.3)
        z: 1

        ColumnLayout {
            anchors { fill: parent; margins: 16 }
            spacing: 12

            // Header
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                Text {
                    text: "\u{F08BB}"
                    font.family: Theme.fontFamily
                    font.pixelSize: 20
                    color: Theme.cPrimary
                    Layout.alignment: Qt.AlignVCenter
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Text {
                        text: "Web-Search Preferences"
                        font.pixelSize: 15
                        font.bold: true
                        color: Theme.cOnSurf
                    }
                    Text {
                        text: "Edit the SearXNG search engine settings"
                        font.pixelSize: 11
                        color: Qt.alpha(Theme.cOnSurfVar, 0.8)
                    }
                }
            }

            // Tab bar
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.tabs
                    delegate: Rectangle {
                        required property int index
                        required property var modelData
                        Layout.preferredHeight: 30
                        Layout.preferredWidth: tabRow.implicitWidth + 22
                        radius: 9
                        color: root.tab === index ? Theme.cPrimaryContainer
                               : (tabMa.containsMouse ? Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.6) : "transparent")
                        border.width: 1
                        border.color: root.tab === index ? Theme.cPrimary : Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.25)
                        RowLayout {
                            id: tabRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text { text: modelData.glyph; font.family: Theme.fontFamily; font.pixelSize: 13; color: root.tab === index ? Theme.cOnPrimaryContainer : Theme.cOnSurf }
                            Text { text: modelData.name; font.pixelSize: 11; color: root.tab === index ? Theme.cOnPrimaryContainer : Theme.cOnSurf }
                        }
                        MouseArea { id: tabMa; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.tab = index }
                    }
                }
                Item { Layout.fillWidth: true }
            }

            // Scrollable body for the active tab's rows
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: rowsCol.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                clip: true
                Column {
                    id: rowsCol
                    width: parent.width
                    spacing: 8
                    Repeater {
                        model: root.spec.filter(function (d) { return d.col === root.tab })
                        delegate: PrefRow { }
                    }
                }
            }

            // Toast line
            Text {
                Layout.fillWidth: true
                visible: root.toast.length > 0
                text: root.toast
                font.pixelSize: 11
                color: root.toastKind === "ok" ? Theme.cPrimary
                       : root.toastKind === "err" ? Theme.cErr : Theme.cOnSurfVar
            }

            // Footer: save / reset
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    visible: root.busy
                    text: "Applying\u2026"
                    font.pixelSize: 11
                    color: Qt.alpha(Theme.cOnSurfVar, 0.8)
                }
                Item { Layout.fillWidth: true; visible: !root.busy }
                Rectangle {
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: resetRow.implicitWidth + 22
                    radius: 9
                    enabled: !root.busy
                    opacity: enabled ? 1.0 : 0.5
                    color: resetMa.containsMouse ? Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.7) : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.4)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cOutline.r, Theme.cOutline.g, Theme.cOutline.b, 0.3)
                    RowLayout {
                        id: resetRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "\u{F0453}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.cOnSurf }
                        Text { text: "Reload"; font.pixelSize: 12; color: Theme.cOnSurf }
                    }
                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        enabled: parent.enabled
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.load()
                    }
                }
                Rectangle {
                    Layout.preferredHeight: 32
                    Layout.preferredWidth: saveRow.implicitWidth + 22
                    radius: 9
                    enabled: !root.busy
                    opacity: enabled ? 1.0 : 0.55
                    color: Theme.cPrimary
                    RowLayout {
                        id: saveRow
                        anchors.centerIn: parent
                        spacing: 6
                        Text { text: "\u{F0193}"; font.family: Theme.fontFamily; font.pixelSize: 13; color: Theme.cOnPrimary }
                        Text { text: root.busy ? "Saving\u2026" : "Save & Apply"; font.pixelSize: 12; font.bold: true; color: Theme.cOnPrimary }
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: parent.enabled
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.save()
                    }
                }
            }
        }
    }

    Component.onCompleted: root.load()
}
