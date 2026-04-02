import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import ".."

// Active window — icon + truncated title of the focused window.
// Icon resolution (no DesktopEntries — not available in all builds):
//   1. Quickshell.iconPath(class) → XDG theme icon lookup by window class
//   2. tray-icon-resolve.py python fallback for edge cases
Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  Math.max(Config.activeWindowMinWidth,
                             row.implicitWidth + Config.modPadH * 2)
    implicitHeight: Config.moduleHeight
    visible: true

    // ── Focused client state — direct property bindings ───────────────────
    readonly property var    _focused:     (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
    readonly property string winTitle:     _focused?.title        ?? ""
    readonly property string winClass:     _focused?.class        ?? ""
    readonly property string initialClass: _focused?.initialClass ?? ""
    readonly property string winAddress:   _focused?.address      ?? ""
    readonly property bool   _noWindow:    winAddress === ""

    // ── Icon resolution ───────────────────────────────────────────────────
    readonly property string _classKey: winClass !== "" ? winClass : initialClass

    // Quickshell.iconPath(name, fallback) — returns "" when not found if fallback=""
    readonly property string _primaryIcon: {
        if (_noWindow || _classKey === "") return ""
        return Quickshell.iconPath(_classKey, "")
    }

    // Fallback: python resolver for apps where class != icon name
    property string _resolvedIcon: ""

    readonly property string iconSource: {
        if (_noWindow) return ""
        if (_resolvedIcon !== "") return "file://" + _resolvedIcon
        return _primaryIcon
    }

    onWinClassChanged:     { _resolvedIcon = ""; _tryResolve() }
    onInitialClassChanged: { _resolvedIcon = ""; _tryResolve() }

    function _tryResolve() {
        if (!_noWindow && _classKey !== "" && _primaryIcon === "") {
            iconResolverProc.running = false
            iconResolverProc.running = true
        }
    }

    Process {
        id: iconResolverProc
        command: ["python3",
                  Quickshell.env("HOME") + "/.config/quickshell/bar/tray-icon-resolve.py",
                  root._classKey]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const p = line.trim()
                if (p) root._resolvedIcon = p
            }
        }
    }

    // ── Layout ────────────────────────────────────────────────────────────
    Row {
        id: row
        anchors.centerIn: parent
        spacing: Config.iconTextGap

        Image {
            id: appIcon
            source: root.iconSource
            width: Config.glyphSize + 2; height: Config.glyphSize + 2
            sourceSize: Qt.size(width, height)
            fillMode: Image.PreserveAspectFit
            smooth: true; mipmap: true
            anchors.verticalCenter: parent.verticalCenter
            visible: !root._noWindow && source !== "" && status === Image.Ready

            onStatusChanged: {
                if (status === Image.Error && root._resolvedIcon === "" && root._classKey !== "") {
                    root._resolvedIcon = ""
                    iconResolverProc.running = false
                    iconResolverProc.running = true
                }
            }
        }

        Text {
            visible: root._noWindow ||
                     root.iconSource === "" ||
                     appIcon.status === Image.Error ||
                     appIcon.status === Image.Null
            text:           "󱑙"
            color:          Theme.cOnSurfVar
            font.family:    Config.fontFamily
            font.pixelSize: Config.glyphSize
            anchors.verticalCenter: parent.verticalCenter
        }

        Text {
            visible: root.winTitle !== ""
            text: root.winTitle.length > 32
                ? root.winTitle.substring(0, 31) + "…"
                : root.winTitle
            color:          Config.windowTextColor
            font.family:    Config.labelFont
            font.pixelSize: Config.labelFontSize
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
