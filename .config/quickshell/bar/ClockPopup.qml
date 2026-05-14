pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ═══════════════════════════════════════════════════════════════════════════
//  ClockPopup.qml — minimal clock popup, hyprcandy quickshell edition
//
//  Left-click on the Clock bar module → toggle this popup.
//  Shows only the current time in C059 Bold Italic with the
//  hour-matched nerd-font icon. Dismisses on focus change.
// ═══════════════════════════════════════════════════════════════════════════
PanelWindow {
    id: clkWin

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap:    Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot: Config.outerMarginBottom + Config.barHeight + 6

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }

    implicitWidth:  clkPanel.implicitWidth  + 8
    implicitHeight: clkPanel.implicitHeight + 8

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell:clock-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    visible: ClockPopupState.visible

    // ── Dismiss on focus change ───────────────────────────────────────────
    // BUG FIX: guard with typeof check (same pattern as ControlCenterPopup,
    // NotificationsPopup, SystemMonitorPopup) to avoid the
    // "HyprlandFocusedClient is not defined" ReferenceError.
    Connections {
        target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                ClockPopupState.close()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onClicked: ClockPopupState.close() }

    // ── Clock icon logic (mirrors Clock.qml) ─────────────────────────────
    function _clockIcon() {
        const h12     = new Date().getHours() % 12 || 12
        const filled  = ["󱑋","󱑌","󱑍","󱑎","󱑏","󱑐","󱑑","󱑒","󱑓","󱑔","󱑕","󱑖"]
        const outline = ["󱑋","󱑌","󱑍","󱑎","󱑏","󱑐","󱑑","󱑒","󱑓","󱑔","󱑕","󱑖"]
        // Simple day/night: day 06:00–18:59
        const h = new Date().getHours()
        return (h >= 6 && h < 19) ? filled[h12 - 1] : outline[h12 - 1]
    }

    property string _time: Qt.formatDateTime(new Date(), "HH:mm:ss")
    property string _icon: _clockIcon()

    // Tick every second
    Timer {
        interval: 1000; running: ClockPopupState.visible; repeat: true
        onTriggered: {
            clkWin._time = Qt.formatDateTime(new Date(), "HH:mm:ss")
            clkWin._icon = clkWin._clockIcon()
        }
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: clkPanel
        anchors.horizontalCenter: parent.horizontalCenter

        implicitWidth:  clkRow.implicitWidth  + 32
        implicitHeight: clkRow.implicitHeight + 20

        radius: 20
        clip: true
        color:  Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.42)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.40)

        // Glass sheen — transparent base; clip:true on parent clips to rounded corners
        Rectangle {
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 35
            radius: 35
            color: "transparent"
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(1,1,1,0.06) }
                GradientStop { position: 1.0; color: Qt.rgba(1,1,1,0.00) }
            }
        }

        Row {
            id: clkRow
            anchors.centerIn: parent
            spacing: 12

            Text {
                text: clkWin._icon
                color: Theme.cPrimary
                font.family: Config.fontFamily
                font.pixelSize: Config.clockIconSize !== undefined ? Config.clockIconSize : 32
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: clkWin._time
                color: Theme.cInverseSurface
                font.family: "C059"
                font.italic: true
                font.weight: Font.Bold
                font.pixelSize: Config.clockTextSize !== undefined ? Config.clockTextSize : 38
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
