pragma ComponentBehavior: Bound
// NotificationCenter.qml
// Standalone notification center + toast overlay.
// Import this alongside shell.qml or merge into ShellRoot.
// Reads colors + notif state from root (ShellRoot must expose them).
//
// Required root properties:
//   cPrimary, cOnPrim, cSurfHi, cSurfMid, cOnSurf, cOnSurfVar, cOutVar, cErr, cPanelBg
//   _m3onSecondary (string hex)
//   notifCenterVisible (bool, writable)
//   notifHistory (var[])
//   notifQueue (var[])
//   notifDismiss(id)
//   notifClearHistory()
//   waybarAtBottom (bool)
//   waybarSideMargin (real)

import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ── Notification daemon bridge ─────────────────────────────────────────────────
// Bridges freedesktop.org org.freedesktop.Notifications D-Bus into the shell's
// notification system. Runs as a separate process that writes IPC messages.
// Launch via: ~/.config/hyprcandy/scripts/notif-bridge.sh
//
// This file also defines the visual notification center panel and toast overlay.
// It is designed to be included in a ShellRoot that exposes the properties listed above.

// ════════════════════════════════════════════════════════════════════
// NOTIFICATION CENTER PANEL
// ════════════════════════════════════════════════════════════════════
PanelWindow {
    id: notifPanel

    // ── Required injected properties (set by parent ShellRoot) ──────
    // The parent must assign these after instantiation or via Binding.
    // For standalone usage, set them here with defaults.
    property color cPrimary:    "#f7c382"
    property color cOnPrim:     "#1d1100"
    property color cSurfHi:     "#1b1611"
    property color cOnSurf:     "#f1e1d2"
    property color cOnSurfVar:  "#d1bca6"
    property color cOutVar:     "#5f5242"
    property color cErr:        "#ffb4ab"
    property string _m3onSec:   "#100a00"
    property bool   _waybarBot: false
    property real   _sideMargin: 12

    property bool _centerVisible: false
    property var  _history: []
    property var  _queue: []

    signal dismissId(int id)
    signal clearAll()
    signal actionTriggered(string cmd)

    // ── Window config ─────────────────────────────────────────────────
    visible: _centerVisible
    WlrLayershell.namespace: "quickshell:notif-center"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors {
        top:    !_waybarBot
        bottom:  _waybarBot
        right:   true
    }
    margins { top: 2; right: _sideMargin; bottom: 2 }
    width: 380
    height: Math.min(720, ncCol.implicitHeight + 40)
    color: "transparent"

    HyprlandFocusGrab {
        id: ncGrab; windows: [notifPanel]; active: false
        onCleared: { if (!active) notifPanel._centerVisible = false }
    }
    onVisibleChanged: {
        if (visible) ncDelayTimer.restart()
        else ncGrab.active = false
    }
    Timer { id: ncDelayTimer; interval: 80; repeat: false
        onTriggered: { if (notifPanel.visible) ncGrab.active = true }
    }

    // ── Panel body ────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: Qt.rgba(
            Qt.color(notifPanel._m3onSec).r,
            Qt.color(notifPanel._m3onSec).g,
            Qt.color(notifPanel._m3onSec).b, 0.88)
        border.width: 1
        border.color: Qt.rgba(notifPanel.cOutVar.r, notifPanel.cOutVar.g, notifPanel.cOutVar.b, 0.4)
        Keys.onEscapePressed: notifPanel._centerVisible = false
        focus: true
        onVisibleChanged: if (visible) forceActiveFocus()

        ColumnLayout {
            id: ncCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18 }
            spacing: 10

            // ── Header ────────────────────────────────────────────────
            RowLayout { Layout.fillWidth: true; spacing: 8
                Text {
                    text: "󰂚"; font.pixelSize: 20
                    font.family: "Symbols Nerd Font Mono"
                    color: notifPanel.cPrimary
                }
                Text {
                    text: "Notifications"
                    color: notifPanel.cOnSurf
                    font.pixelSize: 15; font.weight: Font.SemiBold
                    Layout.fillWidth: true
                }
                // Count badge
                Rectangle {
                    visible: notifPanel._history.length > 0
                    height: 22; radius: 11
                    width: Math.max(22, ncCountLbl.implicitWidth + 14)
                    color: Qt.rgba(notifPanel.cPrimary.r, notifPanel.cPrimary.g, notifPanel.cPrimary.b, 0.18)
                    border.width: 1
                    border.color: Qt.rgba(notifPanel.cPrimary.r, notifPanel.cPrimary.g, notifPanel.cPrimary.b, 0.4)
                    Text {
                        id: ncCountLbl
                        anchors.centerIn: parent
                        text: String(notifPanel._history.length)
                        color: notifPanel.cPrimary; font.pixelSize: 10; font.weight: Font.Bold
                    }
                }
                // Clear all
                Rectangle {
                    visible: notifPanel._history.length > 0
                    height: 26; radius: 8
                    width: clrAllLbl.implicitWidth + 20
                    color: clrAllH.containsMouse
                        ? Qt.rgba(notifPanel.cErr.r, notifPanel.cErr.g, notifPanel.cErr.b, 0.22)
                        : "transparent"
                    border.width: 1
                    border.color: Qt.rgba(notifPanel.cErr.r, notifPanel.cErr.g, notifPanel.cErr.b, 0.45)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        id: clrAllLbl
                        anchors.centerIn: parent
                        text: "Clear all"
                        font.pixelSize: 10; color: notifPanel.cErr
                    }
                    MouseArea {
                        id: clrAllH; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: notifPanel.clearAll()
                    }
                }
                // Close button
                Rectangle {
                    width: 26; height: 26; radius: 8
                    color: ncClH.containsMouse
                        ? Qt.rgba(notifPanel.cOutVar.r, notifPanel.cOutVar.g, notifPanel.cOutVar.b, 0.35)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent; text: "󰅖"
                        font.pixelSize: 13; font.family: "Symbols Nerd Font Mono"
                        color: notifPanel.cOnSurfVar
                    }
                    MouseArea {
                        id: ncClH; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: notifPanel._centerVisible = false
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(notifPanel.cOutVar.r, notifPanel.cOutVar.g, notifPanel.cOutVar.b, 0.25)
            }

            // ── Empty state ───────────────────────────────────────────
            Item {
                visible: notifPanel._history.length === 0
                Layout.fillWidth: true; height: 120
                ColumnLayout { anchors.centerIn: parent; spacing: 12
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "󰂛"; font.pixelSize: 40
                        font.family: "Symbols Nerd Font Mono"
                        color: Qt.rgba(notifPanel.cOnSurfVar.r, notifPanel.cOnSurfVar.g, notifPanel.cOnSurfVar.b, 0.3)
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: "No notifications"
                        font.pixelSize: 12; font.italic: true
                        color: Qt.rgba(notifPanel.cOnSurfVar.r, notifPanel.cOnSurfVar.g, notifPanel.cOnSurfVar.b, 0.45)
                    }
                }
            }

            // ── Notification list ──────────────────────────────────────
            Column {
                visible: notifPanel._history.length > 0
                Layout.fillWidth: true; width: parent.width; spacing: 6

                Repeater {
                    model: notifPanel._history
                    delegate: NotifCard {
                        required property var modelData
                        required property int index
                        width: parent.width
                        cPrimary:   notifPanel.cPrimary
                        cOnPrim:    notifPanel.cOnPrim
                        cSurfHi:    notifPanel.cSurfHi
                        cOnSurf:    notifPanel.cOnSurf
                        cOnSurfVar: notifPanel.cOnSurfVar
                        cOutVar:    notifPanel.cOutVar
                        cErr:       notifPanel.cErr
                        notif: modelData
                        onDismissMe: notifPanel.dismissId(modelData.id)
                        onActionFired: function(cmd) { notifPanel.actionTriggered(cmd) }
                    }
                }
            }

            Item { height: 6 }
        }
    }
}


