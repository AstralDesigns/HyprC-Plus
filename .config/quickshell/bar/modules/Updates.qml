import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// Combined updates indicator — system packages + HyprCandy Plus dotfiles.
// Shows 󰏗 when everything is up-to-date, 󰏖 (primary colour) when any
// updates are pending.  Click opens UpdatesPopup with two sections.
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  updIcon.implicitWidth + Config.moduleHPad * 2
    implicitHeight: Config.moduleHeight

    // ── System update state ───────────────────────────────────────────────────
    property string _text:       "󰏗"
    property string _tooltip:    "Checking for updates…"
    property bool   _hasUpdates: false
    property bool   _checking:   false

    // ── HC update state ───────────────────────────────────────────────────────
    property bool   _hcHasUpdates: false
    property bool   _hcChecking:   false

    // Either source flagging updates lights up the icon
    readonly property bool _anyUpdates: _hasUpdates || _hcHasUpdates
    readonly property bool _anyChecking: _checking  || _hcChecking

    // ── Loader animation (braille spinner) ────────────────────────────────────
    readonly property var _loaderFrames: ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]
    property int _loaderIdx: 0
    Timer {
        id: loaderTick
        interval: 80; running: root._anyChecking; repeat: true
        onTriggered: root._loaderIdx = (root._loaderIdx + 1) % root._loaderFrames.length
    }

    // ── System update check process ───────────────────────────────────────────
    Process {
        id: checkProc
        command: [Config.scriptsDir + "/system-update.sh"]
        onRunningChanged: root._checking = running
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const t = l.trim()
                if (!t) return
                try {
                    const d = JSON.parse(t)
                    root._text       = d.text    || "󰏗"
                    root._tooltip    = d.tooltip || "System is up to date"
                    root._hasUpdates = (d.text && d.text !== "󰏗")
                } catch(e) {
                    root._text       = t
                    root._tooltip    = t
                    root._hasUpdates = false
                }
            }
        }
    }

    // ── HC update check process ───────────────────────────────────────────────
    Process {
        id: hcCheckProc
        command: [Config.scriptsDir + "/hc-update-check.sh"]
        onRunningChanged: root._hcChecking = running
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const t = l.trim()
                if (!t) return
                try {
                    const d = JSON.parse(t)
                    root._hcHasUpdates = d.hasUpdates === true
                    UpdatesPopupState.updateHC(
                        d.hasUpdates === true,
                        d.tooltip    || "",
                        d.noStore    === true
                    )
                } catch(e) {
                    // Ignore malformed output
                }
            }
        }
    }

    // ── Hourly poll timer (both checks fire together) ─────────────────────────
    Timer {
        interval: 3600000; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (!checkProc.running)   checkProc.running   = true
            if (!hcCheckProc.running) hcCheckProc.running = true
        }
    }

    // ── Icon ──────────────────────────────────────────────────────────────────
    Text {
        id: updIcon
        anchors.centerIn: parent
        text:  root._anyChecking ? root._loaderFrames[root._loaderIdx] : (root._anyUpdates ? "󰏖" : "󰏗")
        color: root._anyChecking  ? Theme.cOnSurfVar
             : root._anyUpdates   ? Theme.cPrimary
             :                      Theme.cOnSurfVar
        font.family:    Config.fontFamily
        font.pixelSize: Config.fontSize
        font.weight:    Config.fontWeight
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape:  Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: function(mouse) {
            const cx = root.mapToItem(null, root.width / 2, 0).x
            UpdatesPopupState.toggle(cx, root._tooltip, root._hasUpdates)
        }
    }
}
