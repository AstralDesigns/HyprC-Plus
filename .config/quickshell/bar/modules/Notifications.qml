import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  notifText.implicitWidth + Config.modPadH * 2 + (countBadge.visible ? 6 : 0)
    implicitHeight: Config.moduleHeight

    property bool   _dnd:    false
    property string _alt:    "none"   // mirrors notification shell's _waybarIconKey()
    property int    _count:  0

    // Icon set — mirrors the shell's _waybarIconGlyph map exactly
    readonly property string _icon: {
        switch (_alt) {
            case "notification":              return "󰅸"   // not-dnd, has notifs
            case "none":                      return "󰂜"   // not-dnd, empty
            case "dnd-notification":          return "󱅫"   // dnd on, has notifs
            case "dnd-none":                  return "󰂠"   // dnd on, empty
            case "inhibited-notification":    return "󰅸"
            case "inhibited-none":            return "󱏬"
            case "dnd-inhibited-notification":return "󱅫"
            case "dnd-inhibited-none":        return "󱏫"
            default:                          return "󰂜"
        }
    }

    readonly property color _color: {
        if (_dnd)           return Config.dimColor
        if (_count > 0)     return Config.glyphColor
        return Config.glyphColor
    }

    // Read the state file that notifications/shell.qml writes
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) +
              "/quickshell/notifications/waybar-state.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d   = JSON.parse(text())
                root._alt   = d.alt   || "none"
                root._dnd   = (d.alt  || "").includes("dnd")
                root._count = parseInt(d.count) || 0
            } catch(e) {}
        }
    }

    // Bell / DnD glyph
    Text {
        id: notifText
        anchors.centerIn: parent
        text:  root._icon
        color: root._color
        font.family:    Config.fontFamily
        font.pixelSize: Config.fontSize
        font.weight:    Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // Unread count badge — same style as the history panel counter
    Rectangle {
        id: countBadge
        visible: root._count > 0
        anchors { top: parent.top; right: parent.right; topMargin: 3; rightMargin: 1 }
        width: countLabel.implicitWidth + 4
        height: 10; radius: 5
        color: root._dnd
            ? Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.75)
            : Theme.cPrimary

        Text {
            id: countLabel
            anchors.centerIn: parent
            text: root._count > 99 ? "99+" : root._count.toString()
            color: root._dnd ? Theme.cInverseOnSurface : Theme.cOnPrimary
            font.pixelSize: 7
            font.weight: Font.Bold
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(ev) {
            if (ev.button === Qt.RightButton)
                dndProc.running = true
            else
                histProc.running = true
        }
    }

    Process { id: histProc; command: [Config.scriptsDir + "/notifications.sh"]; running: false }
    Process { id: dndProc;  command: ["qs", "ipc", "-c", "notifications", "call", "notifications", "dndToggle"]; running: false }
}
