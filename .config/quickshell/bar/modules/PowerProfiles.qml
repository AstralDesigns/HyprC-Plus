import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// Power profiles daemon toggle — cycles: balanced → performance → power-saver → balanced
// Matches waybar power-profiles-daemon module icons exactly
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: ppIcon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    property string _profile: "balanced"

    readonly property string _icon: {
        switch (root._profile) {
            case "performance": return "󰠠"
            case "power-saver":  return "󱤅"
            default:             return "󰚀"   // balanced
        }
    }
    readonly property color _color: {
        switch (root._profile) {
            case "performance": return Theme.cWc6
            case "power-saver":  return Theme.cWc5
            default:             return Config.rightGroupColor
        }
    }

    // Human-readable profile name for the hover tooltip's mode line.
    readonly property string _profileLabel: {
        switch (root._profile) {
            case "performance": return "Performance"
            case "power-saver":  return "Power Save"
            default:             return "Balanced"
        }
    }

    // Hover tooltip text, kept as a binding so a profile change (click-cycle or
    // the 10 s poll picking up an external set) refreshes an already-open tooltip
    // via onTipTextChanged -> BarTipState.refresh instead of re-enter.
    readonly property string tipText: "Left-click: Cycle power profile\nMode: " + root._profileLabel
    onTipTextChanged: if (Config.tipPowerProfiles) BarTipState.refresh(root.tipText, root)

    // Poll current profile on startup and every 10 s
    Process {
        id: getProc
        command: ["powerprofilesctl", "get"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) { const p = l.trim(); if (p) root._profile = p }
        }
    }
    Timer {
        interval: 10000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!getProc.running) getProc.running = true
    }

    // Cycle to next profile
    Process {
        id: cycleProc
        property string _next: "balanced"
        command: ["powerprofilesctl", "set", cycleProc._next]
        running: false
        onExited: if (!getProc.running) getProc.running = true
    }
    function _cycleProfile() {
        const order = ["balanced", "performance", "power-saver"]
        const next  = order[(order.indexOf(root._profile) + 1) % order.length]
        cycleProc._next = next
        if (!cycleProc.running) cycleProc.running = true
    }

    Text {
        id: ppIcon
        anchors.centerIn: parent
        text: root._icon
        color: root._color
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
        font.weight: Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (Config.tipPowerProfiles) BarTipState.show(root.tipText, parent)
        onExited: BarTipState.hide(parent)
        onClicked: root._cycleProfile()
    }
}
