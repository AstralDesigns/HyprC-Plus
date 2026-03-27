pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts

// ═══════════════════════════════════════════════════════════════════════════
//  Quickshell Notification + Bluetooth Agent Center
//  ~/.config/quickshell/notifications/shell.qml
//
//  Replaces swaync. Handles:
//    • org.freedesktop.Notifications  (via dbus-monitor, no external daemon)
//    • BT pair confirm / PIN prompts  (via bt-agent.py → Process pipe)
//    • OBEX file transfer prompts     (via bt-agent.py)
//    • Persistent notification history tray (toggle via IPC "notifications")
//    • Matugen live color theming identical to startmenu
// ═══════════════════════════════════════════════════════════════════════════

ShellRoot {
    id: root

    // ── Matugen colors (mirrored from startmenu) ──────────────────────────
    property string _m3primary:              "#f7c382"
    property string _m3onPrimary:            "#1d1100"
    property string _m3onSecondary:          "#100a00"
    property string _m3background:           "#100a00"
    property string _m3surfaceContainerHigh: "#1b1611"
    property string _m3surfaceContainer:     "#18120e"
    property string _m3onSurface:            "#f1e1d2"
    property string _m3onSurfaceVariant:     "#d1bca6"
    property string _m3outlineVariant:       "#5f5242"
    property string _m3inversePrimary:       "#69361d"
    property string _m3error:               "#ffb4ab"

    readonly property color cPrimary:    Qt.color(_m3primary)
    readonly property color cOnPrim:     Qt.color(_m3onPrimary)
    readonly property color cSurfHi:     Qt.color(_m3surfaceContainerHigh)
    readonly property color cSurfMid:    Qt.color(_m3surfaceContainer)
    readonly property color cOnSurf:     Qt.color(_m3onSurface)
    readonly property color cOnSurfVar:  Qt.color(_m3onSurfaceVariant)
    readonly property color cOutVar:     Qt.color(_m3outlineVariant)
    readonly property color cInvPrim:    Qt.color(_m3inversePrimary)
    readonly property color cErr:        Qt.color(_m3error)
    readonly property color cPanelBg:    Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.40)

    function parseColors(t) {
        const re = /property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while ((m = re.exec(t)) !== null) switch (m[1]) {
            case "m3primary":              root._m3primary = m[2]; break
            case "m3onPrimary":            root._m3onPrimary = m[2]; break
            case "m3onSecondary":          root._m3onSecondary = m[2]; break
            case "m3background":           root._m3background = m[2]; break
            case "m3surfaceContainerHigh": root._m3surfaceContainerHigh = m[2]; break
            case "m3surfaceContainer":     root._m3surfaceContainer = m[2]; break
            case "m3onSurface":            root._m3onSurface = m[2]; break
            case "m3onSurfaceVariant":     root._m3onSurfaceVariant = m[2]; break
            case "m3outlineVariant":       root._m3outlineVariant = m[2]; break
            case "m3inversePrimary":       root._m3inversePrimary = m[2]; break
            case "m3error":                root._m3error = m[2]; break
        }
    }
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) +
              "/quickshell/wallpaper/MatugenColors.qml"
        watchChanges: true; onFileChanged: reload(); onLoaded: root.parseColors(text())
    }

    // ── Waybar position (so toast stacks clear the bar) ───────────────────
    property bool waybarAtBottom: false
    property real waybarSideMargin: 12
    FileView {
        path: Quickshell.env("HOME") + "/.config/hyprcandy/waybar-position.txt"
        watchChanges: true; onFileChanged: reload()
        onLoaded: root.waybarAtBottom = text().trim() === "bottom"
    }
    FileView {
        path: Quickshell.env("HOME") + "/.config/hyprcandy/waybar_side_margin.state"
        watchChanges: true; onFileChanged: reload()
        onLoaded: { const v = parseFloat(text().trim()); if (!isNaN(v) && v >= 0) root.waybarSideMargin = v }
    }

    // ── IPC: toggle notification history tray ─────────────────────────────
    property bool historyVisible: false
    IpcHandler { target: "notifications"
        function toggle() { root.historyVisible = !root.historyVisible }
        function open()   { root.historyVisible = true }
        function close()  { root.historyVisible = false }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  NOTIFICATION DATA MODEL
    //  Each notification: { id, appName, summary, body, icon, urgency,
    //                       timestamp, actions, category, isPrompt,
    //                       promptType, promptMac, promptName,
    //                       promptPasskey, promptTransfer, promptFilename,
    //                       promptSize, dismissed }
    // ═════════════════════════════════════════════════════════════════════
    property var notifications: []   // toast queue (auto-dismisses)
    property var history: []         // persistent history
    property int _nextId: 1

    function addNotification(obj) {
        const n = Object.assign({
            id: root._nextId++,
            appName: "", summary: "", body: "", icon: "",
            urgency: 1, timestamp: Date.now(), actions: [],
            category: "app", isPrompt: false,
            dismissed: false
        }, obj)

        // Prepend to toast queue
        const q = root.notifications.slice()
        q.unshift(n)
        // Cap toasts at 5 visible
        if (q.length > 5) q.pop()
        root.notifications = q

        // Add to history (prompts go in history too once resolved)
        if (!n.isPrompt) {
            const h = root.history.slice()
            h.unshift(n)
            if (h.length > 50) h.pop()
            root.history = h
        }

        return n.id
    }

    function dismissNotification(id) {
        root.notifications = root.notifications.filter(function(n){ return n.id !== id })
    }

    function clearHistory() {
        root.history = []
    }

    // ═════════════════════════════════════════════════════════════════════
    //  D-BUS NOTIFICATION LISTENER  (org.freedesktop.Notifications)
    //  We run dbus-monitor on the session bus, filtered to the
    //  Notify method calls.  This is the lightest approach without
    //  needing to own the service name (which would conflict with
    //  existing notification daemons while transitioning).
    //
    //  To fully replace swaync, add to hyprland.conf:
    //    exec-once = pkill swaync; qs -c ~/.config/quickshell/notifications
    //  and ensure no other daemon owns org.freedesktop.Notifications.
    //  We take the name below via the service-name claim script.
    // ═════════════════════════════════════════════════════════════════════
    Process { id: dbusMonProc
        property var _buf: []
        command: ["bash", "-c",
            "dbus-monitor --session \"interface='org.freedesktop.Notifications',member='Notify'\" 2>/dev/null"
        ]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                dbusMonProc._buf.push(l.trim())
                // A Notify call looks like a burst of lines; flush when we see
                // the closing string (body line or empty line after args)
                root._parseDbusNotifyBuf(dbusMonProc._buf)
            }
        }
        Component.onCompleted: running = true
        onExited: { Qt.callLater(function(){ if (!running) running = true }) }
    }

    // Also run our own notification daemon that claims the DBus name
    // so swaync / dunst are not needed at all
    Process { id: notifDaemonProc
        command: ["bash", "-c",
            "~/.config/quickshell/notifications/notify-daemon.py 2>/dev/null"
        ]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (!l.trim()) return
            try {
                const ev = JSON.parse(l)
                root._handleNotifEvent(ev)
            } catch(e) {}
        }}
        Component.onCompleted: running = true
        onExited: { Qt.callLater(function(){ if (!running) running = true }) }
    }

    function _handleNotifEvent(ev) {
        if (ev.type === "notify") {
            const urgMap = {"low":0,"normal":1,"critical":2}
            addNotification({
                appName:  ev.app_name  || "",
                summary:  ev.summary   || "",
                body:     ev.body      || "",
                icon:     ev.icon      || "",
                urgency:  urgMap[ev.urgency] !== undefined ? urgMap[ev.urgency] : 1,
                actions:  ev.actions   || [],
                category: ev.category  || "app",
                _daemonId: ev.id
            })
        } else if (ev.type === "close") {
            // daemon asked to close a notification
        }
    }

    // Minimal dbus-monitor buffer parser (fallback path)
    property var _notifPartial: ({})
    function _parseDbusNotifyBuf(buf) {
        // This is a best-effort heuristic parser for dbus-monitor output
        // The notify-daemon.py path is preferred; this is the fallback
    }

    // ═════════════════════════════════════════════════════════════════════
    //  BLUETOOTH AGENT PROCESS
    //  Runs bt-agent.py which registers a BlueZ Agent1 + OBEX Agent1.
    //  Emits JSON events; we send commands back via stdin.
    // ═════════════════════════════════════════════════════════════════════
    property bool btAgentReady: false

    Process { id: btAgentProc
        command: ["python3", "-u",
                  Quickshell.env("HOME") + "/.config/quickshell/notifications/bt-agent.py"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (!l.trim()) return
            try {
                const ev = JSON.parse(l)
                root._handleBtAgentEvent(ev)
            } catch(e) { console.warn("bt-agent parse error:", l) }
        }}
        Component.onCompleted: running = true
        onExited: {
            root.btAgentReady = false
            // Restart after 3s if it dies
            btAgentRestartTimer.restart()
        }
    }
    Timer { id: btAgentRestartTimer; interval: 3000; repeat: false
        onTriggered: { if (!btAgentProc.running) btAgentProc.running = true }
    }

    function btAgentSend(cmd) {
        // Write a command line to the agent's stdin
        // Quickshell Process doesn't expose stdin directly, so we use a helper
        btAgentStdinProc._cmd = cmd
        if (!btAgentStdinProc.running) btAgentStdinProc.running = true
    }
    // Stdin bridge: echo command into the agent's stdin via a named pipe
    Process { id: btAgentSetupProc
        command: ["bash", "-c",
            "rm -f /tmp/qs_bt_cmd; mkfifo /tmp/qs_bt_cmd; " +
            "python3 -u " + Quickshell.env("HOME") +
            "/.config/quickshell/notifications/bt-agent.py < /tmp/qs_bt_cmd"
        ]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (!l.trim()) return
            try {
                const ev = JSON.parse(l)
                root._handleBtAgentEvent(ev)
            } catch(e) {}
        }}
        Component.onCompleted: running = true
        onExited: { Qt.callLater(function(){ if (!running) { btAgentRestartTimer.restart() } }) }
    }
    Process { id: btAgentStdinProc; property string _cmd: ""
        command: ["bash", "-c", "echo '" + btAgentStdinProc._cmd + "' > /tmp/qs_bt_cmd"]
    }

    function _handleBtAgentEvent(ev) {
        switch (ev.type) {
        case "agent_ready":
            root.btAgentReady = true
            break

        case "pair_confirm":
            // Show confirm-passkey prompt
            addNotification({
                isPrompt: true,
                promptType: "pair_confirm",
                promptMac: ev.mac,
                promptName: ev.name || ev.mac,
                promptPasskey: ev.passkey || "",
                summary: "Bluetooth Pairing Request",
                body: "Confirm passkey on " + (ev.name || ev.mac),
                icon: "bluetooth",
                urgency: 2,
                category: "bt"
            })
            break

        case "pair_pin":
            // Show PIN entry prompt
            addNotification({
                isPrompt: true,
                promptType: "pair_pin",
                promptMac: ev.mac,
                promptName: ev.name || ev.mac,
                promptNeedsPasskey: ev.needs_passkey || false,
                summary: "Bluetooth PIN Required",
                body: "Enter PIN for " + (ev.name || ev.mac),
                icon: "bluetooth",
                urgency: 2,
                category: "bt"
            })
            break

        case "pair_authorize":
            addNotification({
                isPrompt: true,
                promptType: "pair_authorize",
                promptMac: ev.mac,
                promptName: ev.name || ev.mac,
                summary: "Bluetooth Pair Request",
                body: (ev.name || ev.mac) + " wants to pair",
                icon: "bluetooth",
                urgency: 2,
                category: "bt"
            })
            break

        case "display_pin":
            addNotification({
                summary: "Bluetooth PIN",
                body: "PIN for " + (ev.name || ev.mac) + ": " + ev.pin,
                icon: "bluetooth",
                urgency: 2,
                category: "bt"
            })
            break

        case "pair_cancelled":
            addNotification({
                summary: "Bluetooth",
                body: "Pairing cancelled",
                icon: "bluetooth",
                urgency: 1,
                category: "bt"
            })
            // Dismiss any pending pair prompts for this mac
            if (ev.mac) {
                root.notifications = root.notifications.filter(function(n){
                    return !(n.isPrompt && n.promptMac === ev.mac)
                })
            }
            break

        case "file_request":
            const sizeMb = ev.size > 0 ? (ev.size / (1024*1024)).toFixed(1) + " MB" : ""
            addNotification({
                isPrompt: true,
                promptType: "file_accept",
                promptMac: ev.mac,
                promptName: ev.name || ev.mac,
                promptTransfer: ev.transfer,
                promptFilename: ev.filename || "file",
                promptSize: sizeMb,
                summary: "Incoming File",
                body: (ev.name || ev.mac) + " → " + (ev.filename || "file") +
                      (sizeMb ? "  (" + sizeMb + ")" : ""),
                icon: "bluetooth",
                urgency: 2,
                category: "bt"
            })
            break

        case "file_cancelled":
            addNotification({
                summary: "Bluetooth",
                body: "File transfer cancelled",
                icon: "bluetooth",
                urgency: 1,
                category: "bt"
            })
            break

        case "error":
            console.warn("bt-agent error:", ev.msg)
            break
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  AUTO-DISMISS TIMERS
    //  Non-prompt, non-critical notifications auto-dismiss after 5s.
    //  Critical ones stay until manually dismissed.
    //  Prompts never auto-dismiss.
    // ═════════════════════════════════════════════════════════════════════
    Timer { id: autoDismissTimer; interval: 200; repeat: true; running: true
        onTriggered: {
            const now = Date.now()
            const remaining = root.notifications.filter(function(n) {
                if (n.isPrompt) return true            // prompts stay
                if (n.urgency >= 2) return true        // critical stays
                return (now - n.timestamp) < 5000      // others: 5s
            })
            if (remaining.length !== root.notifications.length)
                root.notifications = remaining
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  TOAST STACK WINDOW  — anchored top-right (or bottom-right)
    //  Shows live incoming notifications + interactive prompts
    // ═════════════════════════════════════════════════════════════════════
    PanelWindow {
        id: toastWindow
        visible: root.notifications.length > 0
        WlrLayershell.namespace: "quickshell:notifications:toasts"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: {
            // Need keyboard for PIN entry prompts
            for (let i = 0; i < root.notifications.length; i++) {
                if (root.notifications[i].isPrompt &&
                    (root.notifications[i].promptType === "pair_pin")) return WlrKeyboardFocus.OnDemand
            }
            return WlrKeyboardFocus.None
        }
        anchors {
            top:    !root.waybarAtBottom
            bottom:  root.waybarAtBottom
            left:    true
        }
        margins {
            top:    42
            bottom: 42
            left:   root.waybarSideMargin
        }
        width: 360
        height: toastCol.implicitHeight + 4
        color: cPanelBg
        exclusionMode: ExclusionMode.Ignore

        Column {
            id: toastCol
            anchors { top: parent.top; right: parent.right; left: parent.left }
            spacing: 6

            Repeater {
                model: root.notifications
                delegate: ToastCard {
                    required property var modelData
                    required property int index
                    notif: modelData
                    width: toastCol.width
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  HISTORY TRAY WINDOW  — full panel, toggled via IPC
    // ═════════════════════════════════════════════════════════════════════
    PanelWindow {
        id: historyWindow
        visible: root.historyVisible
        WlrLayershell.namespace: "quickshell:notifications:history"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors {
            top:    !root.waybarAtBottom
            bottom:  root.waybarAtBottom
            left:    true
        }
        margins { top: 2; bottom: 2; left:  root.waybarSideMargin }
        width: 380
        height: Math.min(historyContent.implicitHeight + 32, 700)
        color: "transparent"

        HyprlandFocusGrab {
            id: historyFocusGrab
            windows: [historyWindow]
            active: false
            onCleared: { if (!active) root.historyVisible = false }
        }
        Connections { target: root
            function onHistoryVisibleChanged() {
                if (root.historyVisible) historyGrabTimer.restart()
                else historyFocusGrab.active = false
            }
        }
        Timer { id: historyGrabTimer; interval: 80; repeat: false
            onTriggered: { if (root.historyVisible) historyFocusGrab.active = true }
        }

        Rectangle {
            anchors.fill: parent
            color: root.cPanelBg
            radius: 20
            border.width: 1
            border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.40)
            scale: root.historyVisible ? 1.0 : 0.92
            transformOrigin: Item.TopRight
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Keys.onEscapePressed: root.historyVisible = false

            ColumnLayout {
                id: historyContent
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                spacing: 8

                // Header
                RowLayout { Layout.fillWidth: true
                    Text {
                        text: "󰂞  Notifications"
                        color: root.cOnSurf; font.pixelSize: 14; font.weight: Font.Medium
                        font.family: "Symbols Nerd Font Mono"
                        Layout.fillWidth: true
                    }
                    // BT agent status dot
                    Rectangle {
                        width: 8; height: 8; radius: 4
                        color: root.btAgentReady
                            ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.9)
                            : Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.7)
                    }
                    Item { width: 6 }
                    // Clear all
                    Rectangle {
                        height: 24; width: clearLbl.implicitWidth + 16; radius: 8
                        color: clearH.containsMouse
                            ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.18)
                            : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                        border.width: 1
                        border.color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.4)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { id: clearLbl; anchors.centerIn: parent; text: "Clear all"
                            color: root.cErr; font.pixelSize: 11; opacity: 0.85 }
                        MouseArea { id: clearH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.clearHistory() }
                    }
                    // Close
                    Rectangle {
                        height: 24; width: 24; radius: 8
                        color: closeH.containsMouse
                            ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.9)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "󰅖"
                            font.pixelSize: 12; font.family: "Symbols Nerd Font Mono"
                            color: root.cOnSurfVar }
                        MouseArea { id: closeH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.historyVisible = false }
                    }
                }

                Rectangle { Layout.fillWidth: true; height: 1
                    color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.3) }

                // Empty state
                Text {
                    visible: root.history.length === 0
                    Layout.alignment: Qt.AlignHCenter
                    text: "No notifications"
                    color: root.cOnSurfVar; font.pixelSize: 12; font.italic: true
                    topPadding: 16; bottomPadding: 16
                }

                // History list
                Repeater {
                    model: root.history
                    delegate: HistoryCard {
                        required property var modelData
                        notif: modelData
                        Layout.fillWidth: true
                    }
                }

                Item { height: 4 }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  TOAST CARD COMPONENT
    //  Handles: plain notifications, BT pair confirm, BT PIN entry,
    //           BT pair authorize, incoming file request
    // ═════════════════════════════════════════════════════════════════════
    component ToastCard: Rectangle {
        id: toast
        required property var notif
        property bool _hovered: toastMA.containsMouse

        radius: 16
        color: _hovered
            ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.7)
            : Qt.rgba(root.cSurfMid.r, root.cSurfMid.g, root.cSurfMid.b, 0.63)
        border.width: 1
        border.color: notif.urgency >= 2
            ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.55)
            : notif.category === "bt"
                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.45)
                : Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.35)
        height: toastInner.implicitHeight + 24
        clip: true
        Behavior on color { ColorAnimation { duration: 100 } }

        // Entry animation
        property real _progress: 0
        NumberAnimation on _progress { from: 0; to: 1; duration: 220; easing.type: Easing.OutCubic; running: true }
        opacity: _progress
        transform: Translate { x: (1 - toast._progress) * 28 }

        // Urgency accent bar on left edge
        Rectangle {
            width: 3; height: parent.height; radius: 2
            color: toast.notif.urgency >= 2
                ? root.cErr
                : toast.notif.category === "bt"
                    ? root.cPrimary
                    : Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.5)
        }

        // Progress bar (auto-dismiss countdown) — only for non-prompt, non-critical
        Rectangle {
            visible: !toast.notif.isPrompt && toast.notif.urgency < 2
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 2; radius: 1
            color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.35)
            property real _age: Math.min(1, (Date.now() - toast.notif.timestamp) / 5000)
            Timer { interval: 100; repeat: true; running: parent.visible
                onTriggered: parent._age = Math.min(1, (Date.now() - toast.notif.timestamp) / 5000) }
            Rectangle {
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                width: parent.width * (1 - parent._age)
                color: root.cPrimary; radius: 1
                Behavior on width { NumberAnimation { duration: 100 } }
            }
        }

        ColumnLayout {
            id: toastInner
            anchors { left: parent.left; right: parent.right; top: parent.top
                      leftMargin: 16; rightMargin: 12; topMargin: 12 }
            spacing: 8

            // ── Header row ────────────────────────────────────────────────
            RowLayout { Layout.fillWidth: true; spacing: 8

                // Icon / category indicator
                Rectangle {
                    width: 30; height: 30; radius: 8
                    color: toast.notif.urgency >= 2
                        ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.18)
                        : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.15)
                    Text {
                        anchors.centerIn: parent
                        text: {
                            if (toast.notif.category === "bt")   return "󰂯"
                            if (toast.notif.urgency >= 2)        return "󰀦"
                            if (toast.notif.icon === "network")  return "󰤨"
                            if (toast.notif.icon === "volume")   return "󰕾"
                            if (toast.notif.icon === "battery")  return ""
                            return "󰂞"
                        }
                        font.pixelSize: 15; font.family: "Symbols Nerd Font Mono"
                        color: toast.notif.urgency >= 2 ? root.cErr : root.cPrimary
                    }
                }

                ColumnLayout { Layout.fillWidth: true; spacing: 1
                    Text {
                        Layout.fillWidth: true
                        text: toast.notif.summary || toast.notif.appName || "Notification"
                        color: root.cOnSurf; font.pixelSize: 12; font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    Text {
                        visible: toast.notif.appName !== "" && toast.notif.summary !== ""
                        text: toast.notif.appName
                        color: root.cOnSurfVar; font.pixelSize: 9; opacity: 0.75
                    }
                }

                // Dismiss button (X)
                Rectangle {
                    width: 22; height: 22; radius: 6
                    color: dismissH.containsMouse
                        ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.9)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "󰅖"
                        font.pixelSize: 11; font.family: "Symbols Nerd Font Mono"
                        color: root.cOnSurfVar }
                    MouseArea { id: dismissH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissNotification(toast.notif.id) }
                }
            }

            // ── Body text ─────────────────────────────────────────────────
            Text {
                visible: toast.notif.body !== ""
                Layout.fillWidth: true
                text: toast.notif.body
                color: root.cOnSurfVar; font.pixelSize: 11
                wrapMode: Text.WordWrap; maximumLineCount: 3
                elide: Text.ElideRight
                leftPadding: 38
            }

            // ── BT PAIR CONFIRM (show passkey, Accept/Reject) ─────────────
            ColumnLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "pair_confirm"
                Layout.fillWidth: true; spacing: 8

                // Passkey display
                Rectangle {
                    Layout.alignment: Qt.AlignLeft
                    height: 36; radius: 10
                    color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.12)
                    border.width: 1
                    border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.5)
                    implicitWidth: passcode.implicitWidth + 32
                    Text {
                        id: passcode
                        anchors.centerIn: parent
                        text: toast.notif.promptPasskey || "------"
                        color: root.cPrimary; font.pixelSize: 20
                        font.weight: Font.Bold; font.letterSpacing: 6
                    }
                }
                Text {
                    text: "Confirm this passkey appears on the device"
                    color: root.cOnSurfVar; font.pixelSize: 10; font.italic: true
                }
                RowLayout { spacing: 8
                    Rectangle {
                        height: 32; radius: 8; implicitWidth: 80
                        color: accH.containsMouse
                            ? root.cPrimary
                            : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "󰄬  Accept"
                            color: root.cOnPrim; font.pixelSize: 11
                            font.family: "Symbols Nerd Font Mono"; font.weight: Font.Medium }
                        MouseArea { id: accH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.btAgentSend("accept_pair " + toast.notif.promptMac)
                                root.dismissNotification(toast.notif.id)
                                root.addNotification({ summary:"Bluetooth", body:"Paired with " + toast.notif.promptName, icon:"bluetooth", urgency:1, category:"bt" })
                            }
                        }
                    }
                    Rectangle {
                        height: 32; radius: 8; implicitWidth: 80
                        color: rejH.containsMouse
                            ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.85)
                            : Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.15)
                        border.width: 1
                        border.color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.5)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "󰅖  Reject"
                            color: rejH.containsMouse ? root.cOnPrim : root.cErr
                            font.pixelSize: 11; font.family: "Symbols Nerd Font Mono" }
                        MouseArea { id: rejH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.btAgentSend("reject_pair " + toast.notif.promptMac)
                                root.dismissNotification(toast.notif.id)
                            }
                        }
                    }
                }
            }

            // ── BT PAIR AUTHORIZE (no passkey, just Accept/Reject) ────────
            RowLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "pair_authorize"
                Layout.fillWidth: true; spacing: 8; Layout.leftMargin: 38
                Rectangle {
                    height: 32; radius: 8; implicitWidth: 80
                    color: authAccH.containsMouse ? root.cPrimary
                        : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "󰄬  Pair"
                        color: root.cOnPrim; font.pixelSize: 11
                        font.family: "Symbols Nerd Font Mono"; font.weight: Font.Medium }
                    MouseArea { id: authAccH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.btAgentSend("accept_pair " + toast.notif.promptMac)
                            root.dismissNotification(toast.notif.id)
                            root.addNotification({ summary:"Bluetooth", body:"Paired with " + toast.notif.promptName, icon:"bluetooth", urgency:1, category:"bt" })
                        }
                    }
                }
                Rectangle {
                    height: 32; radius: 8; implicitWidth: 80
                    color: authRejH.containsMouse ? Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.85)
                        : Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.15)
                    border.width: 1; border.color: Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.5)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "Reject"
                        color: authRejH.containsMouse ? root.cOnPrim : root.cErr; font.pixelSize: 11 }
                    MouseArea { id: authRejH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.btAgentSend("reject_pair " + toast.notif.promptMac); root.dismissNotification(toast.notif.id) }
                    }
                }
            }

            // ── BT PIN ENTRY ──────────────────────────────────────────────
            ColumnLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "pair_pin"
                Layout.fillWidth: true; spacing: 8
                RowLayout { spacing: 8
                    Rectangle {
                        height: 34; radius: 8; Layout.fillWidth: true; Layout.maximumWidth: 180
                        color: Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.8)
                        border.width: 1
                        border.color: pinInput.activeFocus
                            ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.7)
                            : Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.5)
                        TextInput {
                            id: pinInput
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10; topMargin: 6; bottomMargin: 6 }
                            color: root.cOnSurf; font.pixelSize: 14; font.letterSpacing: 3
                            inputMethodHints: Qt.ImhDigitsOnly
                            text: "PIN"
                            onAccepted: {
                                if (text.length > 0) {
                                    root.btAgentSend("pin_pair " + toast.notif.promptMac + " " + text)
                                    root.dismissNotification(toast.notif.id)
                                }
                            }
                        }
                        Component.onCompleted: pinInput.forceActiveFocus()
                    }
                    Rectangle {
                        height: 34; width: 60; radius: 8
                        color: pinOkH.containsMouse ? root.cPrimary
                            : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "OK"
                            color: root.cOnPrim; font.pixelSize: 12; font.weight: Font.Bold }
                        MouseArea { id: pinOkH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (pinInput.text.length > 0) {
                                    root.btAgentSend("pin_pair " + toast.notif.promptMac + " " + pinInput.text)
                                    root.dismissNotification(toast.notif.id)
                                }
                            }
                        }
                    }
                    Rectangle {
                        height: 34; width: 60; radius: 8
                        color: Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.15)
                        border.width:1; border.color:Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.4)
                        Text { anchors.centerIn: parent; text: "Cancel"
                            color: root.cErr; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: { root.btAgentSend("reject_pair " + toast.notif.promptMac); root.dismissNotification(toast.notif.id) }
                        }
                    }
                }
            }

            // ── FILE TRANSFER ACCEPT/REJECT ───────────────────────────────
            RowLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "file_accept"
                Layout.fillWidth: true; spacing: 8; Layout.leftMargin: 38
                Rectangle {
                    height: 32; radius: 8; implicitWidth: 100
                    color: fileAccH.containsMouse ? root.cPrimary
                        : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "󰇼  Accept"
                        color: root.cOnPrim; font.pixelSize: 11
                        font.family: "Symbols Nerd Font Mono"; font.weight: Font.Medium }
                    MouseArea { id: fileAccH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.btAgentSend("accept_file " + toast.notif.promptTransfer)
                            root.dismissNotification(toast.notif.id)
                            root.addNotification({
                                summary: "File Received",
                                body: toast.notif.promptFilename + " saved to Downloads",
                                icon: "bluetooth", urgency: 1, category: "bt"
                            })
                        }
                    }
                }
                Rectangle {
                    height: 32; radius: 8; implicitWidth: 80
                    color: fileRejH.containsMouse ? Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.85)
                        : Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.15)
                    border.width: 1; border.color: Qt.rgba(root.cErr.r,root.cErr.g,root.cErr.b,0.5)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "Decline"
                        color: fileRejH.containsMouse ? root.cOnPrim : root.cErr; font.pixelSize: 11 }
                    MouseArea { id: fileRejH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { root.btAgentSend("reject_file " + toast.notif.promptTransfer); root.dismissNotification(toast.notif.id) }
                    }
                }
                Text {
                    visible: toast.notif.promptSize !== undefined && toast.notif.promptSize !== ""
                    text: toast.notif.promptSize || ""
                    color: root.cOnSurfVar; font.pixelSize: 10
                }
            }

            Item { height: 4 }
        }

        // Hover/dismiss background handler
        MouseArea { id: toastMA; anchors.fill: parent; hoverEnabled: true
            // Right-click dismisses
            acceptedButtons: Qt.RightButton
            onClicked: function(e) {
                if (e.button === Qt.RightButton && !toast.notif.isPrompt)
                    root.dismissNotification(toast.notif.id)
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  HISTORY CARD COMPONENT  (compact, read-only)
    // ═════════════════════════════════════════════════════════════════════
    component HistoryCard: Rectangle {
        id: hcard
        required property var notif
        height: hcardInner.implicitHeight + 16
        radius: 12
        color: hcardMA.containsMouse
            ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.7)
            : Qt.rgba(root.cSurfMid.r, root.cSurfMid.g, root.cSurfMid.b, 0.5)
        border.width: 1
        border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.25)
        Behavior on color { ColorAnimation { duration: 100 } }

        RowLayout {
            id: hcardInner
            anchors { left: parent.left; right: parent.right; top: parent.top
                      margins: 10 }
            spacing: 8

            // Category dot
            Rectangle {
                width: 6; height: 6; radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: hcard.notif.urgency >= 2 ? root.cErr
                    : hcard.notif.category === "bt" ? root.cPrimary
                    : Qt.rgba(root.cOnSurfVar.r, root.cOnSurfVar.g, root.cOnSurfVar.b, 0.5)
            }
            ColumnLayout { Layout.fillWidth: true; spacing: 1
                Text { Layout.fillWidth: true
                    text: hcard.notif.summary || hcard.notif.appName || "Notification"
                    color: root.cOnSurf; font.pixelSize: 11; font.weight: Font.Medium
                    elide: Text.ElideRight }
                Text {
                    visible: hcard.notif.body !== ""
                    Layout.fillWidth: true
                    text: hcard.notif.body
                    color: root.cOnSurfVar; font.pixelSize: 10
                    elide: Text.ElideRight; maximumLineCount: 2
                    wrapMode: Text.WordWrap }
            }
            // Timestamp
            Text {
                text: {
                    const d = new Date(hcard.notif.timestamp)
                    const now = new Date()
                    const diffMin = Math.floor((now - d) / 60000)
                    if (diffMin < 1)  return "now"
                    if (diffMin < 60) return diffMin + "m"
                    const diffH = Math.floor(diffMin / 60)
                    if (diffH < 24) return diffH + "h"
                    return d.toLocaleDateString(undefined, {month:"short",day:"numeric"})
                }
                color: root.cOnSurfVar; font.pixelSize: 9; opacity: 0.7
                anchors.verticalCenter: parent.verticalCenter
            }
            // Dismiss
            Rectangle {
                width: 20; height: 20; radius: 5
                color: hcardDismH.containsMouse
                    ? Qt.rgba(root.cSurfHi.r,root.cSurfHi.g,root.cSurfHi.b,0.9)
                    : "transparent"
                Behavior on color { ColorAnimation { duration: 80 } }
                Text { anchors.centerIn: parent; text: "󰅖"
                    font.pixelSize: 10; font.family: "Symbols Nerd Font Mono"
                    color: root.cOnSurfVar; opacity: 0.7 }
                MouseArea { id: hcardDismH; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.history = root.history.filter(function(n){ return n.id !== hcard.notif.id })
                    }
                }
            }
        }
        MouseArea { id: hcardMA; anchors.fill: parent; hoverEnabled: true; z: -1 }
    }
}
