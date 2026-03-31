import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ═══════════════════════════════════════════════════════════════════════════
//  SDDMTab.qml — SDDM sugar-candy theme configuration
//  Mirrors candy-utils.js createSDDMPanel() functionality.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: tab
    implicitWidth: parent ? parent.width : 300
    implicitHeight: content.implicitHeight

    // ── Read helpers ─────────────────────────────────────────────────────
    function readSddmVal(key, entry) {
        const p = readProc.createObject(tab, { _key: key, _entry: entry })
        p.running = true
    }

    Component {
        id: readProc
        Process {
            property string _key: ""
            property var _entry: null
            command: ["bash", "-c",
                "grep -m1 '^" + _key + "=' '" + CCConfig.sddmTheme + "' | cut -d= -f2 | tr -d '\\n \"'"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: {
                    if (parent._entry) parent._entry.text = text.trim()
                }
            }
        }
    }

    // ── Write helper ─────────────────────────────────────────────────────
    Process {
        id: writeProc
        property string _key: ""
        property string _val: ""
        command: ["pkexec", "bash", "-c",
            "sed -i 's/^" + _key + "=.*/" + _key + "=" + _val + "/' '" + CCConfig.sddmTheme + "'"]
        running: false
    }

    function writeSddm(key, val) {
        writeProc._key = key
        writeProc._val = val
        writeProc.running = true
    }

    Component.onCompleted: {
        readSddmVal("HeaderText", headerEntry)
        readSddmVal("FormPosition", formPosEntry)
        readSddmVal("FullBlur", blurToggleState)
        readSddmVal("BlurRadius", blurRadiusEntry)
    }

    // Pseudo-entry to capture FullBlur toggle state
    QtObject {
        id: blurToggleState
        property string text: "false"
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right }
        anchors.margins: 8
        spacing: 6

        Text {
            text: "\udb80\udd0b SDDM"
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont; font.pixelSize: 14; font.weight: Font.Bold
        }

        Text {
            text: "Requires pkexec for privileged writes"
            color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.5)
            font.family: CCConfig.labelFont; font.pixelSize: 9
            Layout.bottomMargin: 2
        }

        // ── Header Text ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCEntry {
                id: headerEntry; Layout.fillWidth: true; text: ""
                placeholderText: "HeaderText"
                onAccepted: tab.writeSddm("HeaderText", "\"" + text + "\"")
            }
            Text { text: "Header"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Form Position ────────────────────────────────────────────────
        Text {
            text: "Form Position"
            color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 12
        }
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            Repeater {
                model: ["left", "center", "right"]
                CCButton {
                    required property string modelData
                    Layout.fillWidth: true
                    label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                    active: formPosEntry.text === modelData
                    onClicked: {
                        formPosEntry.text = modelData
                        tab.writeSddm("FormPosition", "\"" + modelData + "\"")
                    }
                }
            }
        }
        // Hidden entry to hold current form position
        CCEntry { id: formPosEntry; visible: false; text: "center" }

        // ── Full Blur toggle ─────────────────────────────────────────────
        CCButton {
            Layout.fillWidth: true
            label: blurToggleState.text === "true" ? "Full Blur: On" : "Full Blur: Off"
            active: blurToggleState.text === "true"
            onClicked: {
                const next = blurToggleState.text === "true" ? "false" : "true"
                blurToggleState.text = next
                tab.writeSddm("FullBlur", "\"" + next + "\"")
            }
        }

        // ── Blur Radius ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton {
                Layout.fillWidth: true; label: "\u2212"
                onClicked: {
                    let n = Math.max(0, parseInt(blurRadiusEntry.text) - 5)
                    blurRadiusEntry.text = n.toString()
                    tab.writeSddm("BlurRadius", n.toString())
                }
            }
            CCEntry {
                id: blurRadiusEntry; Layout.preferredWidth: 50; text: "50"
                onAccepted: tab.writeSddm("BlurRadius", text)
            }
            CCButton {
                Layout.fillWidth: true; label: "+"
                onClicked: {
                    let n = Math.min(200, parseInt(blurRadiusEntry.text) + 5)
                    blurRadiusEntry.text = n.toString()
                    tab.writeSddm("BlurRadius", n.toString())
                }
            }
            Text { text: "Blur Radius"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Preview button ───────────────────────────────────────────────
        CCButton {
            Layout.fillWidth: true; Layout.topMargin: 4
            label: "\uf06e  Preview SDDM"
            onClicked: previewProc.running = true
        }
        Process {
            id: previewProc
            command: ["bash", "-c", "sddm-greeter --test-mode || sddm-greeter-qt6 --test-mode"]
            running: false
        }
    }
}