// ════════════════════════════════════════════════════════════════════
// TOAST OVERLAY
// ════════════════════════════════════════════════════════════════════
PanelWindow {
    id: toastPanel

    property color cPrimary:   "#f7c382"
    property color cOnPrim:    "#1d1100"
    property color cSurfHi:    "#1b1611"
    property color cOnSurf:    "#f1e1d2"
    property color cOnSurfVar: "#d1bca6"
    property color cOutVar:    "#5f5242"
    property color cErr:       "#ffb4ab"
    property string _m3onSec:  "#100a00"
    property bool   _waybarBot: false
    property real   _sideMargin: 12

    property var _queue: []
    signal dismissId(int id)
    signal actionTriggered(string cmd)

    visible: _queue.length > 0
    WlrLayershell.namespace: "quickshell:toasts"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors {
        top:    !_waybarBot
        bottom:  _waybarBot
        right:   true
    }
    margins { top: 50; right: _sideMargin; bottom: 50 }
    width: 360
    height: toastStack.implicitHeight + 4
    color: "transparent"

    Column {
        id: toastStack
        anchors { top: parent.top; left: parent.left; right: parent.right }
        spacing: 6

        Repeater {
            model: toastPanel._queue
            delegate: ToastCard {
                required property var modelData
                required property int index
                width: 360
                cPrimary:   toastPanel.cPrimary
                cOnPrim:    toastPanel.cOnPrim
                cSurfHi:    toastPanel.cSurfHi
                cOnSurf:    toastPanel.cOnSurf
                cOnSurfVar: toastPanel.cOnSurfVar
                cOutVar:    toastPanel.cOutVar
                cErr:       toastPanel.cErr
                _m3onSec:   toastPanel._m3onSec
                notif: modelData
                onDismissMe: toastPanel.dismissId(modelData.id)
                onActionFired: function(cmd) { toastPanel.actionTriggered(cmd) }
            }
        }
    }
}


