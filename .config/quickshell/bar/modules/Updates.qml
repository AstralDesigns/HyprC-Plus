import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// System updates indicator — matches waybar custom/update module.
// Shows 󰸟 when up-to-date, update count when updates available.
// Click opens popover with "Apply Updates" button when updates are available.
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: updIcon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    property string _text:       "󰸟"
    property string _tooltip:    "Checking for updates…"
    property bool   _hasUpdates: false
    property bool   _checking:   false

    // ── Loader animation (braille spinner) ───────────────────────────────
    readonly property var _loaderFrames: ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    property int _loaderIdx: 0
    Timer {
        id: loaderTick
        interval: 80; running: root._checking; repeat: true
        onTriggered: root._loaderIdx = (root._loaderIdx + 1) % root._loaderFrames.length
    }

    // Poll on startup and every hour (3600 s)
    Process {
        id: checkProc
        command: [Config.home + "/.config/waybar/scripts/system-update.sh"]
        onRunningChanged: root._checking = running
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const t = l.trim()
                if (!t) return
                try {
                    const d = JSON.parse(t)
                    root._text       = d.text    || "󰸟"
                    root._tooltip    = d.tooltip || "System is up to date"
                    root._hasUpdates = (d.text && d.text !== "󰸟")
                } catch(e) {
                    root._text    = t
                    root._tooltip = t
                    root._hasUpdates = false
                }
            }
        }
    }
    Timer {
        interval: 3600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: if (!checkProc.running) checkProc.running = true
    }

    Text {
        id: updIcon
        anchors.centerIn: parent
        text: root._checking ? root._loaderFrames[root._loaderIdx] : root._text
        color: root._checking        ? Theme.cOnSurfVar
             : root._hasUpdates      ? Theme.cPrimary
             :                         Theme.cOnSurfVar
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
        onClicked: {
            const cx = root.mapToItem(null, root.width / 2, 0).x
            UpdatesPopupState.toggle(cx, root._tooltip, root._hasUpdates)
        }
    }
}
