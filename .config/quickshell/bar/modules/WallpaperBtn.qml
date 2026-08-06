import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: icon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    Text {
        id: icon
        anchors.centerIn: parent
        text: "󰋯"
        color: Config.glyphColor
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    Process { id: wpPickProc;   command: [Config.scriptsDir + "/wallpaper.sh"];                                            running: false }
    Process { id: wpNextProc;   command: [Config.home + "/.config/quickshell/wallpaper/wallpaper-cycle.sh", "--next"];     running: false }
    Process { id: wpPrevProc;   command: [Config.home + "/.config/quickshell/wallpaper/wallpaper-cycle.sh", "--prev"];     running: false }
    Process { id: wpReColorProc; command: [Config.home + "/.config/hyprcandy/hooks/wallpaper_integration.sh"]; running: false }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton

        // Left-click: launch picker on press so it feels as instant as OverviewBtn.
        // Using onPressed instead of onClicked avoids the click-disambiguation delay
        // Qt introduces when acceptedButtons includes RightButton.
        onPressed: function(ev) {
            if (ev.button === Qt.LeftButton) {
                ev.accepted = true
                if (!wpPickProc.running) wpPickProc.running = true
            }
        }

        // Right-click: reload colors from current wallpaper (latency not critical here)
        onClicked: function(ev) {
            if (ev.button === Qt.RightButton) {
                if (!wpReColorProc.running) wpReColorProc.running = true
            }
        }

        onWheel: function(wheel) {
            if (wheel.angleDelta.y > 0) {
                if (!wpNextProc.running) wpNextProc.running = true
            } else {
                if (!wpPrevProc.running) wpPrevProc.running = true
            }
        }
    }
}
