import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ═══════════════════════════════════════════════════════════════════════════
//  HyprlandTab.qml — Hyprland settings: hyprsunset, gamma, hyprpicker,
//  x-ray, opacity, blur size/passes, gap presets
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: tab
    implicitWidth: parent ? parent.width : 300
    implicitHeight: content.implicitHeight

    // ── State ────────────────────────────────────────────────────────────
    property bool sunsetOn: false
    property bool xrayOn: false
    property bool opacityOn: false

    // ── State file readers ───────────────────────────────────────────────
    FileView {
        id: sunsetState
        path: CCConfig.configDir + "/hyprsunset.state"
        watchChanges: true
        onLoaded: tab.sunsetOn = (text().trim() === "enabled")
        Component.onCompleted: reload()
    }
    FileView {
        id: opacState
        path: CCConfig.configDir + "/opacity.state"
        watchChanges: true
        onLoaded: tab.opacityOn = (text().trim() === "enabled")
        Component.onCompleted: reload()
    }

    // Check xray sentinel
    Process {
        id: xrayCheck
        command: ["bash", "-c", "test -f " + CCConfig.configDir + "/settings/xray-on && echo on || echo off"]
        running: true
        stdout: StdioCollector { onStreamFinished: tab.xrayOn = (text.trim() === "on") }
    }

    // ── Helper processes ─────────────────────────────────────────────────
    Process { id: sunsetOnProc;  command: ["bash", "-c", "hyprsunset &"]; running: false }
    Process { id: sunsetOffProc; command: ["pkill", "hyprsunset"]; running: false }
    Process { id: gammaDecProc;  command: ["hyprctl", "hyprsunset", "gamma", "-10"]; running: false }
    Process { id: gammaIncProc;  command: ["hyprctl", "hyprsunset", "gamma", "+10"]; running: false }
    Process { id: pickerProc;    command: ["hyprpicker"]; running: false }
    Process { id: xrayProc;      command: ["bash", CCConfig.hyprScripts + "/xray.sh"]; running: false; onExited: tab.xrayOn = !tab.xrayOn }
    Process { id: opacProc;      command: ["bash", "-c", CCConfig.hyprScripts + "/window-opacity.sh"]; running: false }
    Process { id: saveStateProc; property string _f: ""; property string _v: ""; command: ["bash", "-c", "echo '" + _v + "' > '" + CCConfig.configDir + "/" + _f + "'"]; running: false }

    // Opacity read/write
    Process {
        id: opacReadProc
        command: ["bash", "-c", "grep 'active_opacity' '" + CCConfig.hyprConf + "' | head -1 | sed 's/.*= //'"]
        running: true
        stdout: StdioCollector { onStreamFinished: opacEntry.text = text.trim() }
    }
    Process { id: opacWriteProc; property string _v: "0.90"; command: ["bash", "-c",
        "sed -i 's/active_opacity = .*/active_opacity = " + _v + "/' '" + CCConfig.hyprConf + "' && " +
        "sed -i 's/inactive_opacity = .*/inactive_opacity = " + _v + "/' '" + CCConfig.hyprConf + "' && " +
        "hyprctl reload"]; running: false }

    // Blur read/write
    Process {
        id: blurSizeReadProc
        command: ["bash", "-c", "sed -n '/blur {/,/}/p' '" + CCConfig.hyprConf + "' | grep 'size' | head -1 | sed 's/.*= //'"]
        running: true
        stdout: StdioCollector { onStreamFinished: blurSizeEntry.text = text.trim() }
    }
    Process {
        id: blurPassReadProc
        command: ["bash", "-c", "sed -n '/blur {/,/}/p' '" + CCConfig.hyprConf + "' | grep 'passes' | head -1 | sed 's/.*= //'"]
        running: true
        stdout: StdioCollector { onStreamFinished: blurPassEntry.text = text.trim() }
    }

    function writeBlur(key, delta) {
        blurWriteProc._key = key
        blurWriteProc._delta = delta
        blurWriteProc.running = true
    }
    Process { id: blurWriteProc; property string _key: "size"; property int _delta: 1
        command: ["bash", "-c",
            "cur=$(sed -n '/blur {/,/}/p' '" + CCConfig.hyprConf + "' | grep '" + _key + "' | head -1 | sed 's/.*= //'); " +
            "nv=$((cur + " + _delta + ")); [ $nv -lt 0 ] && nv=0; " +
            "sed -i '/blur {/,/}/{s/" + _key + " = [0-9]*/" + _key + " = '$nv'/}' '" + CCConfig.hyprConf + "' && " +
            "hyprctl reload && echo $nv"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                if (blurWriteProc._key === "size") blurSizeEntry.text = text.trim()
                else blurPassEntry.text = text.trim()
            }
        }
    }

    // Gap presets
    Process { id: gapProc; property string _preset: "balanced"
        command: ["bash", "-c", CCConfig.home + "/.config/hyprcandy/hooks/hyprland_gap_presets.sh " + _preset]; running: false }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right }
        anchors.margins: 8
        spacing: 6

        // ── Heading ──────────────────────────────────────────────────────
        Text {
            text: " Hyprland"
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont; font.pixelSize: 14; font.weight: Font.Bold
        }

        // ── Hyprsunset toggle ────────────────────────────────────────────
        CCButton {
            Layout.fillWidth: true
            label: tab.sunsetOn ? "Hyprsunset \uf0eb" : "Hyprsunset \uf204"
            active: tab.sunsetOn
            onClicked: {
                tab.sunsetOn = !tab.sunsetOn
                if (tab.sunsetOn) sunsetOnProc.running = true
                else sunsetOffProc.running = true
                saveStateProc._f = "hyprsunset.state"
                saveStateProc._v = tab.sunsetOn ? "enabled" : "disabled"
                saveStateProc.running = true
            }
        }

        // ── Gamma ±10 ────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton { Layout.fillWidth: true; label: "\u03b3 \u221210"; onClicked: gammaDecProc.running = true }
            CCButton { Layout.fillWidth: true; label: "\u03b3 +10"; onClicked: gammaIncProc.running = true }
        }

        // ── Hyprpicker ──────────────────────────────────────────────────
        CCButton {
            Layout.fillWidth: true
            label: "\uf1fb  Hyprpicker"
            onClicked: pickerProc.running = true
        }

        // ── X-Ray ───────────────────────────────────────────────────────
        CCButton {
            Layout.fillWidth: true
            label: tab.xrayOn ? "X-Ray  On" : "X-Ray  Off"
            active: tab.xrayOn
            onClicked: xrayProc.running = true
        }

        // ── Opacity toggle ──────────────────────────────────────────────
        CCButton {
            Layout.fillWidth: true
            label: tab.opacityOn ? "Opacity On" : "Opacity Off"
            active: tab.opacityOn
            onClicked: {
                tab.opacityOn = !tab.opacityOn
                opacProc.running = true
                saveStateProc._f = "opacity.state"
                saveStateProc._v = tab.opacityOn ? "enabled" : "disabled"
                saveStateProc.running = true
            }
        }

        // ── Opacity ±0.05 ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton {
                Layout.fillWidth: true; label: "\u2212"
                onClicked: {
                    let v = Math.max(0, parseFloat(opacEntry.text) - 0.05).toFixed(2)
                    opacEntry.text = v; opacWriteProc._v = v; opacWriteProc.running = true
                }
            }
            CCEntry { id: opacEntry; Layout.fillWidth: true; text: "0.90"
                onAccepted: { opacWriteProc._v = text; opacWriteProc.running = true }
            }
            CCButton {
                Layout.fillWidth: true; label: "+"
                onClicked: {
                    let v = Math.min(1, parseFloat(opacEntry.text) + 0.05).toFixed(2)
                    opacEntry.text = v; opacWriteProc._v = v; opacWriteProc.running = true
                }
            }
            Text { text: "Opacity"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Blur Size ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton { Layout.fillWidth: true; label: "\u2212"; onClicked: tab.writeBlur("size", -1) }
            CCEntry { id: blurSizeEntry; Layout.fillWidth: true; text: "4" }
            CCButton { Layout.fillWidth: true; label: "+"; onClicked: tab.writeBlur("size", 1) }
            Text { text: "Blur Size"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Blur Passes ─────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true; spacing: 4
            CCButton { Layout.fillWidth: true; label: "\u2212"; onClicked: tab.writeBlur("passes", -1) }
            CCEntry { id: blurPassEntry; Layout.fillWidth: true; text: "2" }
            CCButton { Layout.fillWidth: true; label: "+"; onClicked: tab.writeBlur("passes", 1) }
            Text { text: "Blur Passes"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
        }

        // ── Gap Presets ─────────────────────────────────────────────────
        Text {
            text: "  Gap Presets"
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont; font.pixelSize: 13; font.weight: Font.Bold
            Layout.topMargin: 4
        }

        Repeater {
            model: ["minimal", "balanced", "spacious", "zero"]
            CCButton {
                required property string modelData
                Layout.fillWidth: true
                label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                onClicked: { gapProc._preset = modelData; gapProc.running = true }
            }
        }
    }
}
