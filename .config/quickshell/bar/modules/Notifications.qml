import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  notifText.implicitWidth + Config.modPadH * 2 + (countBadge.visible ? 6 : 0)
    implicitHeight: Config.moduleHeight

    // Read state directly from the in-process singleton
    readonly property string _alt:   NotificationsState._waybarIconKey()
    readonly property bool   _dnd:   NotificationsState.dndEnabled
    readonly property int    _count: NotificationsState.history.length

    readonly property string _icon: {
        switch (_alt) {
            case "notification":              return "󰅸"
            case "none":                      return "󰂜"
            case "dnd-notification":          return "󱅫"
            case "dnd-none":                  return "󰂠"
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

    Text {
        id: notifText
        anchors.centerIn: parent
        text:  root._icon
        color: root._color
        font.family:    Config.fontFamily
        font.pixelSize: Config.glyphSize
        font.weight:    Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
    }

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
            color: root._dnd ? Theme.cOnPrimary : Theme.cOnPrimary
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
                NotificationsState.dndToggle()
            else
                NotificationsState.toggle()
        }
    }
}
