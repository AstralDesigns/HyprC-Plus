import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "."

PanelWindow {
    id: popup

    WlrLayershell.namespace:     "quickshell"
    WlrLayershell.layer:         WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    anchors.left:   false
    anchors.right:  false
    anchors.top:    false
    anchors.bottom: false

    // ── Deferred-destroy animation pattern ──────────────────────────────
    property bool _stateVisible: RecorderPopupState.visible
    Timer { id: _recExitDelay; interval: 220; repeat: false }
    visible: _stateVisible || _recExitDelay.running
    on_StateVisibleChanged: { if (!_stateVisible) _recExitDelay.restart() }
    color:   "transparent"

    implicitWidth:  card.width
    implicitHeight: card.height

    // ── Click-outside dismissal ───────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: RecorderPopupState.hide()
    }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        focus: true

        property int _focusedIndex: 0

        Connections {
            target: RecorderPopupState
            function onStepChanged()    { card._focusedIndex = 0 }
            function onVisibleChanged() {
                if (RecorderPopupState.visible) {
                    card._focusedIndex = 0
                    card.forceActiveFocus()
                }
            }
        }

        Keys.onPressed: function(event) {
            const step = RecorderPopupState.step
            let count = 0
            let activate = null
            let goBack = null

            if (step === "audio") {
                count = 3
                const modes = ["mic", "system", "none"]
                activate = function(idx) {
                    if (idx < 3) RecorderPopupState.pickAudio(modes[idx])
                }
            } else if (step === "region") {
                count = 3
                const regions = ["output", "region"]
                activate = function(idx) {
                    if (idx < 2) RecorderPopupState.pickRegion(regions[idx])
                    else RecorderPopupState.step = "audio"
                }
                goBack = function() { RecorderPopupState.step = "audio" }
            }

            if (count === 0) return

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                if (activate) activate(card._focusedIndex)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                if (goBack) goBack()
                else RecorderPopupState.hide()
                event.accepted = true
            } else if (event.key === Qt.Key_Up   || event.key === Qt.Key_K
                    || event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                card._focusedIndex = (card._focusedIndex - 1 + count) % count
                event.accepted = true
            } else if (event.key === Qt.Key_Down  || event.key === Qt.Key_J
                    || event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                card._focusedIndex = (card._focusedIndex + 1) % count
                event.accepted = true
            }
        }

        width:  230
        height: col.height + 48

        color:        Theme.background
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)
        radius:       20

        opacity: popup._stateVisible ? 1.0 : 0.0
        scale:   popup._stateVisible ? 1.0 : 0.92
        transformOrigin: Item.Center
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: col
            anchors {
                top:              parent.top
                horizontalCenter: parent.horizontalCenter
                topMargin:        20
            }
            width: parent.width - 32
            spacing: 0

            // ── Header icon ───────────────────────────────────────────
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: "󰑋"
                color: Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.9)
                font.family:    Config.fontFamily
                font.pixelSize: Config.glyphSize + 4
                Layout.bottomMargin: 4
            }

            // ── Header text ───────────────────────────────────────────
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: {
                    switch (RecorderPopupState.step) {
                        case "audio":  return "Audio Source"
                        case "region": return "Record Area"
                        default:       return "Screen Record"
                    }
                }
                color:          Theme.text
                font.family:    Config.labelFont
                font.pixelSize: Config.infoFontSize + 1
                font.weight:    Font.DemiBold
                Layout.bottomMargin: 12
            }

            // ── Step: audio ───────────────────────────────────────────
            ColumnLayout {
                visible: RecorderPopupState.step === "audio"
                Layout.fillWidth: true
                spacing: 6
                SsBtn {
                    Layout.fillWidth: true
                    label: "󰍬  With Microphone"
                    highlighted: card._focusedIndex === 0
                    onActivated: RecorderPopupState.pickAudio("mic")
                }
                SsBtn {
                    Layout.fillWidth: true
                    label: "󰕾  System Audio"
                    highlighted: card._focusedIndex === 1
                    onActivated: RecorderPopupState.pickAudio("system")
                }
                SsBtn {
                    Layout.fillWidth: true
                    label: "󰍭  No Audio"
                    highlighted: card._focusedIndex === 2
                    onActivated: RecorderPopupState.pickAudio("none")
                }
            }

            // ── Step: region ──────────────────────────────────────────
            ColumnLayout {
                visible: RecorderPopupState.step === "region"
                Layout.fillWidth: true
                spacing: 6
                SsBtn {
                    Layout.fillWidth: true
                    label: "󰍹  Entire Display"
                    highlighted: card._focusedIndex === 0
                    onActivated: RecorderPopupState.pickRegion("output")
                }
                SsBtn {
                    Layout.fillWidth: true
                    label: "󰹑  Select Region"
                    highlighted: card._focusedIndex === 1
                    onActivated: RecorderPopupState.pickRegion("region")
                }
                SsBtn {
                    Layout.fillWidth: true
                    label: "  Back"
                    accent: false
                    highlighted: card._focusedIndex === 2
                    onActivated: RecorderPopupState.step = "audio"
                }
            }
        }
    }

    // ── Pop-in animation ──────────────────────────────────────────────────────
    NumberAnimation {
        target: card; property: "scale"
        from: 0.92; to: 1.0; duration: 150; easing.type: Easing.OutCubic
        running: popup.visible
    }
    NumberAnimation {
        target: card; property: "opacity"
        from: 0.0; to: 1.0; duration: 150; easing.type: Easing.OutCubic
        running: popup.visible
    }
}