// ════════════════════════════════════════════════════════════════════
// NOTIFICATION CARD COMPONENT
// ════════════════════════════════════════════════════════════════════
component NotifCard: Rectangle {
    id: card

    property color cPrimary:   "#f7c382"
    property color cOnPrim:    "#1d1100"
    property color cSurfHi:    "#1b1611"
    property color cOnSurf:    "#f1e1d2"
    property color cOnSurfVar: "#d1bca6"
    property color cOutVar:    "#5f5242"
    property color cErr:       "#ffb4ab"
    property var notif: null

    signal dismissMe()
    signal actionFired(string cmd)

    height: cardCol.implicitHeight + 20
    radius: 14
    color: notif && notif.urgency === "critical"
        ? Qt.rgba(card.cErr.r, card.cErr.g, card.cErr.b, 0.12)
        : Qt.rgba(card.cSurfHi.r, card.cSurfHi.g, card.cSurfHi.b, 0.7)
    border.width: 1
    border.color: notif && notif.urgency === "critical"
        ? Qt.rgba(card.cErr.r, card.cErr.g, card.cErr.b, 0.45)
        : Qt.rgba(card.cOutVar.r, card.cOutVar.g, card.cOutVar.b, 0.28)

    // Urgency left accent bar
    Rectangle {
        x: 0; y: 12; width: 3
        height: parent.height - 24; radius: 2
        color: notif && notif.urgency === "critical" ? card.cErr
             : notif && notif.urgency === "low" ? Qt.rgba(card.cOnSurfVar.r,card.cOnSurfVar.g,card.cOnSurfVar.b,0.5)
             : card.cPrimary
    }

    ColumnLayout {
        id: cardCol
        anchors { top: parent.top; left: parent.left; right: parent.right
                  topMargin: 10; bottomMargin: 10; leftMargin: 14; rightMargin: 10 }
        spacing: 5

        RowLayout { Layout.fillWidth: true; spacing: 8
            Text {
                text: notif ? (notif.icon || "󰂚") : "󰂚"
                font.pixelSize: 17; font.family: "Symbols Nerd Font Mono"
                color: notif && notif.urgency === "critical" ? card.cErr : card.cPrimary
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 1
                Text {
                    text: notif ? notif.summary : ""
                    color: card.cOnSurf; font.pixelSize: 12; font.weight: Font.SemiBold
                    elide: Text.ElideRight; Layout.fillWidth: true
                }
                Text {
                    visible: notif ? notif.body !== "" : false
                    text: notif ? notif.body : ""
                    color: card.cOnSurfVar; font.pixelSize: 11
                    wrapMode: Text.WordWrap; Layout.fillWidth: true
                }
            }
            ColumnLayout { spacing: 2; Layout.alignment: Qt.AlignTop
                Text {
                    text: notif ? _relTime(notif.ts) : ""
                    color: Qt.rgba(card.cOnSurfVar.r,card.cOnSurfVar.g,card.cOnSurfVar.b,0.6)
                    font.pixelSize: 9
                }
                Rectangle {
                    width: 20; height: 20; radius: 6
                    color: dismissH.containsMouse
                        ? Qt.rgba(card.cOutVar.r,card.cOutVar.g,card.cOutVar.b,0.45)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text {
                        anchors.centerIn: parent; text: "󰅖"
                        font.pixelSize: 11; font.family: "Symbols Nerd Font Mono"
                        color: card.cOnSurfVar
                    }
                    MouseArea {
                        id: dismissH; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: card.dismissMe()
                    }
                }
            }
        }

        // Action buttons
        Row {
            visible: notif && notif.actions && notif.actions.length > 0
            spacing: 6
            Repeater {
                model: notif ? notif.actions : []
                delegate: Rectangle {
                    required property var modelData
                    height: 26; radius: 7
                    width: actLbl.implicitWidth + 22
                    color: actH.containsMouse
                        ? Qt.rgba(card.cPrimary.r,card.cPrimary.g,card.cPrimary.b,0.25)
                        : Qt.rgba(card.cSurfHi.r,card.cSurfHi.g,card.cSurfHi.b,0.9)
                    border.width: 1
                    border.color: Qt.rgba(card.cPrimary.r,card.cPrimary.g,card.cPrimary.b,0.42)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        id: actLbl; anchors.centerIn: parent
                        text: modelData.label || ""
                        font.pixelSize: 10; color: card.cOnSurf
                    }
                    MouseArea {
                        id: actH; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: { if (modelData.action) card.actionFired(modelData.action) }
                    }
                }
            }
        }
    }

    function _relTime(ts) {
        const d = Date.now() - ts
        if (d < 60000) return "now"
        if (d < 3600000) return Math.floor(d/60000) + "m"
        if (d < 86400000) return Math.floor(d/3600000) + "h"
        return Math.floor(d/86400000) + "d"
    }
}


