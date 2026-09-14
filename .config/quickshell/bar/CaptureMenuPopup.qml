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
    property bool _stateVisible: CaptureMenuState.visible
    Timer { id: _exitDelay; interval: 220; repeat: false }
    visible: _stateVisible || _exitDelay.running
    on_StateVisibleChanged: { if (!_stateVisible) _exitDelay.restart() }
    color:   "transparent"

    implicitWidth:  card.width
    implicitHeight: card.height

    // ── Click-outside dismissal ───────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: CaptureMenuState.hide()
    }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        focus: true

        property int _focusedIndex: 0

        Connections {
            target: CaptureMenuState
            function onVisibleChanged() {
                if (CaptureMenuState.visible) {
                    card._focusedIndex = 0
                    card.forceActiveFocus()
                }
            }
        }

        Component.onCompleted: card.forceActiveFocus()

        function triggerAction(idx) {
            CaptureMenuState.hide()
            if (idx === 0) {
                // Screenshot
                ScreenshotPopupState.show()
            } else {
                // Screen Recorder
                if (RecorderPopupState.isRecording) {
                    RecorderPopupState.stopRecording()
                } else {
                    RecorderPopupState.reset()
                    RecorderPopupState.show()
                }
            }
        }

        Keys.onPressed: function(event) {
            const count = 2

            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                card.triggerAction(card._focusedIndex)
                event.accepted = true
            } else if (event.key === Qt.Key_Escape) {
                CaptureMenuState.hide()
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

        // Animate in/out with opacity + scale
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
                text:    "󰹑"
                color:   Theme.cPrimary
                font.family:    Config.fontFamily
                font.pixelSize: Config.glyphSize + 4
                Layout.bottomMargin: 4
            }

            // ── Header text ───────────────────────────────────────────
            Text {
                Layout.alignment: Qt.AlignHCenter
                text:           "Capture"
                color:          Theme.text
                font.family:    Config.labelFont
                font.pixelSize: Config.infoFontSize + 1
                font.weight:    Font.DemiBold
                Layout.bottomMargin: 14
            }

            // ── Action Buttons ────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                SsBtn {
                    Layout.fillWidth: true
                    label: "󰹑  Screenshot"
                    highlighted: card._focusedIndex === 0
                    onHovered:   card._focusedIndex = 0
                    onActivated: card.triggerAction(0)
                }

                SsBtn {
                    Layout.fillWidth: true
                    label: RecorderPopupState.isRecording ? "󰓛  Stop Recording" : "󰑋  Screen Recorder"
                    highlighted: card._focusedIndex === 1
                    onHovered:   card._focusedIndex = 1
                    accent: !RecorderPopupState.isRecording
                    onActivated: card.triggerAction(1)
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
