import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ═══════════════════════════════════════════════════════════════════════════
//  MenusTab.qml — Rofi menu settings: border, radius, icon size
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: tab
    implicitWidth: parent ? parent.width : 300
    implicitHeight: content.implicitHeight

    // ── Read current values ──────────────────────────────────────────────
    Process {
        id: borderRead
        command: ["bash", "-c",
            "grep -oP '(?<=border:\\s)\\d+' '" + CCConfig.rofiBorder + "' 2>/dev/null || echo 2"]
        running: true
        stdout: StdioCollector { onStreamFinished: borderEntry.text = text.trim() }
    }

    Process {
        id: radiusRead
        command: ["bash", "-c",
            "grep -oP '(?<=border-radius:\\s)\\d+' '" + CCConfig.rofiRadius + "' 2>/dev/null || echo 12"]
        running: true
        stdout: StdioCollector { onStreamFinished: radiusEntry.text = text.trim() }
    }

    Process {
        id: iconRead
        command: ["bash", "-c",
            "grep -oP '(?<=element-icon\\s*\\{[^}]*size:\\s*)\\d+' '" + CCConfig.rofiConf + "' 2>/dev/null || echo 24"]
        running: true
        stdout: StdioCollector { onStreamFinished: iconEntry.text = text.trim() }
    }

    // ── Write helpers ────────────────────────────────────────────────────
    Process {
        id: borderWrite
        property string _v: "2"
        command: ["bash", "-c",
            "echo '* { border: " + _v + "px; }' > '" + CCConfig.rofiBorder + "'"]
        running: false
    }

    Process {
        id: radiusWrite
        property string _v: "12"
        command: ["bash", "-c",
            "echo '* { border-radius: " + _v + "px; }' > '" + CCConfig.rofiRadius + "'"]
        running: false
    }

    Process {
        id: iconWrite
        property string _v: "24"
        command: ["bash", "-c",
            "sed -i 's/size:\\s*[0-9]*px/size: " + _v + "px/g' '" + CCConfig.rofiConf + "'"]
        running: false
    }

    function adjustVal(entry, writeProc, delta, lo, hi) {
        let n = parseInt(entry.text) + delta
        if (n < lo) n = lo
        if (n > hi) n = hi
        entry.text = n.toString()
        writeProc._v = n.toString()
        writeProc.running = true
    }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right }
        anchors.margins: 8
        spacing: 6

        Text {
            text: "\udb80\udcc5 Menus (Rofi)"
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont; font.pixelSize: 14; font.weight: Font.Bold
        }

        // ── Border Width ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton {
                Layout.fillWidth: true; label: "\u2212"
                onClicked: tab.adjustVal(borderEntry, borderWrite, -1, 0, 20)
            }
            CCEntry {
                id: borderEntry; Layout.preferredWidth: 50; text: "2"
                onAccepted: { borderWrite._v = text; borderWrite.running = true }
            }
            CCButton {
                Layout.fillWidth: true; label: "+"
                onClicked: tab.adjustVal(borderEntry, borderWrite, 1, 0, 20)
            }
            Text { text: "Border"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Border Radius ────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton {
                Layout.fillWidth: true; label: "\u2212"
                onClicked: tab.adjustVal(radiusEntry, radiusWrite, -2, 0, 100)
            }
            CCEntry {
                id: radiusEntry; Layout.preferredWidth: 50; text: "12"
                onAccepted: { radiusWrite._v = text; radiusWrite.running = true }
            }
            CCButton {
                Layout.fillWidth: true; label: "+"
                onClicked: tab.adjustVal(radiusEntry, radiusWrite, 2, 0, 100)
            }
            Text { text: "Radius"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Icon Size ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton {
                Layout.fillWidth: true; label: "\u2212"
                onClicked: tab.adjustVal(iconEntry, iconWrite, -2, 8, 64)
            }
            CCEntry {
                id: iconEntry; Layout.preferredWidth: 50; text: "24"
                onAccepted: { iconWrite._v = text; iconWrite.running = true }
            }
            CCButton {
                Layout.fillWidth: true; label: "+"
                onClicked: tab.adjustVal(iconEntry, iconWrite, 2, 8, 64)
            }
            Text { text: "Icon Size"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }
    }
}
