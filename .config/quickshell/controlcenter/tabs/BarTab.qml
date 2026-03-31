import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ═══════════════════════════════════════════════════════════════════════════
//  BarTab.qml — Bar configuration with sub-tabs matching Bar-plan.md:
//  General, Icons, Workspaces, Media, Cava, Background
//  Reads/writes ~/.config/quickshell/bar/Config.qml via sed
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: tab
    implicitWidth: parent ? parent.width : 300
    implicitHeight: content.implicitHeight

    property string activeSubTab: "general"
    readonly property string barConfigPath: CCConfig.home + "/.config/quickshell/bar/Config.qml"

    // ── Read a property value from Config.qml ────────────────────────────
    function readProp(key, callback) {
        const proc = readComp.createObject(tab, { _key: key, _cb: callback })
        proc.running = true
    }

    Component {
        id: readComp
        Process {
            property string _key: ""
            property var _cb: null
            command: ["bash", "-c",
                "grep -m1 'property.*" + _key + ":' '" + tab.barConfigPath + "' | " +
                "sed 's/.*" + _key + ":\\s*//' | sed 's|\\s*//.*||' | tr -d '\\n'"]
            running: false
            stdout: StdioCollector {
                onStreamFinished: { if (parent._cb) parent._cb(text.trim()) }
            }
        }
    }

    // ── Write a property value to Config.qml ─────────────────────────────
    Process {
        id: writeProc
        property string _key: ""
        property string _val: ""
        command: ["bash", "-c",
            "sed -i 's/\\(property.*" + _key + ":\\s*\\)[^ ]*/\\1" + _val + "/' '" + tab.barConfigPath + "' && " +
            "qs ipc -c bar call bar reloadConfig 2>/dev/null || true"]
        running: false
    }

    function writeProp(key, val) {
        writeProc._key = key
        writeProc._val = val
        writeProc.running = true
    }

    // ── Sub-tab button row ───────────────────────────────────────────────
    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right }
        anchors.margins: 8
        spacing: 4

        Text {
            text: "\udb81\udd8d Bar Config"
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont; font.pixelSize: 14; font.weight: Font.Bold
        }

        // Sub-tab selector
        Flow {
            Layout.fillWidth: true
            spacing: 3

            Repeater {
                model: [
                    { id: "general",    label: "General" },
                    { id: "icons",      label: "Icons" },
                    { id: "workspaces", label: "WS" },
                    { id: "media",      label: "Media" },
                    { id: "cava",       label: "Cava" },
                    { id: "background", label: "BG" }
                ]
                Rectangle {
                    required property var modelData
                    width: stLabel.implicitWidth + 14; height: 22; radius: 6
                    color: tab.activeSubTab === modelData.id
                        ? Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.2)
                        : Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.06)
                    border.width: tab.activeSubTab === modelData.id ? 1 : 0
                    border.color: CCTheme.cPrimaryFixedDim
                    Text {
                        id: stLabel; anchors.centerIn: parent
                        text: modelData.label; color: CCTheme.cPrimary
                        font.family: CCConfig.labelFont; font.pixelSize: 10
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: tab.activeSubTab = modelData.id
                    }
                }
            }
        }

        // ═════════════════════════════════════════════════════════════════
        //  SUB-TAB: General
        // ═════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: tab.activeSubTab === "general"
            Layout.fillWidth: true; spacing: 4

            // Bar mode toggle
            RowLayout {
                Layout.fillWidth: true; spacing: 4
                Repeater {
                    model: ["bar", "island"]
                    CCButton {
                        required property string modelData
                        Layout.fillWidth: true
                        label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        active: barModeVal === modelData
                        onClicked: { barModeVal = modelData; tab.writeProp("barMode", "\"" + modelData + "\"") }
                    }
                }
                property string barModeVal: "bar"
                Component.onCompleted: tab.readProp("barMode", function(v) { barModeVal = v.replace(/"/g, "") })
            }

            // Bar position
            RowLayout {
                Layout.fillWidth: true; spacing: 4
                Repeater {
                    model: ["top", "bottom"]
                    CCButton {
                        required property string modelData
                        Layout.fillWidth: true
                        label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        active: barPosVal === modelData
                        onClicked: { barPosVal = modelData; tab.writeProp("barPosition", "\"" + modelData + "\"") }
                    }
                }
                property string barPosVal: "top"
                Component.onCompleted: tab.readProp("barPosition", function(v) { barPosVal = v.replace(/"/g, "") })
            }

            // Numeric fields
            Repeater {
                model: [
                    { key: "barHeight",           label: "Bar Height",      lo: 16, hi: 80 },
                    { key: "moduleHeight",        label: "Module Height",   lo: 10, hi: 60 },
                    { key: "islandSpacing",       label: "Island Spacing",  lo: 0,  hi: 30 },
                    { key: "barRadius",           label: "Bar Radius",      lo: 0,  hi: 40 },
                    { key: "islandRadius",        label: "Island Radius",   lo: 0,  hi: 40 },
                    { key: "islandBorder",        label: "Island Border",   lo: 0,  hi: 10 },
                    { key: "barBorderWidth",      label: "Bar Border",      lo: 0,  hi: 10 },
                    { key: "modPadH",             label: "Module Pad H",    lo: 0,  hi: 20 },
                    { key: "modPadV",             label: "Module Pad V",    lo: 0,  hi: 20 },
                    { key: "groupedSpacing",      label: "Grouped Spacing", lo: 0,  hi: 20 },
                    { key: "barEdgePaddingLeft",   label: "Edge Pad L",     lo: 0,  hi: 30 },
                    { key: "barEdgePaddingRight",  label: "Edge Pad R",     lo: 0,  hi: 30 }
                ]
                BarNumericRow {
                    required property var modelData
                    Layout.fillWidth: true
                    propKey: modelData.key; propLabel: modelData.label
                    lo: modelData.lo; hi: modelData.hi
                    configPath: tab.barConfigPath
                    onValueChanged: (k, v) => tab.writeProp(k, v)
                    Component.onCompleted: tab.readProp(modelData.key, function(v) { setValue(v) })
                }
            }
        }

        // ═════════════════════════════════════════════════════════════════
        //  SUB-TAB: Icons
        // ═════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: tab.activeSubTab === "icons"
            Layout.fillWidth: true; spacing: 4

            Repeater {
                model: [
                    { key: "glyphSize",      label: "Glyph Size",       lo: 6, hi: 32 },
                    { key: "infoGlyphSize",  label: "Info Glyph Size",  lo: 6, hi: 32 },
                    { key: "mediaGlyphSize", label: "Media Glyph Size", lo: 6, hi: 32 },
                    { key: "infoFontSize",   label: "Info Font Size",   lo: 6, hi: 32 },
                    { key: "mediaInfoFontSize", label: "Media Font Size", lo: 6, hi: 32 },
                    { key: "labelFontSize",  label: "Label Font Size",  lo: 6, hi: 32 }
                ]
                BarNumericRow {
                    required property var modelData
                    Layout.fillWidth: true
                    propKey: modelData.key; propLabel: modelData.label
                    lo: modelData.lo; hi: modelData.hi
                    configPath: tab.barConfigPath
                    onValueChanged: (k, v) => tab.writeProp(k, v)
                    Component.onCompleted: tab.readProp(modelData.key, function(v) { setValue(v) })
                }
            }

            // CC glyph entry
            RowLayout {
                Layout.fillWidth: true; spacing: 4
                CCEntry {
                    id: ccGlyphEntry; Layout.fillWidth: true
                    placeholderText: "CC Glyph"
                    onAccepted: tab.writeProp("ccGlyph", "\"" + text + "\"")
                }
                Text { text: "CC Glyph"; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 11 }
                Component.onCompleted: tab.readProp("ccGlyph", function(v) { ccGlyphEntry.text = v.replace(/"/g, "") })
            }

            // Battery radial
            Repeater {
                model: [
                    { key: "batteryRadialSize",  label: "Bat Radial Size",  lo: 6, hi: 30 },
                    { key: "batteryRadialWidth", label: "Bat Radial Width", lo: 1, hi: 8 }
                ]
                BarNumericRow {
                    required property var modelData
                    Layout.fillWidth: true
                    propKey: modelData.key; propLabel: modelData.label
                    lo: modelData.lo; hi: modelData.hi
                    configPath: tab.barConfigPath
                    onValueChanged: (k, v) => tab.writeProp(k, v)
                    Component.onCompleted: tab.readProp(modelData.key, function(v) { setValue(v) })
                }
            }
        }

        // ═════════════════════════════════════════════════════════════════
        //  SUB-TAB: Workspaces
        // ═════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: tab.activeSubTab === "workspaces"
            Layout.fillWidth: true; spacing: 4

            // Icon mode selector
            RowLayout {
                Layout.fillWidth: true; spacing: 4
                Repeater {
                    model: ["dot", "number", "icon"]
                    CCButton {
                        required property string modelData
                        Layout.fillWidth: true
                        label: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        active: wsIconModeVal === modelData
                        onClicked: { wsIconModeVal = modelData; tab.writeProp("wsIconMode", "\"" + modelData + "\"") }
                    }
                }
                property string wsIconModeVal: "icon"
                Component.onCompleted: tab.readProp("wsIconMode", function(v) { wsIconModeVal = v.replace(/"/g, "") })
            }

            Repeater {
                model: [
                    { key: "wsGlyphSize",   label: "WS Glyph Size",  lo: 6, hi: 32 },
                    { key: "wsSpacing",     label: "WS Spacing",     lo: 0, hi: 20 },
                    { key: "wsPadLeft",     label: "WS Pad Left",    lo: 0, hi: 20 },
                    { key: "wsPadRight",    label: "WS Pad Right",   lo: 0, hi: 20 },
                    { key: "wsPadTop",      label: "WS Pad Top",     lo: 0, hi: 20 },
                    { key: "wsPadBottom",   label: "WS Pad Bottom",  lo: 0, hi: 20 },
                    { key: "wsMarginLeft",  label: "WS Margin L",    lo: 0, hi: 20 },
                    { key: "wsMarginRight", label: "WS Margin R",    lo: 0, hi: 20 }
                ]
                BarNumericRow {
                    required property var modelData
                    Layout.fillWidth: true
                    propKey: modelData.key; propLabel: modelData.label
                    lo: modelData.lo; hi: modelData.hi
                    configPath: tab.barConfigPath
                    onValueChanged: (k, v) => tab.writeProp(k, v)
                    Component.onCompleted: tab.readProp(modelData.key, function(v) { setValue(v) })
                }
            }

            // Separators toggle
            CCButton {
                Layout.fillWidth: true
                label: wsSepOn ? "Separators: On" : "Separators: Off"
                active: wsSepOn
                property bool wsSepOn: false
                onClicked: { wsSepOn = !wsSepOn; tab.writeProp("wsSeparators", wsSepOn ? "true" : "false") }
                Component.onCompleted: tab.readProp("wsSeparators", function(v) { wsSepOn = (v === "true") })
            }
        }

        // ═════════════════════════════════════════════════════════════════
        //  SUB-TAB: Media
        // ═════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: tab.activeSubTab === "media"
            Layout.fillWidth: true; spacing: 4

            Repeater {
                model: [
                    { key: "mediaThumbSize",     label: "Thumb Size",     lo: 8, hi: 40 },
                    { key: "mediaPlayPauseSize", label: "Play/Pause Size", lo: 4, hi: 20 },
                    { key: "mediaPadLeft",       label: "Pad Left",       lo: 0, hi: 20 },
                    { key: "mediaPadRight",      label: "Pad Right",      lo: 0, hi: 20 },
                    { key: "mediaPadTop",        label: "Pad Top",        lo: 0, hi: 20 },
                    { key: "mediaPadBottom",     label: "Pad Bottom",     lo: 0, hi: 20 }
                ]
                BarNumericRow {
                    required property var modelData
                    Layout.fillWidth: true
                    propKey: modelData.key; propLabel: modelData.label
                    lo: modelData.lo; hi: modelData.hi
                    configPath: tab.barConfigPath
                    onValueChanged: (k, v) => tab.writeProp(k, v)
                    Component.onCompleted: tab.readProp(modelData.key, function(v) { setValue(v) })
                }
            }

            // Show/hide media
            CCButton {
                Layout.fillWidth: true
                label: mediaVis ? "Media: Visible" : "Media: Hidden"
                active: mediaVis
                property bool mediaVis: true
                onClicked: { mediaVis = !mediaVis; tab.writeProp("showMediaPlayer", mediaVis ? "true" : "false") }
                Component.onCompleted: tab.readProp("showMediaPlayer", function(v) { mediaVis = (v === "true") })
            }
        }

        // ═════════════════════════════════════════════════════════════════
        //  SUB-TAB: Cava
        // ═════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: tab.activeSubTab === "cava"
            Layout.fillWidth: true; spacing: 4

            // Cava style presets
            Text {
                text: "Cava Style"
                color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 12
            }
            Flow {
                Layout.fillWidth: true; spacing: 3
                Repeater {
                    model: ["dots", "bars", "braille_fill", "braille_hollow", "blocks", "thin_bars"]
                    CCButton {
                        required property string modelData
                        width: csLbl.implicitWidth + 14; height: 22
                        label: modelData.replace("_", " ")
                        active: cavaStyleVal === modelData
                        onClicked: { cavaStyleVal = modelData; tab.writeProp("cavaStyle", "\"" + modelData + "\"") }
                        Text { id: csLbl; visible: false; text: modelData.replace("_", " "); font.pixelSize: 10 }
                    }
                }
                property string cavaStyleVal: "dots"
                Component.onCompleted: tab.readProp("cavaStyle", function(v) { cavaStyleVal = v.replace(/"/g, "") })
            }

            // Cava width
            BarNumericRow {
                Layout.fillWidth: true
                propKey: "cavaWidth"; propLabel: "Cava Width"
                lo: 5; hi: 80
                configPath: tab.barConfigPath
                onValueChanged: (k, v) => tab.writeProp(k, v)
                Component.onCompleted: tab.readProp("cavaWidth", function(v) { setValue(v) })
            }

            // Gradient toggle
            CCButton {
                Layout.fillWidth: true
                label: cavaGrad ? "Gradient: On" : "Gradient: Off"
                active: cavaGrad
                property bool cavaGrad: false
                onClicked: { cavaGrad = !cavaGrad; tab.writeProp("cavaGradientEnabled", cavaGrad ? "true" : "false") }
                Component.onCompleted: tab.readProp("cavaGradientEnabled", function(v) { cavaGrad = (v === "true") })
            }
        }

        // ═════════════════════════════════════════════════════════════════
        //  SUB-TAB: Background
        // ═════════════════════════════════════════════════════════════════
        ColumnLayout {
            visible: tab.activeSubTab === "background"
            Layout.fillWidth: true; spacing: 4

            Text {
                text: "Per-module BG Opacity"
                color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 12
            }

            Repeater {
                model: [
                    { key: "wsBgOpacity",           label: "WS BG" },
                    { key: "groupedBgOpacity",      label: "Grouped BG" },
                    { key: "ungroupedBgOpacity",    label: "Ungrouped BG" },
                    { key: "mediaBgOpacity",        label: "Media BG" },
                    { key: "cavaBgOpacity",         label: "Cava BG" },
                    { key: "activeWindowBgOpacity", label: "Active Win BG" },
                    { key: "moduleBgOpacity",       label: "Global Module BG" },
                    { key: "islandBgOpacityIsland", label: "Island Mode BG" }
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true; spacing: 4
                    CCButton {
                        Layout.preferredWidth: 26; label: "\u2212"
                        onClicked: {
                            let v = Math.max(-1, parseFloat(_bgEntry.text) - 0.1).toFixed(1)
                            _bgEntry.text = v; tab.writeProp(modelData.key, v)
                        }
                    }
                    CCEntry {
                        id: _bgEntry; Layout.preferredWidth: 50; text: "-1"
                        onAccepted: tab.writeProp(modelData.key, text)
                    }
                    CCButton {
                        Layout.preferredWidth: 26; label: "+"
                        onClicked: {
                            let v = Math.min(1, parseFloat(_bgEntry.text) + 0.1).toFixed(1)
                            _bgEntry.text = v; tab.writeProp(modelData.key, v)
                        }
                    }
                    Text { text: modelData.label; color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 10 }
                    Component.onCompleted: tab.readProp(modelData.key, function(v) { _bgEntry.text = v })
                }
            }

            // Module visibility toggles
            Text {
                text: "Module Visibility"
                color: CCTheme.cPrimary; font.family: CCConfig.labelFont; font.pixelSize: 12
                Layout.topMargin: 6
            }

            Repeater {
                model: [
                    { key: "showCava",          label: "Cava" },
                    { key: "showWeather",       label: "Weather" },
                    { key: "showBattery",       label: "Battery" },
                    { key: "showMediaPlayer",   label: "Media" },
                    { key: "showIdleInhibitor", label: "Idle Inhibitor" },
                    { key: "showRofi",          label: "Rofi" },
                    { key: "showUpdates",       label: "Updates" },
                    { key: "showPowerProfiles", label: "Power Profiles" },
                    { key: "showOverview",      label: "Overview" },
                    { key: "showNotifications", label: "Notifications" },
                    { key: "showWallpaper",     label: "Wallpaper" },
                    { key: "showTray",          label: "Tray" },
                    { key: "showBluetooth",     label: "Bluetooth" },
                    { key: "showWindow",        label: "Active Window" },
                    { key: "showDistro",        label: "Distro" }
                ]
                CCButton {
                    required property var modelData
                    Layout.fillWidth: true
                    label: modelData.label + (_vis ? ": On" : ": Off")
                    active: _vis
                    property bool _vis: true
                    onClicked: { _vis = !_vis; tab.writeProp(modelData.key, _vis ? "true" : "false") }
                    Component.onCompleted: tab.readProp(modelData.key, function(v) { _vis = (v === "true") })
                }
            }
        }
    }
}
