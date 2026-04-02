pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// ═══════════════════════════════════════════════════════════════════════════
//  Quickshell Notification + Bluetooth Agent Center
//  ~/.config/quickshell/notifications/shell.qml
//  toggle: qs -c notifications
// ═══════════════════════════════════════════════════════════════════════════

ShellRoot {
    id: root

    // ── Matugen colors ────────────────────────────────────────────────────
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

    readonly property color cPrimary:   Qt.color(_m3primary)
    readonly property color cOnPrim:    Qt.color(_m3onPrimary)
    readonly property color cSurfHi:    Qt.color(_m3surfaceContainerHigh)
    readonly property color cSurfMid:   Qt.color(_m3surfaceContainer)
    readonly property color cOnSurf:    Qt.color(_m3onSurface)
    readonly property color cOnSurfVar: Qt.color(_m3onSurfaceVariant)
    readonly property color cOutVar:    Qt.color(_m3outlineVariant)
    readonly property color cInvPrim:   Qt.color(_m3inversePrimary)
    readonly property color cErr:       Qt.color(_m3error)
    readonly property color cPanelBg:   Qt.rgba(
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

    // ── Waybar alignment ──────────────────────────────────────────────────
    property bool waybarAtBottom: false
    property real waybarSideMargin: 12
    property real waybarOuterRadius: 20
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
    FileView {
        path: Quickshell.env("HOME") + "/.config/hyprcandy/waybar_outer_radius.state"
        watchChanges: true; onFileChanged: reload()
        onLoaded: { const v = parseFloat(text().trim()); if (!isNaN(v) && v >= 0) root.waybarOuterRadius = v }
    }

    // ── IPC ───────────────────────────────────────────────────────────────
    property bool historyVisible: false
    property bool dndEnabled: false

    IpcHandler { target: "notifications"
        function toggle()        { root.historyVisible = !root.historyVisible }
        function toggleHistory() { root.historyVisible = !root.historyVisible }
        function open()          { root.historyVisible = true }
        function close()         { root.historyVisible = false }
        function dndOn()         { root.dndEnabled = true  }
        function dndOff()        { root.dndEnabled = false }
        function dndToggle()     { root.dndEnabled = !root.dndEnabled }
    }

    // ── Waybar notification state ──────────────────────────────────────────
    // Writes a JSON state file and pokes waybar signal 12 whenever dnd,
    // inhibitor state, or notification count changes. waybar custom/notifications
    // cats the file on signal so the icon and tooltip stay in sync.
    //
    // Icon key matrix (matches swaync format-icons):
    //   dnd  inhibited  hasNotifs  → key
    //   no   no         yes        → notification
    //   no   no         no         → none
    //   yes  no         yes        → dnd-notification
    //   yes  no         no         → dnd-none
    //   no   yes        yes        → inhibited-notification
    //   no   yes        no         → inhibited-none
    //   yes  yes        yes        → dnd-inhibited-notification
    //   yes  yes        no         → dnd-inhibited-none
    property bool inhibitorActive: false   // read from idle-inhibitor state file

    // Read idle inhibitor state written by idle-inhibitor.sh
    FileView {
        path: Quickshell.env("HOME") + "/.cache/waybar-idle-inhibitor.state"
        watchChanges: true; onFileChanged: reload()
        onLoaded: root.inhibitorActive = text().trim() === "active"
    }

    // Compute the icon key and emit to waybar whenever any relevant state changes
    function _waybarIconKey() {
        const has  = root.history.length > 0
        const dnd  = root.dndEnabled
        const inh  = root.inhibitorActive
        if (!dnd && !inh) return has ? "notification"          : "none"
        if ( dnd && !inh) return has ? "dnd-notification"      : "dnd-none"
        if (!dnd &&  inh) return has ? "inhibited-notification" : "inhibited-none"
        /* dnd && inh */  return has ? "dnd-inhibited-notification" : "dnd-inhibited-none"
    }
    function _waybarIconGlyph(key) {
        const map = {
            "notification":           "󰅸",
            "none":                   "󰂜",
            "dnd-notification":       "󱅫",
            "dnd-none":               "󰂠",
            "inhibited-notification": "󰅸",
            "inhibited-none":         "󱏬",
            "dnd-inhibited-notification": "󱅫",
            "dnd-inhibited-none":     "󱏫"
        }
        return map[key] || "󰂜"
    }
    function _emitWaybarState() {
        const key    = root._waybarIconKey()
        const icon   = root._waybarIconGlyph(key)
        const count  = root.history.length
        const tip    = root.dndEnabled ? "Do Not Disturb ON" : "Notifications"
        const cls    = root.dndEnabled ? "dnd" : (count > 0 ? "unread" : "")
        const json   = JSON.stringify({ text: icon, tooltip: tip, class: cls, alt: key, count: count })
        waybarStateProc._json = json
        if (!waybarStateProc.running) waybarStateProc.running = true
    }

    // Write state file then poke waybar signal 12.
    // Uses a helper script path so the JSON is passed via the property
    // at run time, not baked into the command array at bind time.
    // Writes the notification state JSON for the bar's Notifications module.
    // File is watched via FileView in Notifications.qml — no waybar signal needed.
    Process { id: waybarStateProc; property string _json: "{}"
        command: ["bash", "-c",
            "D=~/.cache/quickshell/notifications; mkdir -p \"$D\"; " +
            "printf '%s' \"$QS_NOTIF_STATE\" > \"$D/waybar-state.json\""
        ]
        environment: ({ "QS_NOTIF_STATE": waybarStateProc._json })
    }

    onDndEnabledChanged:      Qt.callLater(root._emitWaybarState)
    onInhibitorActiveChanged: Qt.callLater(root._emitWaybarState)
    onHistoryChanged:         Qt.callLater(root._emitWaybarState)

    // ═════════════════════════════════════════════════════════════════════
    //  DATA MODEL
    //  Each notification: { id, appName, summary, body, icon, iconPath,
    //    urgency, timestamp, actions[], category, isPrompt, promptType,
    //    promptMac, promptName, promptPasskey, promptTransfer,
    //    promptFilename, promptSize, count, groupKey }
    // ═════════════════════════════════════════════════════════════════════
    property var notifications: []   // active toasts
    property var history: []         // persistent history
    property int _nextId: 1

    // ── Icon glyph resolver ───────────────────────────────────────────────
    function iconGlyph(notif) {
        const ic = (notif.icon || "").toLowerCase()
        const ap = (notif.appName || "").toLowerCase()
        const cat = notif.category || ""
        if (cat === "bt" || ic === "bluetooth" || ic.includes("bluetooth")) return "󰂯"  // nf-md-bluetooth
        if (ic.includes("wireless") || ic === "network-wireless")           return "󰤨"  // nf-md-wifi_strength_4
        if (ic === "network" || ic.includes("ethernet"))                    return "󰈀"  // nf-md-ethernet
        if (cat === "media.playing" || ap === "now playing") return "󰝚"   // nf-md-music_note
        if (ic.includes("volume") || ic.includes("audio") || ic.includes("sound")) return "󰕾"  // nf-md-volume_high
        if (ic.includes("battery"))                                         return "󰁹"  // nf-md-battery
        if (ic.includes("screenshot") || ap.includes("screenshot"))        return "󰹑"  // nf-md-monitor_screenshot
        if (ic.includes("record") || ap.includes("record") || ap.includes("obs")) return "󰑋"  // nf-md-record_circle
        if (ic.includes("mail") || ap.includes("mail") || ap.includes("thunderbird")) return "󰇮"  // nf-md-email
        if (ic.includes("discord") || ap.includes("discord"))              return "󰙯"  // nf-md-discord
        if (ic.includes("telegram") || ap.includes("telegram"))            return ""   // nf-fa-telegram
        if (ic.includes("spotify") || ap.includes("spotify"))              return "󰓇"  // nf-md-spotify
        if (ic.includes("firefox") || ap.includes("firefox"))              return "󰈹"  // nf-md-firefox
        if (ic.includes("chrome") || ic.includes("chromium"))              return ""   // nf-dev-chrome
        if (ic.includes("update") || ic.includes("package") || ap.includes("pacman")) return "󰏖"  // nf-md-package
        if (ic.includes("calendar") || ap.includes("calendar"))            return "󰃭"  // nf-md-calendar
        if (ic.includes("download"))                                        return "󰇚"  // nf-md-download
        if (ic.includes("upload"))                                          return "󰇹"  // nf-md-upload
        if (ic.includes("error") || ic.includes("critical") || notif.urgency >= 2) return "󰀦"  // nf-md-alert_circle
        if (ic.includes("warning") || ic.includes("warn"))                 return "󰀪"  // nf-md-alert
        if (ic.includes("info"))                                            return "󰋼"  // nf-md-information
        if (ic.includes("success") || ic.includes("complete"))             return "󰄬"  // nf-md-check_circle
        if (ic.includes("clock") || ic.includes("alarm"))                  return "󰥔"  // nf-md-clock
        if (ic.includes("usb") || ap.includes("usb"))                      return "󰙈"  // nf-md-usb
        return "󰂞"   // nf-md-bell  notification bell (default)
    }

    function groupKey(n) {
        return (n.appName || "") + "|" + (n.summary || "")
    }

    function addNotification(obj) {
        const n = Object.assign({
            id: root._nextId++, appName: "", summary: "", body: "", icon: "", iconPath: "",
            urgency: 1, timestamp: Date.now(), actions: [], category: "app",
            isPrompt: false, count: 1
        }, obj)
        n.groupKey = groupKey(n)

        // Toast queue — replace same-group non-prompt (bump count)
        // Toast queue — suppress when DnD is active (prompts + critical always show)
        if (!root.dndEnabled || n.isPrompt || n.urgency >= 2) {
            const q = root.notifications.slice()
            const ei = q.findIndex(function(x) { return x.groupKey === n.groupKey && !x.isPrompt })
            if (ei >= 0 && !n.isPrompt) {
                n.count = (q[ei].count || 1) + 1
                q.splice(ei, 1)
            }
            q.unshift(n)
            if (q.length > 6) q.pop()
            root.notifications = q
        }

        // History — group + bump. All non-prompt notifications go here.
        // media.playing: always match on category so the single media card updates
        // in-place (no splice+unshift) regardless of track title changes.
        // All other notifications: match on groupKey, bump count, move to top.
        if (!n.isPrompt) {
            const h = root.history.slice()
            const isMedia = n.category === "media.playing"
            const hi = isMedia
                ? h.findIndex(function(x) { return x.category === "media.playing" })
                : h.findIndex(function(x) { return x.groupKey === n.groupKey })
            if (hi >= 0) {
                const updated = Object.assign({}, h[hi], {
                    summary:   n.summary,
                    body:      n.body,
                    iconPath:  n.iconPath || h[hi].iconPath,
                    icon:      n.icon,
                    timestamp: n.timestamp,
                    count:     isMedia ? (h[hi].count || 1) : (h[hi].count || 1) + 1
                })
                if (isMedia) {
                    // Update in-place — card stays at its current position in the list
                    h[hi] = updated
                } else {
                    h.splice(hi, 1)
                    h.unshift(updated)
                }
            } else {
                h.unshift(n)
                if (h.length > 60) h.pop()
            }
            root.history = h
        }
        return n.id
    }

    // Invoke a notification action via DBus ActionInvoked signal.
    // ── Action invocation ─────────────────────────────────────────────────
    // actionInvokerProc fires gdbus ActionInvoked so the sending app reacts.
    // urlOpenerProc handles xdg-open for the "default" action (click-to-focus).
    // Pass daemonId and actionKey as argv so no quoting is needed inside the
    // QML string — argv[1] and argv[2] are never interpreted by the shell.
    Process { id: actionInvokerProc
        property int  _nid: 0
        property string _key: ""
        command: ["gdbus", "call", "--session",
                  "--dest",        "org.freedesktop.Notifications",
                  "--object-path", "/org/freedesktop/Notifications",
                  "--method",      "org.freedesktop.Notifications.ActionInvoked",
                  actionInvokerProc._nid.toString(), actionInvokerProc._key] }
    Process { id: urlOpenerProc; property string _url: ""
        command: ["xdg-open", urlOpenerProc._url] }

    function invokeAction(notif, actionKey) {
        const daemonId = notif._daemonId || notif.id
        actionInvokerProc._nid = daemonId
        actionInvokerProc._key = actionKey
        if (!actionInvokerProc.running) actionInvokerProc.running = true
        if (actionKey === "default") {
            const m = (notif.body || "").match(/https?:\/\/\S+/)
            if (m) {
                urlOpenerProc._url = m[0]
                if (!urlOpenerProc.running) urlOpenerProc.running = true
            }
        }
    }

    function dismissNotification(id) {
        root.notifications = root.notifications.filter(function(n) { return n.id !== id })
    }
    function clearHistory() { root.history = [] }

    // ═════════════════════════════════════════════════════════════════════
    //  NOTIFICATION DAEMON  (claims org.freedesktop.Notifications)
    // ═════════════════════════════════════════════════════════════════════
    Process { id: notifDaemonProc
        command: ["python3", "-u",
            Quickshell.env("HOME") + "/.config/quickshell/notifications/notify-daemon.py"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (!l.trim()) return
            try { root._handleNotifEvent(JSON.parse(l)) } catch(e) {}
        }}
        stderr: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (l.trim()) console.warn("notify-daemon:", l)
        }}
        Component.onCompleted: running = true
        onExited: function(code, status) {
            console.warn("notify-daemon exited code=" + code + " status=" + status)
            Qt.callLater(function() { if (!running) running = true })
        }
    }

    function _handleNotifEvent(ev) {
        if (ev.type !== "notify") return
        const urgMap = { "low": 0, "normal": 1, "critical": 2 }
        addNotification({
            appName:  ev.app_name  || "",
            summary:  ev.summary   || "",
            body:     ev.body      || "",
            icon:     ev.icon      || "",
            iconPath: ev.icon_path || "",
            urgency:  urgMap[ev.urgency] !== undefined ? urgMap[ev.urgency] : 1,
            actions:  ev.actions   || [],
            category: ev.category  || "app",
            _daemonId: ev.id
        })
    }

    // ═════════════════════════════════════════════════════════════════════
    //  BLUETOOTH AGENT
    // ═════════════════════════════════════════════════════════════════════
    property bool btAgentReady: false

    // ── Fifo setup ──────────────────────────────────────────────────────────
    // Create the fifo once, then immediately open a persistent write-end
    // holder (sleep infinity) so bt-agent.py never sees EOF on its stdin.
    // Without this every short-lived btAgentStdinProc write closes the
    // last writer, delivering EOF → bt-agent exits (code=9).
    //
    // IMPORTANT: kill any stale holders from a previous instance BEFORE
    // starting a new one — otherwise every qs restart stacks another
    // "sleep infinity" process that never gets reaped.
    Process { id: btFifoInitProc
        command: ["bash", "-c",
            "pkill -f 'sleep infinity >> /tmp/qs_bt_cmd' 2>/dev/null; sleep 0.1; " +
            "[ -p /tmp/qs_bt_cmd ] || (rm -f /tmp/qs_bt_cmd && mkfifo /tmp/qs_bt_cmd)"]
        Component.onCompleted: running = true
        onExited: btFifoHolderRestartTimer.restart()
    }

    // Persistent writer keeping the fifo write-end open indefinitely.
    // onExited uses a timer so it never re-enters synchronously, and only
    // restarts when not already running to prevent accumulation.
    Process { id: btFifoHolderProc
        command: ["bash", "-c", "sleep infinity >> /tmp/qs_bt_cmd"]
        onExited: btFifoHolderRestartTimer.restart()
    }
    Timer { id: btFifoHolderRestartTimer; interval: 500; repeat: false
        onTriggered: {
            if (!btFifoHolderProc.running) btFifoHolderProc.running = true
            if (!btAgentProc.running)      btAgentProc.running = true
        }
    }

    // Agent process — bt-agent.py opens the fifo itself via its stdin_reader loop.
    Process { id: btAgentProc
        command: ["python3", "-u",
            Quickshell.env("HOME") +
            "/.config/quickshell/notifications/bt-agent.py"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (!l.trim()) return
            try { root._handleBtAgentEvent(JSON.parse(l)) } catch(e) {}
        }}
        stderr: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (l.trim()) console.warn("bt-agent:", l)
        }}
        onExited: function(code, status) {
            root.btAgentReady = false
            console.warn("bt-agent exited code=" + code)
            btAgentRestartTimer.restart()
        }
    }
    Timer { id: btAgentRestartTimer; interval: 3000; repeat: false
        onTriggered: { if (!btAgentProc.running) btAgentProc.running = true }
    }

    // Send a command to bt-agent.py via the fifo.
    Process { id: btAgentStdinProc; property string _cmd: ""
        command: ["bash", "-c", "printf '%s\\n' " + btAgentStdinProc._cmd + " >> /tmp/qs_bt_cmd"]
    }
    function btAgentSend(cmd) {
        btAgentStdinProc._cmd = "'" + cmd.replace(/'/g, "'\\''" ) + "'"
        if (!btAgentStdinProc.running) btAgentStdinProc.running = true
    }

    function _handleBtAgentEvent(ev) {
        switch (ev.type) {
        case "agent_ready":
            root.btAgentReady = true
            break
        case "pair_confirm":
            addNotification({ isPrompt: true, promptType: "pair_confirm",
                promptMac: ev.mac, promptName: ev.name || ev.mac, promptPasskey: ev.passkey || "",
                summary: "Bluetooth Pairing Request", body: "Confirm passkey on " + (ev.name || ev.mac),
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "pair_pin":
            addNotification({ isPrompt: true, promptType: "pair_pin",
                promptMac: ev.mac, promptName: ev.name || ev.mac, promptNeedsPasskey: ev.needs_passkey || false,
                summary: "Bluetooth PIN Required", body: "Enter PIN for " + (ev.name || ev.mac),
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "pair_authorize":
            addNotification({ isPrompt: true, promptType: "pair_authorize",
                promptMac: ev.mac, promptName: ev.name || ev.mac,
                summary: "Bluetooth Pair Request", body: (ev.name || ev.mac) + " wants to pair",
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "display_pin":
            addNotification({ summary: "Bluetooth PIN",
                body: "PIN for " + (ev.name || ev.mac) + ": " + ev.pin,
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "pair_cancelled":
            if (ev.mac) root.notifications = root.notifications.filter(function(n) {
                return !(n.isPrompt && n.promptMac === ev.mac)
            })
            addNotification({ summary: "Bluetooth", body: "Pairing cancelled",
                icon: "bluetooth", urgency: 1, category: "bt" })
            break
        case "file_request":
            const szMb = ev.size > 0 ? (ev.size / 1048576).toFixed(1) + " MB" : ""
            addNotification({ isPrompt: true, promptType: "file_accept",
                promptMac: ev.mac, promptName: ev.name || ev.mac,
                promptTransfer: ev.transfer, promptFilename: ev.filename || "file", promptSize: szMb,
                summary: "Incoming File",
                body: (ev.name || ev.mac) + " → " + (ev.filename || "file") + (szMb ? " (" + szMb + ")" : ""),
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "file_cancelled":
            addNotification({ summary: "Bluetooth", body: "File transfer cancelled",
                icon: "bluetooth", urgency: 1, category: "bt" })
            break
        case "error":
            console.warn("bt-agent:", ev.msg)
            break
        }
    }

    // ── Auto-dismiss ───────────────────────────────────────────────────────
    Timer { id: autoDismissTimer; interval: 200; repeat: true; running: true
        onTriggered: {
            const now = Date.now()
            const rem = root.notifications.filter(function(n) {
                if (n.isPrompt || n.urgency >= 2) return true
                if (n.category === "media.playing") return (now - n.timestamp) < 5000
                return (now - n.timestamp) < 5000
            })
            if (rem.length !== root.notifications.length) root.notifications = rem
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  TOAST WINDOW
    //  Transparent container — each ToastCard is its own opaque surface.
    //  height is driven by an invisible Item that mirrors the Column's
    //  implicitHeight so the binding never races.
    // ═════════════════════════════════════════════════════════════════════
    PanelWindow {
        id: toastWindow
        visible: root.notifications.length > 0
        WlrLayershell.namespace: "quickshell:notifications:toasts"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: {
            for (let i = 0; i < root.notifications.length; i++)
                if (root.notifications[i].isPrompt && root.notifications[i].promptType === "pair_pin")
                    return WlrKeyboardFocus.OnDemand
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
        width:  364
        height: toastCol.implicitHeight + 4
        color: "transparent"  // transparent = no unified shadow rect across the window surface
        exclusionMode: ExclusionMode.Ignore

        Column {
            id: toastCol
            anchors { top: parent.top; left: parent.left; right: parent.right }
            spacing: 6

            Repeater {
                model: root.notifications
                delegate: ToastCard {
                    required property var modelData
                    required property int index
                    notif:  modelData
                    width:  toastCol.width
                }
            }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  CLOSE ON REAL-WINDOW FOCUS
    //  Watches HyprlandFocusedClient: fires whenever Hyprland reports a
    //  newly focused *client* (i.e. a regular XDG toplevel window).
    //  Layer shells (waybar, rofi, dock, other quickshell panels) are NOT
    //  tracked as focused clients by Hyprland, so interacting with them
    //  does NOT trigger this and the panels stay open as requested.
    //  Only a genuine click into a normal app window closes them.
    // ═════════════════════════════════════════════════════════════════════
    Connections {
        target: HyprlandFocusedClient
        function onAddressChanged() {
            root.historyVisible = false
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  HISTORY PANEL
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
        margins { top: 6; bottom: 6; left: root.waybarSideMargin }
        width:  380
        // Height grows with content up to 720px max, then the Flickable scrolls.
        height: Math.min(histScrollContent.height + histHeader.implicitHeight + histDivider.height + 42, 720)
        color:  "transparent"


        Rectangle {
            id: histPanel
            anchors.fill: parent
            color:  root.cPanelBg
            radius: root.waybarOuterRadius
            border.width: 1
            border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.40)
            scale: root.historyVisible ? 1.0 : 0.92
            transformOrigin: Item.TopLeft
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Keys.onEscapePressed: root.historyVisible = false

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                id: histHeader
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
                spacing: 8

                // ── DnD toggle button ─────────────────────────────────────
                // Shows the same icon matrix as waybar custom/notifications.
                // Click toggles Do Not Disturb; icon reflects dnd + inhibitor + unread state.
                Rectangle {
                    id: dndBtn
                    height: 28; width: 28; radius: 8
                    color: dndBtnMA.containsMouse
                        ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.18)
                        : root.dndEnabled
                            ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.14)
                            : "transparent"
                    border.width: 1
                    border.color: root.dndEnabled
                        ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.50)
                        : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.40)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text {
                        anchors.centerIn: parent
                        text: root._waybarIconGlyph(root._waybarIconKey())
                        font.pixelSize: 15; font.family: "Symbols Nerd Font Mono"
                        color: root.dndEnabled ? root.cErr : root.cPrimary
                        Behavior on color { ColorAnimation { duration: 120 } }
                    }
                    MouseArea {
                        id: dndBtnMA; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dndEnabled = !root.dndEnabled
                    }
                }

                Text {
                    text: root.dndEnabled ? "Do Not Disturb" : "Notifications"
                    color: root.dndEnabled
                        ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.85)
                        : root.cOnSurf
                    font.pixelSize: 14; font.weight: Font.Medium
                    font.family: "Symbols Nerd Font Mono"
                    Layout.fillWidth: true
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                // BT status dot
                Rectangle {
                    width: 8; height: 8; radius: 4
                    color: root.btAgentReady
                        ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.9)
                        : Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.7)
                }
                Item { width: 2 }
                // Clear all
                Rectangle {
                    height: 24; implicitWidth: clrLbl.implicitWidth + 16; radius: 8
                    color: clrH.containsMouse
                        ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.18)
                        : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.6)
                    border.width: 1
                    border.color: clrH.containsMouse
                        ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.85)
                        : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.55)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Behavior on border.color { ColorAnimation { duration: 100 } }
                    Text { id: clrLbl; anchors.centerIn: parent; text: "Clear all"
                        color: clrH.containsMouse ? root.cErr : root.cOnSurfVar
                        font.pixelSize: 11
                        Behavior on color { ColorAnimation { duration: 100 } }
                    }
                    MouseArea { id: clrH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor; onClicked: root.clearHistory() }
                }
                
                Rectangle {
                    height: 24; width: 24; radius: 8
                    color: clsH.containsMouse
                        ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.9)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 100 } }
                    
                    Text { anchors.centerIn: parent; text: "×"
                        font.pixelSize: 12; color: root.cOnSurfVar }
                    MouseArea { id: clsH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.historyVisible = false }
                }
            }

            Rectangle {
                id: histDivider
                anchors { top: histHeader.bottom; topMargin: 8; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                height: 1
                color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.3)
            }

            // ── Scrollable history list ───────────────────────────────────
            // Swipe-to-dismiss is handled per-card via a WheelHandler inside
            // each HistoryCard — no cursor-Y arithmetic needed.
            Flickable {
                id: histFlickable
                anchors {
                    top: histDivider.bottom; topMargin: 8
                    left: parent.left; right: parent.right; bottom: parent.bottom
                    leftMargin: 10; rightMargin: 10; bottomMargin: 10
                }
                clip: true
                // Bind to .height not .implicitHeight — ColumnLayout.implicitHeight
                // does NOT react to children's explicit height: changes (e.g. card
                // expand animations). .height does once the layout has height:implicitHeight.
                contentHeight: histScrollContent.height
                flickableDirection: Flickable.VerticalFlick
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: histScrollContent
                    width: parent.width
                    // Explicit height makes contentHeight track expand/collapse live.
                    height: implicitHeight
                    spacing: 5

                    // Empty state — fixed height matches one collapsed HistoryCard
                    // (cardInner min ~34px icon + 12 topMargin + 24 card padding = 70px)
                    // so the panel doesn't resize when the last notification is cleared.
                    Item {
                        visible: root.history.length === 0
                        Layout.fillWidth: true
                        height: 44
                        Text {
                            anchors.centerIn: parent
                            text: "No notifications"
                            color: root.cOnSurfVar; font.pixelSize: 12; font.italic: true
                        }
                    }

                    Repeater {
                        model: root.history
                        delegate: HistoryCard {
                            required property var modelData
                            notif: modelData
                            flickable: histFlickable
                            Layout.fillWidth: true
                        }
                    }
                    Item { height: 4 }
                }
            }

        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  TOAST CARD COMPONENT
    //  Per-card blur that respects rounded corners — no Hyprland layerrule needed.
    //  Uses the same Item + layer.effect MultiEffect mask technique as the lockscreen
    //  floating panel: all children render to one FBO, then MultiEffect masks the FBO
    //  to a rounded rect shape (supplied by an opacity:0 Rectangle with its own layer),
    //  so the blur is composited already-clipped and never bleeds past the corners.
    // ═════════════════════════════════════════════════════════════════════
    component ToastCard: Item {
        id: toast
        required property var notif
        property bool _hov: toastMA.containsMouse
        property real _radius: 14

        // Height driven by content + progress bar slot (same as before, just on Item)
        height: cardInner.implicitHeight + 24 + (progTrackItem.visible ? 4 : 0)

        // ── Rounded-corner blur: render all children to FBO, mask to rounded rect ──
        // Identical technique to shell-lockscreen.qml centerPanel:
        //   1. layer.enabled renders all children to a single FBO.
        //   2. MultiEffect masks the FBO using toastRoundMask's layer alpha.
        //   3. toastRoundMask is opacity:0 (invisible in scene) but its layer FBO
        //      (captured before the opacity pass) supplies the mask texture.
        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled:      true
            maskSource:       toastRoundMask
            maskThresholdMin: 0.5
            maskSpreadAtMin:  1.0
        }

        // Mask shape — white rounded rect at opacity:0.
        Rectangle {
            id: toastRoundMask
            anchors.fill: parent
            radius: toast._radius
            color: "white"
            opacity: 0
            layer.enabled: true
        }

        // ── Blurred backdrop slice ─────────────────────────────────────────
        // Captures the toastWindow's own background colour and blurs it so each
        // card gets an individual frosted-glass look without a shared layer surface.
        // (toastWindow.color is already set to cPanelBg — nearly transparent —
        //  so this primarily blurs compositor content showing through the window.)
        Item {
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true; blur: 1.0; blurMax: 48
            }
            // Extend the source rect to the full window so sampling at edges
            // doesn't wrap/clamp — same trick as the lockscreen wallpaper slice.
            Rectangle {
                x: -toast.x; y: -toast.y
                width:  toastWindow.width
                height: toastWindow.height
                color:  Qt.rgba(root.cSurfMid.r, root.cSurfMid.g, root.cSurfMid.b, 0.72)
            }
        }

        // ── Card surface (tint + border, radius matches mask) ──────────────
        Rectangle {
            anchors.fill: parent
            radius: toast._radius
            color: toast._hov
                ? Qt.rgba(root.cSurfHi.r,  root.cSurfHi.g,  root.cSurfHi.b,  0.55)
                : Qt.rgba(root.cSurfMid.r, root.cSurfMid.g, root.cSurfMid.b, 0.45)
            border.width: 1
            border.color: toast.notif.urgency >= 2
                ? Qt.rgba(root.cErr.r,     root.cErr.g,     root.cErr.b,     0.6)
                : toast.notif.category === "bt"
                    ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.5)
                    : toast.notif.category === "media.playing"
                        ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.35)
                        : Qt.rgba(root.cOutVar.r,  root.cOutVar.g,  root.cOutVar.b,  0.38)
            Behavior on color { ColorAnimation { duration: 100 } }
        }

        // ── Slide-in animation ────────────────────────────────────────────
        property real _p: 0
        NumberAnimation on _p { from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic; running: true }
        opacity: _p
        transform: Translate { x: -(1 - toast._p) * 24 }

        // ── Left urgency accent bar ───────────────────────────────────────
        Rectangle {
            x: 0; y: 0; width: 3
            // Clip accent bar with same radius as card
            height: parent.height - toast._radius
            color: toast.notif.urgency >= 2 ? root.cErr
                : toast.notif.category === "bt" ? root.cPrimary
                : toast.notif.category === "media.playing"
                    ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.5)
                    : Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.45)
        }
        // Rounded bottom of accent bar
        Rectangle {
            x: 0; width: 3; radius: 2
            y: parent.height - toast._radius * 2
            height: toast._radius * 2
            color: toast.notif.urgency >= 2 ? root.cErr
                : toast.notif.category === "bt" ? root.cPrimary
                : toast.notif.category === "media.playing"
                    ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.5)
                    : Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.45)
        }

        // ── Progress bar — sits at bottom inside rounded corners ──────────
        // Uses an Item clipped to the card's rounded bottom area
        Item {
            id: progTrackItem
            visible: !toast.notif.isPrompt && toast.notif.urgency < 2
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 3
            // Clip so it never bleeds outside card radius
            clip: true

            Rectangle {
                id: progBg
                anchors.fill: parent
                // Small bottom radius to match card
                radius: toast._radius
                color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.22)

                property real _age: 0
                Timer {
                    interval: 80; repeat: true; running: progTrackItem.visible
                    onTriggered: progBg._age = Math.min(1, (Date.now() - toast.notif.timestamp) / 5000)
                }

                // Filled portion
                Rectangle {
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                    width: progBg.width * Math.max(0, 1 - progBg._age)
                    color: root.cPrimary
                    radius: toast._radius
                    Behavior on width { NumberAnimation { duration: 80 } }
                }
            }
        }

        // ── Main content ──────────────────────────────────────────────────
        ColumnLayout {
            id: cardInner
            anchors {
                left: parent.left; right: parent.right; top: parent.top
                leftMargin: 14; rightMargin: 10; topMargin: 12
            }
            spacing: 6

            // Header row
            RowLayout { Layout.fillWidth: true; spacing: 10

                // Icon area — media.playing shows circular album art (48px),
                // all others show app icon or glyph (34px)
                Item {
                    width:  toast.notif.category === "media.playing" ? 48 : 34
                    height: toast.notif.category === "media.playing" ? 48 : 34
                    Rectangle { anchors.fill: parent
                        radius: toast.notif.category === "media.playing" ? width / 2 : 9
                        color: toast.notif.urgency >= 2
                            ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.18)
                            : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.15)
                    }
                    // For media.playing, clip album art to circle using the
                    // same MultiEffect mask technique as the ToastCard itself.
                    Item {
                        id: toastIcImgWrap
                        anchors { fill: parent; margins: toast.notif.category === "media.playing" ? 0 : 4 }
                        visible: toastIcImg.status === Image.Ready
                        layer.enabled: toast.notif.category === "media.playing"
                        layer.effect: MultiEffect {
                            maskEnabled:      true
                            maskSource:       toastArtMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin:  1.0
                        }
                        Rectangle {
                            id: toastArtMask
                            anchors.fill: parent; radius: width / 2
                            color: "white"; opacity: 0; layer.enabled: true
                        }
                        Image {
                            id: toastIcImg
                            anchors.fill: parent
                            source: toast.notif.iconPath ? "file://" + toast.notif.iconPath : ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true; mipmap: true
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: !toastIcImg.visible
                        text: root.iconGlyph(toast.notif)
                        font.pixelSize: toast.notif.category === "media.playing" ? 22 : 17
                        font.family: "Symbols Nerd Font Mono"
                        color: toast.notif.urgency >= 2 ? root.cErr : root.cPrimary
                    }
                    // Group count badge
                    Rectangle {
                        visible: (toast.notif.count || 1) > 1
                        anchors { right: parent.right; top: parent.top; rightMargin: -2; topMargin: -2 }
                        width: 16; height: 16; radius: 8; color: root.cPrimary
                        Text { anchors.centerIn: parent; text: toast.notif.count || 1
                            font.pixelSize: 9; color: root.cOnPrim; font.weight: Font.Bold }
                    }
                }

                // App name + summary
                ColumnLayout { Layout.fillWidth: true; spacing: 1
                    Text { Layout.fillWidth: true
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

                // Dismiss ×
                Rectangle { width: 22; height: 22; radius: 6
                    color: dH.containsMouse
                        ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.9)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "×"
                        font.pixelSize: 11; color: root.cOnSurfVar }
                    MouseArea { id: dH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dismissNotification(toast.notif.id) }
                }
            }

            // Body text
            Text {
                visible: (toast.notif.body || "") !== ""
                Layout.fillWidth: true
                text: toast.notif.body || ""
                color: root.cOnSurfVar; font.pixelSize: 11
                wrapMode: Text.WordWrap; maximumLineCount: 4; elide: Text.ElideRight
                leftPadding: 44
            }

            // ── Thumbnail — shown when the icon IS a file path (screenshots,
            //   recordings, etc.). Media album art is already shown as a circle
            //   in the icon area so it is excluded here.
            // Detection: notif.icon starts with "/" means notify-send -i /path/to/file
            Image {
                id: toastThumb
                property bool _isFilePath: (toast.notif.icon || "").startsWith("/") ||
                                           (toast.notif.icon || "").startsWith("file://")
                visible: _isFilePath &&
                         toast.notif.category !== "media.playing" &&
                         !toast.notif.isPrompt &&
                         status === Image.Ready
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(implicitHeight, 180)
                source: toast.notif.iconPath ? "file://" + toast.notif.iconPath : ""
                fillMode: Image.PreserveAspectFit
                smooth: true; mipmap: true
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled:      true
                    maskSource:       thumbMask
                    maskThresholdMin: 0.5
                    maskSpreadAtMin:  1.0
                }
                Rectangle {
                    id: thumbMask
                    anchors.fill: parent
                    radius: 8; color: "white"; opacity: 0; layer.enabled: true
                }
            }

            // Action buttons (non-prompt, standard freedesktop actions)
            Flow {
                visible: (toast.notif.actions || []).length > 0 && !toast.notif.isPrompt
                Layout.fillWidth: true; spacing: 6; leftPadding: 44
                Repeater { model: toast.notif.actions || []
                    delegate: Rectangle {
                        required property var modelData
                        visible: modelData.key !== "default"
                        height: 26; implicitWidth: aLbl.implicitWidth + 16; radius: 8
                        color: aH.containsMouse
                            ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.22)
                            : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.7)
                        border.width: 1
                        border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.35)
                        Behavior on color { ColorAnimation { duration: 80 } }
                        Text { id: aLbl; anchors.centerIn: parent
                            text: modelData.label || modelData.key || ""
                            color: root.cOnSurf; font.pixelSize: 10 }
                        MouseArea { id: aH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.invokeAction(toast.notif, modelData.key)
                                root.dismissNotification(toast.notif.id)
                            }
                        }
                    }
                }
            }

            // ── BT Pair Confirm (show passkey, Accept/Reject) ─────────────
            ColumnLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "pair_confirm"
                Layout.fillWidth: true; spacing: 8; Layout.leftMargin: 44

                Rectangle {
                    Layout.alignment: Qt.AlignLeft
                    height: 40; radius: 10; implicitWidth: pkT.implicitWidth + 32
                    color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.12)
                    border.width: 1; border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.5)
                    Text { id: pkT; anchors.centerIn: parent
                        text: toast.notif.promptPasskey || "------"
                        color: root.cPrimary; font.pixelSize: 22; font.weight: Font.Bold; font.letterSpacing: 7
                    }
                }
                Text { text: "Confirm this passkey appears on the device"
                    color: root.cOnSurfVar; font.pixelSize: 10; font.italic: true }
                RowLayout { spacing: 8
                    Rectangle { height: 32; implicitWidth: 88; radius: 8
                        color: pcA.containsMouse ? root.cPrimary
                            : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "󰄬  Accept"   // 󰄬
                            color: root.cOnPrim; font.pixelSize: 11
                            font.family: "Symbols Nerd Font Mono"; font.weight: Font.Medium }
                        MouseArea { id: pcA; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.btAgentSend("accept_pair " + toast.notif.promptMac)
                                root.dismissNotification(toast.notif.id)
                                root.addNotification({ summary: "Bluetooth", body: "Paired with " + toast.notif.promptName,
                                    icon: "bluetooth", urgency: 1, category: "bt" })
                            }
                        }
                    }
                    Rectangle { height: 32; implicitWidth: 80; radius: 8
                        color: pcR.containsMouse
                            ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.85)
                            : Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.15)
                        border.width: 1; border.color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.5)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "×  Reject"
                            color: pcR.containsMouse ? root.cOnPrim : root.cErr; font.pixelSize: 11 }
                        MouseArea { id: pcR; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.btAgentSend("reject_pair " + toast.notif.promptMac)
                                root.dismissNotification(toast.notif.id)
                            }
                        }
                    }
                }
            }

            // ── BT Pair Authorize (no passkey) ────────────────────────────
            RowLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "pair_authorize"
                Layout.fillWidth: true; spacing: 8; Layout.leftMargin: 44
                Rectangle { height: 32; implicitWidth: 80; radius: 8
                    color: paA.containsMouse ? root.cPrimary
                        : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "󰄬  Pair"   // 󰄬
                        color: root.cOnPrim; font.pixelSize: 11
                        font.family: "Symbols Nerd Font Mono"; font.weight: Font.Medium }
                    MouseArea { id: paA; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.btAgentSend("accept_pair " + toast.notif.promptMac)
                            root.dismissNotification(toast.notif.id)
                            root.addNotification({ summary: "Bluetooth", body: "Paired with " + toast.notif.promptName,
                                icon: "bluetooth", urgency: 1, category: "bt" })
                        }
                    }
                }
                Rectangle { height: 32; implicitWidth: 80; radius: 8
                    color: paR.containsMouse
                        ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.85)
                        : Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.15)
                    border.width: 1; border.color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.5)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "Reject"
                        color: paR.containsMouse ? root.cOnPrim : root.cErr; font.pixelSize: 11 }
                    MouseArea { id: paR; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.btAgentSend("reject_pair " + toast.notif.promptMac)
                            root.dismissNotification(toast.notif.id)
                        }
                    }
                }
            }

            // ── BT PIN entry ───────────────────────────────────────────────
            ColumnLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "pair_pin"
                Layout.fillWidth: true; spacing: 8; Layout.leftMargin: 44
                RowLayout { spacing: 8
                    Rectangle { height: 34; Layout.preferredWidth: 160; radius: 8
                        color: Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.8)
                        border.width: 1
                        border.color: pinIn.activeFocus
                            ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.7)
                            : Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.5)
                        TextInput {
                            id: pinIn
                            anchors { fill: parent; margins: 8 }
                            color: root.cOnSurf; font.pixelSize: 15; font.letterSpacing: 4
                            inputMethodHints: Qt.ImhDigitsOnly
                            onAccepted: {
                                if (text.length > 0) {
                                    root.btAgentSend("pin_pair " + toast.notif.promptMac + " " + text)
                                    root.dismissNotification(toast.notif.id)
                                }
                            }
                        }
                        Text { anchors.centerIn: pinIn; text: "PIN"
                            color: Qt.rgba(root.cOnSurfVar.r, root.cOnSurfVar.g, root.cOnSurfVar.b, 0.45)
                            font.pixelSize: 13
                            visible: pinIn.text.length === 0 && !pinIn.activeFocus
                        }
                        Component.onCompleted: pinIn.forceActiveFocus()
                    }
                    Rectangle { height: 34; width: 52; radius: 8
                        color: pOk.containsMouse ? root.cPrimary
                            : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "OK"
                            color: root.cOnPrim; font.pixelSize: 12; font.weight: Font.Bold }
                        MouseArea { id: pOk; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (pinIn.text.length > 0) {
                                    root.btAgentSend("pin_pair " + toast.notif.promptMac + " " + pinIn.text)
                                    root.dismissNotification(toast.notif.id)
                                }
                            }
                        }
                    }
                    Rectangle { height: 34; width: 64; radius: 8
                        color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.15)
                        border.width: 1; border.color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.4)
                        Text { anchors.centerIn: parent; text: "Cancel"
                            color: root.cErr; font.pixelSize: 11 }
                        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.btAgentSend("reject_pair " + toast.notif.promptMac)
                                root.dismissNotification(toast.notif.id)
                            }
                        }
                    }
                }
            }

            // ── File transfer Accept/Decline ───────────────────────────────
            RowLayout {
                visible: toast.notif.isPrompt && toast.notif.promptType === "file_accept"
                Layout.fillWidth: true; spacing: 8; Layout.leftMargin: 44
                Rectangle { height: 32; implicitWidth: 100; radius: 8
                    color: faA.containsMouse ? root.cPrimary
                        : Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.85)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "󰇚  Accept"   // 󰃼
                        color: root.cOnPrim; font.pixelSize: 11
                        font.family: "Symbols Nerd Font Mono"; font.weight: Font.Medium }
                    MouseArea { id: faA; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.btAgentSend("accept_file " + toast.notif.promptTransfer)
                            root.dismissNotification(toast.notif.id)
                            root.addNotification({ summary: "File Received",
                                body: toast.notif.promptFilename + " saved to Downloads",
                                icon: "bluetooth", urgency: 1, category: "bt" })
                        }
                    }
                }
                Rectangle { height: 32; implicitWidth: 80; radius: 8
                    color: faR.containsMouse
                        ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.85)
                        : Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.15)
                    border.width: 1; border.color: Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.5)
                    Behavior on color { ColorAnimation { duration: 100 } }
                    Text { anchors.centerIn: parent; text: "Decline"
                        color: faR.containsMouse ? root.cOnPrim : root.cErr; font.pixelSize: 11 }
                    MouseArea { id: faR; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.btAgentSend("reject_file " + toast.notif.promptTransfer)
                            root.dismissNotification(toast.notif.id)
                        }
                    }
                }
                Text { visible: (toast.notif.promptSize || "") !== ""
                    text: toast.notif.promptSize || ""
                    color: root.cOnSurfVar; font.pixelSize: 10
                }
            }

            Item { height: 2 }
        }

        // Click-to-dismiss: left click anywhere on a non-prompt card dismisses it.
        // Action buttons and the × button have their own MouseAreas with z>0,
        // so clicks on those are consumed before reaching this z:-1 area.
        // For cards that have a "default" action, invoke it before dismissing.
        MouseArea { id: toastMA; anchors.fill: parent; hoverEnabled: true; z: -1
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onClicked: function(e) {
                if (toast.notif.isPrompt) return
                if (e.button === Qt.LeftButton) {
                    const hasDefault = (toast.notif.actions || []).some(function(a) { return a.key === "default" })
                    if (hasDefault) root.invokeAction(toast.notif, "default")
                    root.dismissNotification(toast.notif.id)
                } else {
                    root.dismissNotification(toast.notif.id)
                }
            }
        }

        // ── Two-finger touchpad swipe-to-dismiss on toast ────────────────
        // Mirrors the HistoryCard gesture: horizontal pixelDelta drives x-offset;
        // release beyond 35 % threshold dismisses, otherwise snaps back.
        property real _swipeX:    0
        property bool _dismissing: false
        property bool _swipeLock:  false

        x: _swipeX
        Behavior on _swipeX {
            enabled: !toast._swipeLock
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        function _commitDismiss() {
            if (toast._dismissing) return
            toast._dismissing = true
            toast._swipeX = (toast._swipeX >= 0 ? 1 : -1) * (toast.width + 40)
            Qt.callLater(function() { root.dismissNotification(toast.notif.id) })
        }

        function _endSwipe() {
            toast._swipeLock = false
            if (toast._dismissing) return
            if (Math.abs(toast._swipeX) >= toast.width * 0.35)
                toast._commitDismiss()
            else
                toast._swipeX = 0
        }

        Timer {
            id: toastSwipeIdle; interval: 200; repeat: false
            onTriggered: toast._endSwipe()
        }

        WheelHandler {
            onWheel: function(ev) {
                if (toast.notif.isPrompt) { ev.accepted = false; return }
                const px = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : -(ev.angleDelta.x / 8.0)
                const py = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : -(ev.angleDelta.y / 8.0)
                const hm = Math.abs(px), vm = Math.abs(py)
                if (hm < 2 || vm > hm * 0.8) { ev.accepted = false; return }
                ev.accepted      = true
                toast._swipeLock = true
                toast._swipeX    = Math.max(-toast.width * 1.3,
                                   Math.min( toast.width * 1.3, toast._swipeX + px))
                toastSwipeIdle.restart()
                if (Math.abs(toast._swipeX) >= toast.width * 0.70) toast._commitDismiss()
            }
        }

        // TouchScreen: two-finger drag
        DragHandler {
            acceptedDevices: PointerDevice.TouchScreen
            minimumPointCount: 2; maximumPointCount: 2
            xAxis.enabled: true; yAxis.enabled: false
            xAxis.minimum: -toast.width * 1.3; xAxis.maximum: toast.width * 1.3
            onTranslationChanged: {
                if (toast.notif.isPrompt || toast._dismissing) return
                toast._swipeLock = true
                toast._swipeX = translation.x
                if (Math.abs(toast._swipeX) >= toast.width * 0.70) toast._commitDismiss()
            }
            onActiveChanged: { if (!active) toast._endSwipe() }
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  HISTORY CARD COMPONENT
    //  Compact, collapsible. Shows icon glyph, group count badge,
    //  expand toggle reveals full body + action buttons.
    // ═════════════════════════════════════════════════════════════════════
    component HistoryCard: Rectangle {
        id: hcard
        required property var notif
        // Passed from delegate so this component can freeze/restore the parent
        // Flickable during a swipe gesture. Required because pragma ComponentBehavior:
        // Bound prevents direct ID references to items outside the component.
        required property var flickable
        property bool _exp: false

        // ── Two-finger side-swipe to dismiss ─────────────────────────────
        property real _swipeX: 0          // accumulated / animated horizontal offset
        property bool _dismissing: false   // latched once threshold crossed
        property bool _swipeLock: false    // true while gesture is in flight

        x: _swipeX
        opacity: 1.0 - Math.min(Math.abs(_swipeX) / 160, 0.55)

        Behavior on _swipeX {
            enabled: !hcard._swipeLock
            NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
        }

        function _commitDismiss() {
            if (hcard._dismissing) return
            hcard._dismissing = true
            const dir = hcard._swipeX >= 0 ? 1 : -1
            hcard._swipeX = dir * (hcard.width + 40)
            Qt.callLater(function() {
                root.history = root.history.filter(
                    function(n) { return n.id !== hcard.notif.id })
            })
        }

        function _endGesture() {
            hcard._swipeLock = false
            hcard.flickable.interactive = true
            if (hcard._dismissing) return
            if (Math.abs(hcard._swipeX) >= hcard.width * 0.35)
                hcard._commitDismiss()
            else
                hcard._swipeX = 0
        }

        // Idle timer: gesture ended when no events arrive for 200 ms
        Timer {
            id: swipeIdleTimer; interval: 200; repeat: false
            onTriggered: hcard._endGesture()
        }

        // ── TouchPad: horizontal wheel events → swipe-to-dismiss ────────────
        // Bare WheelHandler (no acceptedDevices/acceptedModifiers filters) —
        // matching the pattern used by the wallpaper picker which works correctly.
        // On Wayland/libinput touchpad scroll arrives as PointerDevice.Mouse and
        // may carry modifier flags, so any filter silently drops all events.
        WheelHandler {
            onWheel: function(ev) {
                const px = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : -(ev.angleDelta.x / 8.0)
                const py = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : -(ev.angleDelta.y / 8.0)
                const hm = Math.abs(px), vm = Math.abs(py)
                // Pass vertical-dominant events through so Flickable still scrolls
                if (hm < 2 || vm > hm * 0.8) { ev.accepted = false; return }
                ev.accepted = true
                hcard.flickable.interactive = false
                hcard._swipeLock = true
                hcard._swipeX = Math.max(-hcard.width * 1.3,
                                Math.min( hcard.width * 1.3, hcard._swipeX + px))
                swipeIdleTimer.restart()
                if (Math.abs(hcard._swipeX) >= hcard.width * 0.70) hcard._commitDismiss()
            }
        }

        // ── TouchScreen: two-finger drag ─────────────────────────────────────
        DragHandler {
            id: hcTouchDrag
            acceptedDevices: PointerDevice.TouchScreen
            minimumPointCount: 2; maximumPointCount: 2
            xAxis.enabled: true; yAxis.enabled: false
            xAxis.minimum: -hcard.width * 1.3; xAxis.maximum: hcard.width * 1.3
            onTranslationChanged: {
                if (hcard._dismissing) return
                hcard._swipeLock = true
                hcard._swipeX = translation.x
                if (Math.abs(hcard._swipeX) >= hcard.width * 0.70)
                    hcard._commitDismiss()
            }
            onActiveChanged: { if (!active) hcard._endGesture() }
        }

        radius: 12
        // clip:false — the Flickable's clip:true is the only viewport boundary.
        height: hcBody.implicitHeight + 16
        // Tell the parent ColumnLayout about our explicit height so implicitHeight
        // propagates correctly when we expand/collapse.
        Layout.preferredHeight: height
        color: hcMA.containsMouse
            ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.7)
            : Qt.rgba(root.cSurfMid.r, root.cSurfMid.g, root.cSurfMid.b, 0.5)
        border.width: 1
        border.color: hcard.notif.urgency >= 2
            ? Qt.rgba(root.cErr.r, root.cErr.g, root.cErr.b, 0.35)
            : Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.25)
        Behavior on color { ColorAnimation { duration: 100 } }
        Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        ColumnLayout {
            id: hcBody
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 10 }
            spacing: 4

            // ── Summary row ───────────────────────────────────────────────
            RowLayout { Layout.fillWidth: true; spacing: 8

                // Urgency dot
                Rectangle { width: 6; height: 6; radius: 3
                    anchors.verticalCenter: parent.verticalCenter
                    color: hcard.notif.urgency >= 2 ? root.cErr
                        : hcard.notif.category === "bt" ? root.cPrimary
                        : Qt.rgba(root.cOnSurfVar.r, root.cOnSurfVar.g, root.cOnSurfVar.b, 0.5)
                }

                // App icon (image if available, else glyph)
                // Skip for file-path icons (screenshots/recordings) — the full
                // thumbnail renders in the expanded section instead.
                Item { width: 20; height: 20
                    Image {
                        id: hcIcImg
                        anchors.fill: parent; anchors.margins: 1
                        source: {
                            const ic = hcard.notif.icon || ""
                            if (ic.startsWith("/") || ic.startsWith("file://")) return ""
                            return hcard.notif.iconPath ? "file://" + hcard.notif.iconPath : ""
                        }
                        fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent; visible: !hcIcImg.visible
                        text: root.iconGlyph(hcard.notif)
                        font.pixelSize: 12; font.family: "Symbols Nerd Font Mono"
                        color: hcard.notif.urgency >= 2 ? root.cErr : root.cOnSurfVar
                    }
                }

                // Text
                ColumnLayout { Layout.fillWidth: true; spacing: 0
                    RowLayout {
                        Text { Layout.fillWidth: true
                            text: hcard.notif.summary || hcard.notif.appName || "Notification"
                            color: root.cOnSurf; font.pixelSize: 11; font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        // Group count badge
                        Rectangle {
                            visible: (hcard.notif.count || 1) > 1
                            height: 16; implicitWidth: cntT.implicitWidth + 10; radius: 8
                            color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.25)
                            border.width: 1; border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.4)
                            Text { id: cntT; anchors.centerIn: parent
                                text: "×" + (hcard.notif.count || 1)
                                font.pixelSize: 9; color: root.cPrimary
                            }
                        }
                    }
                    Text {
                        visible: hcard.notif.appName !== "" && hcard.notif.summary !== ""
                        text: hcard.notif.appName
                        color: root.cOnSurfVar; font.pixelSize: 9; opacity: 0.7
                    }
                }

                // Timestamp
                Text {
                    text: {
                        const d = new Date(hcard.notif.timestamp), now = new Date()
                        const dm = Math.floor((now - d) / 60000)
                        if (dm < 1)  return "now"
                        if (dm < 60) return dm + "m"
                        const dh = Math.floor(dm / 60)
                        if (dh < 24) return dh + "h"
                        return d.toLocaleDateString(undefined, { month: "short", day: "numeric" })
                    }
                    color: root.cOnSurfVar; font.pixelSize: 9; opacity: 0.65
                    anchors.verticalCenter: parent.verticalCenter
                }

                // Expand/collapse toggle — only when there's something to show
                Text {
                    visible: (hcard.notif.body || "") !== "" || ((hcard.notif.actions || []).length > 0)
                    // nf-md-chevron-down / up
                    text: hcard._exp ? "󰅃" : "󰅀"
                    font.pixelSize: 10; font.family: "Symbols Nerd Font Mono"
                    color: root.cOnSurfVar; opacity: 0.8
                    anchors.verticalCenter: parent.verticalCenter
                    MouseArea { anchors.fill: parent; anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: hcard._exp = !hcard._exp
                    }
                }

                // Dismiss
                Rectangle { width: 18; height: 18; radius: 5
                    color: hcDH.containsMouse
                        ? Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.9)
                        : "transparent"
                    Behavior on color { ColorAnimation { duration: 80 } }
                    Text { anchors.centerIn: parent; text: "×"
                        font.pixelSize: 9; color: root.cOnSurfVar; opacity: 0.7 }
                    MouseArea { id: hcDH; anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.history = root.history.filter(function(n) { return n.id !== hcard.notif.id })
                    }
                }
            }

            // ── Expanded body + actions ────────────────────────────────────
            ColumnLayout {
                visible: hcard._exp
                Layout.fillWidth: true; spacing: 6

                // Thumbnail — screenshots, recordings, any file-path icon
                Image {
                    id: hcThumb
                    property bool _isFilePath: (hcard.notif.icon || "").startsWith("/") ||
                                               (hcard.notif.icon || "").startsWith("file://")
                    visible: _isFilePath &&
                             hcard.notif.category !== "media.playing" &&
                             status === Image.Ready
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(implicitHeight, 160)
                    source: hcard.notif.iconPath ? "file://" + hcard.notif.iconPath : ""
                    fillMode: Image.PreserveAspectFit
                    smooth: true; mipmap: true
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true; maskSource: hcThumbMask
                        maskThresholdMin: 0.5; maskSpreadAtMin: 1.0
                    }
                    Rectangle {
                        id: hcThumbMask; anchors.fill: parent
                        radius: 6; color: "white"; opacity: 0; layer.enabled: true
                    }
                }

                Text {
                    visible: (hcard.notif.body || "") !== ""
                    Layout.fillWidth: true
                    text: hcard.notif.body || ""
                    color: root.cOnSurfVar; font.pixelSize: 10
                    wrapMode: Text.WordWrap; leftPadding: 14
                }

                Flow {
                    visible: (hcard.notif.actions || []).length > 0
                    Layout.fillWidth: true; spacing: 5; leftPadding: 14
                    Repeater { model: hcard.notif.actions || []
                        delegate: Rectangle {
                            required property var modelData
                            visible: modelData.key !== "default"
                            height: 22; implicitWidth: haL.implicitWidth + 12; radius: 6
                            color: haH.containsMouse
                                ? Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.22)
                                : Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.7)
                            border.width: 1
                            border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.3)
                            Behavior on color { ColorAnimation { duration: 80 } }
                            Text { id: haL; anchors.centerIn: parent
                                text: modelData.label || modelData.key || ""
                                color: root.cOnSurf; font.pixelSize: 9
                            }
                            MouseArea { id: haH; anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.invokeAction(hcard.notif, modelData.key)
                            }
                        }
                    }
                }
            }
        }

        MouseArea { id: hcMA; anchors.fill: parent; hoverEnabled: true; z: -1; propagateComposedEvents: true }
    }
}
