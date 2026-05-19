import QtQuick
import QtQuick.Layouts
import Quickshell.Services.SystemTray
import ".."

// ── System-tray toggle button ────────────────────────────────────────────────
// Sits inside the Updates/Cafeine/PowerProfiles/Rofi grouped island.
// Clicking it opens/closes SysTrayPopup (a separate PanelWindow).
// The icon shows the nerd-font tray glyph; badge shows item count when > 0.
Item {
    id: root

    // Injected by Bar.qml (kept for API compatibility; not needed for the popup)
    property var  rootWindow
    property real trayMaxW: -1

    Layout.alignment: Qt.AlignVCenter

    implicitWidth:  icon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    // ── Tray icon glyph ──────────────────────────────────────────────────────
    Text {
        id: icon
        anchors.centerIn: parent
        text:  "󰧈"   // nf-md-dots_grid 󱗼 — generic "system tray" glyph 󰧈 󱊔
        color: SysTrayPopupState.visible ? Theme.cPrimary : Config.glyphColor
        font.family:    Config.fontFamily
        font.pixelSize: Config.fontSize
        font.weight:    Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // ── Item-count badge (shown when popup is closed and items > 0) ──────────
    Rectangle {
        id: badge
        visible: !SysTrayPopupState.visible && SystemTray.items.values.length > 0
        anchors { top: icon.top; right: icon.right; topMargin: -3; rightMargin: -4 }
        width:  badgeTxt.implicitWidth + 4
        height: 12
        radius: 6
        color:  Theme.cPrimary

        Text {
            id: badgeTxt
            anchors.centerIn: parent
            text:           SystemTray.items.values.length
            color:          Theme.cOnPrimary
            font.family:    Config.labelFont
            font.pixelSize: 9
            font.weight:    Font.Bold
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        onClicked: {
            // Pass the horizontal centre of this button in screen-space
            const cx = root.mapToItem(null, root.width / 2, 0).x
            SysTrayPopupState.toggle(cx)
        }
    }
}
