import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import ".."

Item {
    id: root

    // Set true when used inside a vertical sidebar bar
    property bool vertical: false

    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  vertical ? Config.moduleHeight : wsRow.implicitWidth + Config.modPadH * 2
    implicitHeight: vertical ? wsCol.implicitHeight + Config.modPadH : Config.moduleHeight

    // ── Helpers ─────────────────────────────────────────────────────────────
    function _wsIcon(id, name, isEmpty) {
        if (Config.wsSpecialIcons.hasOwnProperty(name)) return Config.wsSpecialIcons[name]
        switch (Config.wsIconMode) {
            case "number": return String(id)
            case "icon": {
                const idx = id - 1
                // ws 1-5: use active/persistent/empty state icons; ws 6+: use wsIcons entry
                if (idx >= 0 && idx < Config.wsIcons.length && Config.wsIcons[idx] !== "")
                    return Config.wsIcons[idx]
                // fall through to state-based
            }
            // "dot" and fallback:
            default:
                return isEmpty ? Config.wsDotEmpty : Config.wsDotActive
        }
    }

    // State-based icon — active state always wins, then empty, then custom/persistent.
    // Checking active FIRST prevents the duplicate active dot when ws 6+ exists.
    function _wsStateIcon(ws) {
        const active = ws.id === (Hyprland.focusedMonitor?.activeWorkspace?.id ?? -999)
        if (active)      return Config.wsDotActive
        if (ws.isEmpty)  return Config.wsDotEmpty
        if (Config.wsIconMode !== "icon") return Config.wsDotPersistent
        const idx = ws.id - 1
        if (idx >= 0 && idx < Config.wsIcons.length && Config.wsIcons[idx] !== "")
            return Config.wsIcons[idx]   // persistent: custom icon
        return Config.wsDotPersistent
    }

    // ── Reactive workspace model ─────────────────────────────────────────────
    // Always shows Config.wsCount (5) persistent slots; extra workspaces appear 1-by-1.
    // isEmpty:true slots are dimmed (cOnSurfVar); active = cPrimary; occupied = cOnSurf
    readonly property var _wsModel: {
        const _dep  = Hyprland.workspaces?.values?.length         // reactivity: ws list changes
        const _dep2 = Hyprland.focusedMonitor?.activeWorkspace?.id // reactivity: focus changes
        const realMap = {}
        const specialList = []
        if (Hyprland.workspaces) {
            for (let i = 0; i < Hyprland.workspaces.values.length; i++) {
                const w = Hyprland.workspaces.values[i]
                if (w.id > 0) realMap[w.id] = { id: w.id, name: w.name, isEmpty: false, special: false }
                else if (w.id < 0) specialList.push({ id: w.id, name: w.name, isEmpty: false, special: true })
            }
        }
        let result = []
        for (let i = 1; i <= Config.wsCount; i++) {
            result.push(realMap[i] || { id: i, name: String(i), isEmpty: true, special: false })
            delete realMap[i]
        }
        const extraIds = Object.keys(realMap).map(Number).sort((a, b) => a - b)
        for (const id of extraIds) result.push(realMap[id])
        return result
    }


    function _wsColor(ws) {
        const active = ws.id === (Hyprland.focusedMonitor?.activeWorkspace?.id ?? -999)
        if (active)      return Config.wsActiveColor
        if (ws.isEmpty)  return Config.wsEmptyColor
        return Config.wsPersistentColor
    }

    function _wsOpacity(ws) {
        const active = ws.id === (Hyprland.focusedMonitor?.activeWorkspace?.id ?? -999)
        if (active)      return Config.wsActiveOpacity
        if (ws.isEmpty)  return Config.wsEmptyOpacity
        return Config.wsPersistentOpacity
    }


    // ── Horizontal layout ────────────────────────────────────────────────────
    Row {
        id: wsRow
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: Config.wsSpacing

        // Regular + persistent workspaces
        Repeater {
            model: root._wsModel
            delegate: Item {
                required property var modelData
                readonly property int _slot:    modelData.id
                readonly property string _name: modelData.name

                width: Config.wsIconMode === "number" ? 18 : 22
                height: Config.moduleHeight

                Text {
                    anchors.centerIn: parent
                    text: root._wsStateIcon(parent.modelData)
                    color: root._wsColor(parent.modelData)
                    opacity: root._wsOpacity(parent.modelData)
                    font.family: Config.fontFamily
                    font.pixelSize: Config.wsIconMode === "number" ? Config.labelFontSize : Config.glyphSize
                    font.weight: Config.fontWeight
                    Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + parent._slot)
                    onWheel: function(ev) {
                        if (!Config.wsScrollSwitch) return
                        Hyprland.dispatch(ev.angleDelta.y > 0 ? "workspace -1" : "workspace +1")
                    }
                }
            }
        }

    }

    // ── Vertical layout (sidebar) ────────────────────────────────────────────
    Column {
        id: wsCol
        visible: root.vertical
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Config.moduleVPad
        spacing: 2

        Repeater {
            model: root._wsModel
            delegate: Item {
                required property var modelData
                width: Config.barHeight; height: 26

                Text {
                    anchors.centerIn: parent
                    text: root._wsIcon(parent.modelData.id, parent.modelData.name)
                    color: root._wsColor(parent.modelData)
                    opacity: root._wsOpacity(parent.modelData)
                    font.family: Config.fontFamily
                    font.pixelSize: Config.fontSize
                    Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Hyprland.dispatch("workspace " + parent.modelData.id)
                }
            }
        }
    }
}