// ════════════════════════════════════════════════════════════════════
// TOAST CARD COMPONENT (slides in from right, auto-dismiss progress)
// ════════════════════════════════════════════════════════════════════
component ToastCard: Item {
    id: toast

    property color cPrimary:   "#f7c382"
    property color cOnPrim:    "#1d1100"
    property color cSurfHi:    "#1b1611"
    property color cOnSurf:    "#f1e1d2"
    property color cOnSurfVar: "#d1bca6"
    property color cOutVar:    "#5f5242"
    property color cErr:       "#ffb4ab"
    property string _m3onSec:  "#100a00"
    property var notif: null

    signal dismissMe()
    signal actionFired(string cmd)

    height: toastRect.height
    opacity: 1.0

    // Slide in from right
    property real slideX: width
    x: slideX
    Component.onCompleted: slideAnim.start()
    NumberAnimation {
        id: slideAnim; target: toast; property: "slideX"
        from: 380; to: 0; duration: 260; easing.type: Easing.OutCubic
    }

    // Dismiss animation
    function animDismiss() {
        slideOutAnim.start()
    }
    SequentialAnimation {
        id: slideOutAnim
        NumberAnimation { target: toast; property: "slideX"; to: 400; duration: 220; easing.type: Easing.InCubic }
        ScriptAction { script: toast.dismissMe() }
    }

    Rectangle {
        id: toastRect
        width: 360
        height: tCardCol.implicitHeight + 20
        radius: 16
        color: notif && notif.urgency === "critical"
            ? Qt.rgba(toast.cErr.r,toast.cErr.g,toast.cErr.b,0.15)
            : Qt.rgba(Qt.color(toast._m3onSec).r, Qt.color(toast._m3onSec).g, Qt.color(toast._m3onSec).b, 0.92)
        border.width: notif && notif.urgency === "critical" ? 2 : 1
        border.color: notif && notif.urgency === "critical"
            ? Qt.rgba(toast.cErr.r,toast.cErr.g,toast.cErr.b,0.7)
            : Qt.rgba(toast.cOutVar.r,toast.cOutVar.g,toast.cOutVar.b,0.42)

        // Critical pulse
        SequentialAnimation on border.color {
            running: notif && notif.urgency === "critical"; loops: Animation.Infinite
            ColorAnimation { to: Qt.rgba(toast.cErr.r,toast.cErr.g,toast.cErr.b,0.7); duration: 700 }
            ColorAnimation { to: Qt.rgba(toast.cErr.r,toast.cErr.g,toast.cErr.b,0.2); duration: 700 }
        }

        // Left accent
        Rectangle {
            x: 0; y: 12; width: 3; height: parent.height - 24; radius: 2
            color: notif && notif.urgency === "critical" ? toast.cErr : toast.cPrimary
        }

        ColumnLayout {
            id: tCardCol
            anchors { top: parent.top; left: parent.left; right: parent.right
                      topMargin: 12; bottomMargin: 12; leftMargin: 16; rightMargin: 12 }
            spacing: 6

            RowLayout { Layout.fillWidth: true; spacing: 10
                Text {
                    text: notif ? (notif.icon || "󰂚") : "󰂚"
                    font.pixelSize: 20; font.family: "Symbols Nerd Font Mono"
                    color: notif && notif.urgency === "critical" ? toast.cErr : toast.cPrimary
                }
                ColumnLayout { Layout.fillWidth: true; spacing: 2
                    Text {
                        text: notif ? notif.summary : ""
                        color: toast.cOnSurf; font.pixelSize: 13; font.weight: Font.SemiBold
                        elide: Text.ElideRight; Layout.fillWidth: true
                    }
                    Text {
                        visible: notif ? notif.body !== "" : false
                        text: notif ? notif.body : ""
                        color: toast.cOnSurfVar; font.pixelSize: 11
                        wrapMode: Text.WordWrap; Layout.fillWidth: true
                    }
                }
                Rectangle {
                    width: 22; height: 22; radius: 7
                    color: tdH.containsMouse
                        ? Qt.rgba(toast.cOutVar.r,toast.cOutVar.g,toast.cOutVar.b,0.4)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text {
                        anchors.centerIn: parent; text: "󰅖"
                        font.pixelSize: 12; font.family: "Symbols Nerd Font Mono"
                        color: toast.cOnSurfVar
                    }
                    MouseArea {
                        id: tdH; anchors.fill: parent
                        hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: toast.animDismiss()
                    }
                }
            }

            // Action buttons
            Row {
                visible: notif && notif.actions && notif.actions.length > 0
                spacing: 6
                Repeater {
                    model: notif ? notif.actions : []
                    delegate: Rectangle {
                        required property var modelData
                        height: 26; radius: 7; width: tActLbl.implicitWidth + 22
                        color: tActH.containsMouse
                            ? Qt.rgba(toast.cPrimary.r,toast.cPrimary.g,toast.cPrimary.b,0.28)
                            : Qt.rgba(toast.cSurfHi.r,toast.cSurfHi.g,toast.cSurfHi.b,0.8)
                        border.width: 1
                        border.color: Qt.rgba(toast.cPrimary.r,toast.cPrimary.g,toast.cPrimary.b,0.4)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { id: tActLbl; anchors.centerIn: parent; text: modelData.label || ""; font.pixelSize: 10; color: toast.cOnSurf }
                        MouseArea {
                            id: tActH; anchors.fill: parent
                            hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: { if (modelData.action) toast.actionFired(modelData.action) }
                        }
                    }
                }
            }

            // Auto-dismiss countdown bar
            Item {
                Layout.fillWidth: true; height: 3
                Rectangle {
                    anchors.fill: parent; radius: 2
                    color: Qt.rgba(toast.cOutVar.r,toast.cOutVar.g,toast.cOutVar.b,0.2)
                }
                Rectangle {
                    id: progressBar
                    height: parent.height; radius: 2
                    color: notif && notif.urgency === "critical" ? toast.cErr : toast.cPrimary
                    width: parent.width
                    // Shrink over the lifetime of the toast
                    NumberAnimation on width {
                        running: true
                        from: toastRect.width - 28  // account for margins
                        to: 0
                        duration: notif && notif.urgency === "critical" ? 12000 : 6000
                        easing.type: Easing.Linear
                        onFinished: toast.animDismiss()
                    }
                }
            }
        }
    }
}
