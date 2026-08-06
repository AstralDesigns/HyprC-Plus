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
                // All workspaces: use wsIcons entry if set; otherwise fall through to state-based
                if (idx >= 0 && idx < Config.wsIcons.length && Config.wsIcons[idx] !== "")
                    return Config.wsIcons[idx]
                // No custom icon — use same active/persistent/empty logic as _wsStateIcon
                // so ws 6-10 honour wsDotPersistent just like ws 1-5 do.
                const active = id === (Hyprland.focusedMonitor?.activeWorkspace?.id ?? -999)
                if (active)   return Config.wsDotActive
                if (!isEmpty) return Config.wsDotPersistent
                return Config.wsDotEmpty
            }
            // "dot" and fallback:
            default:
                return isEmpty ? Config.wsDotEmpty : Config.wsDotActive
        }
    }

    // State-based icon for ws 1-5 in "icon" mode
    function _wsStateIcon(ws) {
        if (Config.wsIconMode !== "icon") return _wsIcon(ws.id, ws.name, ws.isEmpty)
        const idx = ws.id - 1
        if (idx >= 0 && idx < Config.wsIcons.length && Config.wsIcons[idx] !== "")
            return Config.wsIcons[idx]   // has explicit custom icon
        const active = ws.id === (Hyprland.focusedMonitor?.activeWorkspace?.id ?? -999)
        if (active)     return Config.wsDotActive
        if (!ws.isEmpty) return Config.wsDotPersistent
        return Config.wsDotEmpty
    }

    // ── Reactive workspace model ─────────────────────────────────────────────
    // Always shows Config.wsCount (5) persistent slots; extra workspaces appear 1-by-1.
    // isEmpty:true slots are dimmed (cOnSurfVar); active = cPrimary; occupied = cOnSurf
    readonly property var _wsModel: {
        const _dep = Hyprland.workspaces?.values?.length  // reactivity tracker
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


    // ── Workspace scroll (shared by root MouseArea) ─────────────────────────
    function _scrollWorkspace(delta) {
        if (!Config.wsScrollSwitch) return
        const cur = Hyprland.focusedMonitor?.activeWorkspace?.id ?? 1
        const maxOccupied = Hyprland.workspaces?.values
            ? Hyprland.workspaces.values.reduce((max, w) => {
                  return (w.id > 0 && w.name !== "hidden" && w.id > max) ? w.id : max
              }, Config.wsCount)
            : Config.wsCount
        let target
        if (delta > 0) {
            target = cur - 1
            if (target < 1) target = maxOccupied
        } else {
            target = cur + 1
            if (target > maxOccupied) target = 1
        }
        Hyprland.dispatch("hl.dsp.focus({ workspace = " + target + " })")
    }

    // ── Horizontal layout ────────────────────────────────────────────────────

    // Full-module scroll — covers gaps between buttons and margin spacers.
    // Clicks pass through (propagateComposedEvents) so per-button click still works.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: ev => root._scrollWorkspace(ev.angleDelta.y)
    }

    Row {
        id: wsRow
        visible: !root.vertical
        anchors.centerIn: parent
        spacing: Config.wsSpacing

        // Left margin spacer
        Item { width: Config.wsMarginLeft; height: 1; visible: Config.wsMarginLeft > 0 }

        // Regular + persistent workspaces
        Repeater {
            id: wsRepeater
            model: root._wsModel
            delegate: Row {
                required property var modelData
                required property int  index
                readonly property int  _slot: modelData.id
                spacing: 0

                // ── Optional separator before this button (skip index 0) ────
                Item {
                    visible: Config.wsSeparators && root._wsModel.length > 1 && parent.index > 0
                    // Total width = pad-left + glyph + pad-right
                    implicitWidth:  Config.wsSeparatorPadLeft + sepTxt.implicitWidth + Config.wsSeparatorPadRight
                    implicitHeight: Config.moduleHeight

                    Text {
                        id: sepTxt
                        x: Config.wsSeparatorPadLeft
                        anchors.verticalCenter: parent.verticalCenter
                        text:           Config.wsSeparatorGlyph
                        color:          Config.wsSeparatorColor
                        font.family:    Config.fontFamily
                        font.pixelSize: Config.wsSeparatorSize
                    }
                }

                // ── Workspace button ─────────────────────────────────────────
                //  Width is derived from the text's implicit width so wsSpacing:0
                //  truly produces no gap between glyphs.
                Item {
                    id: wsBtn
                    implicitWidth:  wsGlyph.implicitWidth + Config.wsPadLeft + Config.wsPadRight
                    implicitHeight: Config.moduleHeight

                    Text {
                        id: wsGlyph
                        anchors.centerIn: parent
                        text: root._wsStateIcon(wsBtn.parent.modelData)
                        color: root._wsColor(wsBtn.parent.modelData)
                        opacity: root._wsOpacity(wsBtn.parent.modelData)
                        font.family: Config.fontFamily
                        font.pixelSize: Config.wsGlyphSize
                        font.weight: Config.fontWeight
                        Behavior on color { ColorAnimation { duration: Config.hoverDuration } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: {
                            var pt = mapToItem(null, 0, 0)
                            WorkspacesPopupState.hoverWorkspace(wsBtn.parent._slot, pt.x, width)
                        }
                        onExited: WorkspacesPopupState.leaveWorkspace(wsBtn.parent._slot)
                        onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + wsBtn.parent._slot + " })")
                        onWheel: ev => root._scrollWorkspace(ev.angleDelta.y)
                    }
                }
            }
        }

        // Right margin spacer
        Item { width: Config.wsMarginRight; height: 1; visible: Config.wsMarginRight > 0 }
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
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: {
                        var pt = mapToItem(null, 0, 0)
                        WorkspacesPopupState.hoverWorkspace(parent.modelData.id, pt.x, width)
                    }
                    onExited: WorkspacesPopupState.leaveWorkspace(parent.modelData.id)
                    onClicked: Hyprland.dispatch("hl.dsp.focus({ workspace = " + parent.modelData.id + " })")
                }
            }
        }
    }
}
