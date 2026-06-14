import QtQuick
import QtQuick.Layouts
import Quickshell
import "."

PanelWindow {
    id: popup

    anchors.left:   false
    anchors.right:  false
    anchors.top:    false
    anchors.bottom: false

    visible: ScreenshotPopupState.visible
    color:   "transparent"

    implicitWidth:  card.width
    implicitHeight: card.height

    // ── Click-outside dismissal ───────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: ScreenshotPopupState.hide()
    }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent

        // Width fixed; height driven only by the visible step column
        width:  220
        height: col.height + 48

        color:        Theme.background
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)
        radius:       20

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
                visible: ScreenshotPopupState.step !== "running"
                        && ScreenshotPopupState.step !== "countdown"
                // hide but still take space so header text doesn't jump
                // actually collapse it when running
                text:    ""
                color:   Theme.text
                font.family:    Config.fontFamily
                font.pixelSize: Config.glyphSize + 4
                Layout.bottomMargin: 4
            }

            // ── Header text ───────────────────────────────────────────
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: ScreenshotPopupState.step !== "countdown"
                text: {
                    switch (ScreenshotPopupState.step) {
                        case "timing":  return "Screenshot"
                        case "delay":   return "Choose Delay"
                        case "region":  return "Capture Area"
                        case "action":  return "Save As"
                        case "running": return "Capturing…"
                        default:        return "Screenshot"
                    }
                }
                color:          Theme.text
                font.family:    Config.labelFont
                font.pixelSize: Config.infoFontSize + 1
                font.weight:    Font.DemiBold
                Layout.bottomMargin: 12
            }

            // ── Step: timing ──────────────────────────────────────────
            ColumnLayout {
                visible: ScreenshotPopupState.step === "timing"
                Layout.fillWidth: true
                spacing: 6
                SsBtn { Layout.fillWidth: true; label: "  Immediate"; onActivated: ScreenshotPopupState.pickTiming(0) }
                SsBtn { Layout.fillWidth: true; label: "  Delayed";   onActivated: ScreenshotPopupState.step = "delay" }
            }

            // ── Step: delay ───────────────────────────────────────────
            ColumnLayout {
                visible: ScreenshotPopupState.step === "delay"
                Layout.fillWidth: true
                spacing: 6
                SsBtn { Layout.fillWidth: true; label: "󱦟  5 seconds";  onActivated: ScreenshotPopupState.pickTiming(5)  }
                SsBtn { Layout.fillWidth: true; label: "󱦟  10 seconds"; onActivated: ScreenshotPopupState.pickTiming(10) }
                SsBtn { Layout.fillWidth: true; label: "󱦟  20 seconds"; onActivated: ScreenshotPopupState.pickTiming(20) }
                SsBtn { Layout.fillWidth: true; label: "󱦟  30 seconds"; onActivated: ScreenshotPopupState.pickTiming(30) }
                SsBtn { Layout.fillWidth: true; label: "󱦟  60 seconds"; onActivated: ScreenshotPopupState.pickTiming(60) }
                SsBtn { Layout.fillWidth: true; label: "  Back"; accent: false; onActivated: ScreenshotPopupState.step = "timing" }
            }

            // ── Step: region ──────────────────────────────────────────
            ColumnLayout {
                visible: ScreenshotPopupState.step === "region"
                Layout.fillWidth: true
                spacing: 6
                SsBtn { Layout.fillWidth: true; label: "󰍹  Entire Display"; onActivated: ScreenshotPopupState.pickRegion("output") }
                SsBtn { Layout.fillWidth: true; label: "  Active Window";   onActivated: ScreenshotPopupState.pickRegion("active") }
                SsBtn { Layout.fillWidth: true; label: "  Selection";       onActivated: ScreenshotPopupState.pickRegion("region") }
                SsBtn { Layout.fillWidth: true; label: "  Back"; accent: false; onActivated: ScreenshotPopupState.step = "timing" }
            }

            // ── Step: action ──────────────────────────────────────────
            ColumnLayout {
                visible: ScreenshotPopupState.step === "action"
                Layout.fillWidth: true
                spacing: 6
                SsBtn { Layout.fillWidth: true; label: "  Copy";         onActivated: ScreenshotPopupState.pickAction("copy")     }
                SsBtn { Layout.fillWidth: true; label: "  Save";         onActivated: ScreenshotPopupState.pickAction("save")     }
                SsBtn { Layout.fillWidth: true; label: "  Copy & Save";  onActivated: ScreenshotPopupState.pickAction("copysave") }
                SsBtn { Layout.fillWidth: true; label: "  Edit (satty)"; onActivated: ScreenshotPopupState.pickAction("edit")     }
                SsBtn { Layout.fillWidth: true; label: "  Back"; accent: false; onActivated: ScreenshotPopupState.step = "region" }
            }

            // ── Step: countdown ───────────────────────────────────────
            // Shown in place of the action step buttons — same card size.
            // Number displayed in CO59 Bold Italic, large enough to fill
            // roughly the same vertical space as the 5-button action step.
            ColumnLayout {
                visible: ScreenshotPopupState.step === "countdown"
                Layout.fillWidth: true
                spacing: 8

                // Big countdown number — CO59 Bold Italic
                Text {
                    Layout.alignment:    Qt.AlignHCenter
                    Layout.topMargin:    8
                    text:                ScreenshotPopupState.countdownVal.toString()
                    color:               Theme.text
                    font.family:         "C059"
                    font.pixelSize:      120
                    font.bold:           true
                    font.italic:         true

                    // Pulse animation: shrinks slightly on each tick
                    // driven by countdownVal changes
                    property int _lastVal: 0
                    onTextChanged: {
                        pulseAnim.restart()
                    }

                    NumberAnimation {
                        id: pulseAnim
                        target: parent
                        property: "scale"
                        from: 0.82; to: 1.0
                        duration: 450
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                }

                // Cancel button — same width as action step buttons
                SsBtn {
                    Layout.fillWidth:   true
                    Layout.bottomMargin: 4
                    label:  "Cancel"
                    accent: false
                    onActivated: {
                        ScreenshotPopupState.reset()
                        ScreenshotPopupState.hide()
                    }
                }
            }

            // ── Step: running ─────────────────────────────────────────
            ColumnLayout {
                visible: ScreenshotPopupState.step === "running"
                Layout.fillWidth: true
                spacing: 10
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "󰑋"
                    color: Theme.text
                    font.family:    Config.fontFamily
                    font.pixelSize: Config.glyphSize + 10
                    RotationAnimator on rotation {
                        from: 0; to: 360; duration: 1200
                        loops: Animation.Infinite
                        running: ScreenshotPopupState.step === "running"
                    }
                }
                SsBtn {
                    Layout.fillWidth: true
                    label: "Cancel"; accent: false
                    onActivated: { ScreenshotPopupState.reset(); ScreenshotPopupState.hide() }
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
