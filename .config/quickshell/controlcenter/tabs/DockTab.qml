import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ═══════════════════════════════════════════════════════════════════════════
//  DockTab.qml — Dock settings (hyprcandy-dock GJS)
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: tab
    implicitWidth: parent ? parent.width : 300
    implicitHeight: content.implicitHeight

    // ── Read dock config values ──────────────────────────────────────────
    function readDockVal(key) {
        readProc._key = key
        readProc.running = true
    }

    Process {
        id: readProc
        property string _key: ""
        command: ["bash", "-c",
            "grep -m1 '^[[:space:]]*" + _key + ":' '" + CCConfig.dockConfig + "' | sed \"s/.*: *//;s/[,'\\\"]//g\" | tr -d '\\n'"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim()
                switch (readProc._key) {
                    case "buttonSpacing": spacingEntry.text = v; break
                    case "innerPadding":  paddingEntry.text = v; break
                    case "borderWidth":   borderWEntry.text = v; break
                    case "borderRadius":  borderREntry.text = v; break
                    case "appIconSize":   iconSizeEntry.text = v; break
                    case "startIcon":     startIconEntry.text = v; break
                }
            }
        }
    }

    // ── Write dock config values ─────────────────────────────────────────
    Process {
        id: writeProc
        property string _key: ""
        property string _val: ""
        property bool _isStr: false
        command: ["bash", "-c",
            "sed -i \"s/^\\([[:space:]]*" + _key + ":\\s*\\).*/\\1" +
            (_isStr ? "'" + _val + "'" : _val) + ",/\" '" + CCConfig.dockConfig + "' && " +
            "pkill -SIGUSR2 -f 'gjs dock-main.js'"
        ]
        running: false
    }

    function writeDock(key, val, isStr) {
        writeProc._key = key
        writeProc._val = val
        writeProc._isStr = isStr || false
        writeProc.running = true
    }

    // ── Cycle position ───────────────────────────────────────────────────
    Process { id: cycleProc; command: ["bash", CCConfig.dockCycle]; running: false }

    // ── Icon size (requires dock restart) ────────────────────────────────
    Process {
        id: iconRestartProc
        command: ["bash", "-c", "bash '" + CCConfig.dockToggle + "' && sleep 1 && bash '" + CCConfig.dockToggle + "'"]
        running: false
    }

    Component.onCompleted: {
        // Read all initial values
        for (const k of ["buttonSpacing", "innerPadding", "borderWidth", "borderRadius", "appIconSize", "startIcon"])
            readDockVal(k)
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right }
        anchors.margins: 8
        spacing: 6

        Text {
            text: "\udb80\ude92 Dock"
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont; font.pixelSize: 14; font.weight: Font.Bold
        }

        CCButton {
            Layout.fillWidth: true
            label: "\udb81\udf18 Cycle Position"
            onClicked: cycleProc.running = true
        }

        // ── Editable fields ──────────────────────────────────────────────
        Repeater {
            model: [
                { label: "Spacing",  key: "buttonSpacing", lo: 0, hi: 30 },
                { label: "Padding",  key: "innerPadding",  lo: 0, hi: 30 },
                { label: "Border W", key: "borderWidth",   lo: 0, hi: 10 },
                { label: "Border R", key: "borderRadius",  lo: 0, hi: 100 }
            ]
            RowLayout {
                required property var modelData
                Layout.fillWidth: true; spacing: 4
                CCEntry {
                    id: _entry
                    Layout.preferredWidth: 50
                    text: ""
                    onAccepted: {
                        const n = parseInt(text)
                        if (!isNaN(n) && n >= modelData.lo && n <= modelData.hi)
                            tab.writeDock(modelData.key, n.toString(), false)
                    }
                    Component.onCompleted: {
                        if (modelData.key === "buttonSpacing") spacingEntry = _entry
                        else if (modelData.key === "innerPadding") paddingEntry = _entry
                        else if (modelData.key === "borderWidth") borderWEntry = _entry
                        else if (modelData.key === "borderRadius") borderREntry = _entry
                    }
                }
                Text {
                    text: modelData.label; color: CCTheme.cPrimary
                    font.family: CCConfig.labelFont; font.pixelSize: 11
                }
            }
        }

        // ── Icon Size (special: requires dock restart) ───────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCEntry {
                id: iconSizeEntry; Layout.preferredWidth: 50
                text: ""
                onAccepted: {
                    const n = parseInt(text)
                    if (!isNaN(n) && n >= 12 && n <= 64) {
                        tab.writeDock("appIconSize", n.toString(), false)
                        iconRestartProc.running = true
                    }
                }
            }
            Text { text: "Icon Size"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Start Icon ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCEntry {
                id: startIconEntry; Layout.preferredWidth: 50
                text: ""
                onAccepted: { if (text.length > 0) tab.writeDock("startIcon", text, true) }
            }
            Text { text: "Start Icon"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }
    }

    // Entry aliases for readProc to populate
    property var spacingEntry: null
    property var paddingEntry: null
    property var borderWEntry: null
    property var borderREntry: null
}
