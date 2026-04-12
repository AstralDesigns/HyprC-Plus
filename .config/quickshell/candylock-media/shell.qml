// ~/.config/quickshell/candylock-media/shell.qml
// Candylock media overlay — right-side panel
// Starts its own cava instance on the hyprcandy-lock socket.
// Add to Hyprland: layerrule = blur, namespace:quickshell:candylock-media
// IPC close: qs ipc -c candylock-media call candylockMedia close

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // ── Matugen colors ─────────────────────────────────────────────────────
    property string _m3primary:              "#f7c382"
    property string _m3onSecondary:          "#100a00"
    property string _m3surfaceContainer:     "#0d0a07"
    property string _m3surfaceContainerHigh: "#1b1611"
    property string _m3onSurface:            "#f1e1d2"
    property string _m3onSurfaceVariant:     "#d1bca6"
    property string _m3outlineVariant:       "#5f5242"

    readonly property color cPrimary:   Qt.color(_m3primary)
    readonly property color cOnSurf:    Qt.color(_m3onSurface)
    readonly property color cOnSurfVar: Qt.color(_m3onSurfaceVariant)
    readonly property color cSurf:      Qt.color(_m3surfaceContainer)
    readonly property color cSurfHi:    Qt.color(_m3surfaceContainerHigh)
    readonly property color cOutVar:    Qt.color(_m3outlineVariant)
    readonly property color cPanelBg:   Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.4)

    function parseColors(text) {
        const re = /property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while ((m = re.exec(text)) !== null) {
            switch (m[1]) {
                case "m3primary":             root._m3primary = m[2];              break
                case "m3onSecondary":         root._m3onSecondary = m[2];          break
                case "m3surfaceContainer":    root._m3surfaceContainer = m[2];     break
                case "m3surfaceContainerHigh":root._m3surfaceContainerHigh = m[2]; break
                case "m3onSurface":           root._m3onSurface = m[2];            break
                case "m3onSurfaceVariant":    root._m3onSurfaceVariant = m[2];     break
                case "m3outlineVariant":      root._m3outlineVariant = m[2];       break
            }
        }
    }

    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) +
              "/quickshell/wallpaper/MatugenColors.qml"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parseColors(text())
    }

    // ── IPC: close on unlock ────────────────────────────────────────────────
    IpcHandler {
        target: "candylockMedia"
        function close(): void {
            cavaProc.running = false
            Qt.quit()
        }
    }

    // ── Cava (own instance via hyprcandy-lock socket) ───────────────────────
    property var  cavaBars: []
    property int  cavaN:    32
    readonly property int cavaRange: 15

    // Start cava.py manager for the lock-screen socket
    Process {
        id: cavaMgrProc
        command: ["python3",
            Quickshell.env("HOME") + "/.config/quickshell/candylock-media/cava.py",
            "--manager", "--bars", "32", "--range", "15"]
        Component.onCompleted: running = true
    }

    // Connect to cava socket after manager starts
    Timer {
        interval: 1500; running: true; repeat: false
        onTriggered: cavaProc.running = true
    }

    Process {
        id: cavaProc
        command: ["bash", "-c",
            "SOCK=\"${XDG_RUNTIME_DIR}/hyprcandy-lock/cava.sock\"; " +
            "while true; do [ -S \"$SOCK\" ] && nc -U \"$SOCK\" 2>/dev/null; sleep 3; done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const parts = line.trim().split(";").filter(v => /^\d+$/.test(v))
                if (parts.length < 2) return
                const n = Math.min(parts.length, 64)
                const prev = root.cavaBars
                const nb = new Array(n)
                for (let i = 0; i < n; i++) {
                    const raw = Math.min(parseInt(parts[i]), root.cavaRange) / root.cavaRange
                    const p = (prev && prev[i]) ? prev[i] : 0
                    nb[i] = raw > p ? p * 0.25 + raw * 0.75 : p * 0.55 + raw * 0.45
                }
                root.cavaN = n; root.cavaBars = nb
            }
        }
    }

    // ── Media (playerctl follow) ────────────────────────────────────────────
    property string mediaStatus: "Stopped"
    property string mediaTitle:  "No media"
    property string mediaArtist: ""
    property string mediaArtUrl: ""

    Process {
        id: mediaProc
        command: ["playerctl", "-F", "metadata", "--format",
                  "{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const p = line.split("\t")
                if (p.length >= 4) {
                    root.mediaStatus = p[0].trim() || "Stopped"
                    root.mediaArtUrl = p[1].trim()
                    root.mediaTitle  = p[2].trim() || "No media"
                    root.mediaArtist = p[3].trim()
                }
            }
        }
        Component.onCompleted: running = true
    }

    Process {
        id: ctlProc; property string _cmd: ""
        command: ["bash", "-c", ctlProc._cmd]
    }
    function playerAction(cmd) {
        ctlProc._cmd = "playerctl " + cmd
        if (!ctlProc.running) ctlProc.running = true
    }

    // ── Panel window ────────────────────────────────────────────────────────
    PanelWindow {
        anchors { right: true; top: true; bottom: true }
        WlrLayershell.namespace: "quickshell:candylock-media"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        width: 260
        color: "transparent"

        Rectangle {
            anchors { fill: parent; margins: 16 }
            radius: 22
            color: root.cPanelBg
            border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.30)
            border.width: 1
            clip: true

            ColumnLayout {
                anchors { fill: parent; margins: 16 }
                spacing: 12

                Item { Layout.fillHeight: true }

                // ── Disc + cava ring ──────────────────────────────────────
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    readonly property int discSize: 96
                    readonly property int barMax:   22
                    readonly property int gap:      5
                    readonly property int ringSize: discSize + 2 * (gap + barMax + 3)
                    width: ringSize; height: ringSize

                    // Cava ring
                    Canvas {
                        id: cavaCanvas
                        anchors.fill: parent
                        property color pri: root.cPrimary
                        onPriChanged: requestPaint()
                        Connections {
                            target: root
                            function onCavaBarsChanged() { cavaCanvas.requestPaint() }
                        }
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            const bars = root.cavaBars, N = root.cavaN
                            if (!bars || N < 2) return
                            const cx = width/2, cy = height/2
                            const rInner = parent.discSize/2 + parent.gap
                            const barMax = parent.barMax
                            const dA = 2*Math.PI/N, s0 = -Math.PI/2
                            ctx.lineWidth = 1.5; ctx.lineCap = "round"
                            for (let i = 0; i < N; i++) {
                                const amp = bars[i] || 0
                                if (amp < 0.015) continue
                                const a = s0 + (i + 0.5) * dA
                                const len = amp * barMax
                                const cos = Math.cos(a), sin = Math.sin(a)
                                ctx.strokeStyle = Qt.rgba(pri.r, pri.g, pri.b, 0.15 + amp * 0.85).toString()
                                ctx.beginPath()
                                ctx.moveTo(cx + rInner * cos, cy + rInner * sin)
                                ctx.lineTo(cx + (rInner + len) * cos, cy + (rInner + len) * sin)
                                ctx.stroke()
                            }
                        }
                    }

                    // Disc — layer.enabled:true is the correct Qt6 circular-clip approach
                    Rectangle {
                        id: disc
                        anchors.centerIn: parent
                        width: parent.discSize; height: parent.discSize
                        radius: width / 2
                        color: root.cSurf
                        // layer.enabled makes radius act as actual clip mask for children
                        layer.enabled: true

                        Image {
                            anchors.fill: parent
                            source: root.mediaArtUrl.startsWith("file://") ? root.mediaArtUrl
                                  : root.mediaArtUrl !== ""                 ? root.mediaArtUrl : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: root.mediaArtUrl !== ""
                        }

                        // Placeholder icon
                        Text {
                            anchors.centerIn: parent
                            visible: root.mediaArtUrl === ""
                            text: "󰽲"; font.pixelSize: 38; font.family: "Symbols Nerd Font Mono"
                            color: root.cOnSurfVar; opacity: 0.4
                        }

                        // Spindle center dot
                        Rectangle {
                            anchors.centerIn: parent
                            visible: root.mediaArtUrl !== ""
                            width: 10; height: 10; radius: 5
                            color: root.cSurf; opacity: 0.9
                            Rectangle {
                                anchors.centerIn: parent
                                width: 4; height: 4; radius: 2
                                color: root.cPrimary
                            }
                        }

                        // Rotation on the disc itself (layer.enabled ensures circular clip during spin)
                        RotationAnimator {
                            target: disc
                            from: 0; to: 360; duration: 12000
                            loops: Animation.Infinite
                            running: root.mediaStatus === "Playing"
                        }
                    }
                }

                // ── Track info ────────────────────────────────────────────
                ColumnLayout {
                    Layout.fillWidth: true; spacing: 3

                    Text {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                        text: root.mediaTitle; color: root.cOnSurf
                        font.pixelSize: 13; font.weight: Font.Medium
                        horizontalAlignment: Text.AlignHCenter; elide: Text.ElideRight
                    }
                    Text {
                        Layout.fillWidth: true; Layout.alignment: Qt.AlignHCenter
                        text: root.mediaArtist; color: root.cOnSurfVar
                        font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight; visible: text !== ""
                    }
                }

                // ── Controls ──────────────────────────────────────────────
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter; spacing: 8

                    Repeater {
                        model: [
                            { icon: "󰒮", cmd: "previous" },
                            { icon: root.mediaStatus === "Playing" ? "󰏤" : "󰐊", cmd: "play-pause" },
                            { icon: "󰒭", cmd: "next" },
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: 36; height: 36; radius: 18
                            color: ctrlHov.containsMouse
                                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.20)
                                : Qt.rgba(root.cSurfHi.r,  root.cSurfHi.g,  root.cSurfHi.b,  0.50)
                            Behavior on color { ColorAnimation { duration: 120 } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.icon
                                font.pixelSize: 16; font.family: "Symbols Nerd Font Mono"
                                color: ctrlHov.containsMouse ? root.cPrimary : root.cOnSurfVar
                                Behavior on color { ColorAnimation { duration: 120 } }
                            }
                            MouseArea { id: ctrlHov; anchors.fill: parent; hoverEnabled: true
                                onClicked: root.playerAction(modelData.cmd) }
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
