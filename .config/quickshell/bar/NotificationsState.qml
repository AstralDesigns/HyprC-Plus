pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  NotificationsState — single source for notification daemon, BT agent,
//  data model, DND. Lives in the bar process so popups read directly.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: ns
    visible: false

    // ── Visibility ────────────────────────────────────────────────────────
    property bool historyVisible: false
    property bool dndEnabled: false

    function toggle()        { ns.historyVisible = !ns.historyVisible }
    function toggleHistory() { ns.historyVisible = !ns.historyVisible }
    function open()          { ns.historyVisible = true }
    function close()         { ns.historyVisible = false }
    function dndOn()         { ns.dndEnabled = true  }
    function dndOff()        { ns.dndEnabled = false }
    function dndToggle()     { ns.dndEnabled = !ns.dndEnabled }

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
        if (cat === "bt" || ic === "bluetooth" || ic.includes("bluetooth")) return "󰂯"
        if (ic.includes("wireless") || ic === "network-wireless")           return "󰤨"
        if (ic === "network" || ic.includes("ethernet"))                    return "󰈀"
        if (cat === "media.playing" || ap === "now playing") return "󰝚"
        if (ic.includes("volume") || ic.includes("audio") || ic.includes("sound")) return "󰕾"
        if (ic.includes("battery"))                                         return "󰁹"
        if (ic.includes("screenshot") || ap.includes("screenshot"))        return "󰹑"
        if (ic.includes("record") || ap.includes("record") || ap.includes("obs")) return "󰑋"
        if (ic.includes("mail") || ap.includes("mail") || ap.includes("thunderbird")) return "󰇮"
        if (ic.includes("discord") || ap.includes("discord"))              return "󰙯"
        if (ic.includes("telegram") || ap.includes("telegram"))            return ""
        if (ic.includes("spotify") || ap.includes("spotify"))              return "󰓇"
        if (ic.includes("firefox") || ap.includes("firefox"))              return "󰈹"
        if (ic.includes("chrome") || ic.includes("chromium"))              return ""
        if (ic.includes("update") || ic.includes("package") || ap.includes("pacman")) return "󰏖"
        if (ic.includes("calendar") || ap.includes("calendar"))            return "󰃭"
        if (ic.includes("download"))                                        return "󰇚"
        if (ic.includes("upload"))                                          return "󰇹"
        if (ic.includes("error") || ic.includes("critical") || notif.urgency >= 2) return "󰀦"
        if (ic.includes("warning") || ic.includes("warn"))                 return "󰀪"
        if (ic.includes("info"))                                            return "󰋼"
        if (ic.includes("success") || ic.includes("complete"))             return "󰄬"
        if (ic.includes("clock") || ic.includes("alarm"))                  return "󰥔"
        if (ic.includes("usb") || ap.includes("usb"))                      return "󰙈"
        return "󰂞"
    }

    function groupKey(n) {
        return (n.appName || "") + "|" + (n.summary || "")
    }

    function addNotification(obj) {
        const n = Object.assign({
            id: ns._nextId++, appName: "", summary: "", body: "", icon: "", iconPath: "",
            urgency: 1, timestamp: Date.now(), actions: [], category: "app",
            isPrompt: false, count: 1
        }, obj)
        n.groupKey = ns.groupKey(n)

        // Toast queue — replace same-group non-prompt (bump count)
        // Toast queue — suppress when DnD is active (prompts + critical always show)
        if (!ns.dndEnabled || n.isPrompt || n.urgency >= 2) {
            const q = ns.notifications.slice()
            const ei = q.findIndex(function(x) { return x.groupKey === n.groupKey && !x.isPrompt })
            if (ei >= 0 && !n.isPrompt) {
                n.count = (q[ei].count || 1) + 1
                q.splice(ei, 1)
            }
            q.unshift(n)
            if (q.length > 6) q.pop()
            ns.notifications = q
        }

        // History — group + bump. All non-prompt notifications go here.
        if (!n.isPrompt) {
            const h = ns.history.slice()
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
                    h[hi] = updated
                } else {
                    h.splice(hi, 1)
                    h.unshift(updated)
                }
            } else {
                h.unshift(n)
                if (h.length > 60) h.pop()
            }
            ns.history = h
        }
        return n.id
    }

    // ── Action invocation ─────────────────────────────────────────────────
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
        ns.notifications = ns.notifications.filter(function(n) { return n.id !== id })
    }
    function clearHistory() { ns.history = [] }

    // ═════════════════════════════════════════════════════════════════════
    //  NOTIFICATION DAEMON  (claims org.freedesktop.Notifications)
    // ═════════════════════════════════════════════════════════════════════
    Process { id: notifDaemonProc
        command: ["python3", "-u",
            Quickshell.env("HOME") + "/.config/quickshell/notifications/notify-daemon.py"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (!l.trim()) return
            try { ns._handleNotifEvent(JSON.parse(l)) } catch(e) {}
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
        ns.addNotification({
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
    property bool btReceiving:  false   // mirrors auto_accept mode in bt-agent.py

    function btToggleReceive() {
        const target = !ns.btReceiving
        // Optimistically update — the auto_accept event from bt-agent will
        // confirm this. If the agent isn't ready, we'll resync on agent_ready.
        ns.btReceiving = target
        ns.btAgentSend("set_auto_accept " + (target ? "1" : "0"))
    }

    // ── BT agent startup ────────────────────────────────────────────────────
    // bt-agent.py creates its own FIFO and kills stale instances.
    // We just need a holder process to keep the FIFO open for reading.
    Process { id: btFifoHolderProc
        command: ["bash", "-c",
            "[ -p /tmp/qs_bt_cmd ] || (rm -f /tmp/qs_bt_cmd && mkfifo /tmp/qs_bt_cmd); " +
            "sleep infinity >> /tmp/qs_bt_cmd"]
        Component.onCompleted: running = true
        onExited: btFifoHolderRestartTimer.restart()
    }
    Timer { id: btFifoHolderRestartTimer; interval: 500; repeat: false
        onTriggered: { if (!btFifoHolderProc.running) btFifoHolderProc.running = true }
    }

    Process { id: btAgentProc
        command: ["python3", "-u",
            Quickshell.env("HOME") +
            "/.config/quickshell/notifications/bt-agent.py"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (!l.trim()) return
            try { ns._handleBtAgentEvent(JSON.parse(l)) } catch(e) {}
        }}
        stderr: SplitParser { splitMarker: "\n"; onRead: function(l) {
            if (l.trim()) console.warn("bt-agent:", l)
        }}
        Component.onCompleted: running = true
        onRunningChanged: {
            if (!running) {
                ns.btAgentReady = false
                console.warn("bt-agent exited code=" + exitCode)
                btAgentRestartTimer.restart()
            }
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
            ns.btAgentReady = true
            // Sync the receiving mode with the freshly started agent
            ns.btAgentSend("set_auto_accept " + (ns.btReceiving ? "1" : "0"))
            break
        case "pair_confirm":
            ns.addNotification({ isPrompt: true, promptType: "pair_confirm",
                promptMac: ev.mac, promptName: ev.name || ev.mac, promptPasskey: ev.passkey || "",
                summary: "Bluetooth Pairing Request", body: "Confirm passkey on " + (ev.name || ev.mac),
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "pair_pin":
            ns.addNotification({ isPrompt: true, promptType: "pair_pin",
                promptMac: ev.mac, promptName: ev.name || ev.mac, promptNeedsPasskey: ev.needs_passkey || false,
                summary: "Bluetooth PIN Required", body: "Enter PIN for " + (ev.name || ev.mac),
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "pair_authorize":
            ns.addNotification({ isPrompt: true, promptType: "pair_authorize",
                promptMac: ev.mac, promptName: ev.name || ev.mac,
                summary: "Bluetooth Pair Request", body: (ev.name || ev.mac) + " wants to pair",
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "display_pin":
            ns.addNotification({ summary: "Bluetooth PIN",
                body: "PIN for " + (ev.name || ev.mac) + ": " + ev.pin,
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "pair_cancelled":
            if (ev.mac) ns.notifications = ns.notifications.filter(function(n) {
                return !(n.isPrompt && n.promptMac === ev.mac)
            })
            ns.addNotification({ summary: "Bluetooth", body: "Pairing cancelled",
                icon: "bluetooth", urgency: 1, category: "bt" })
            break
        case "file_request":
            const szMb = ev.size > 0 ? (ev.size / 1048576).toFixed(1) + " MB" : ""
            ns.addNotification({ isPrompt: true, promptType: "file_accept",
                promptMac: ev.mac, promptName: ev.name || ev.mac,
                promptTransfer: ev.transfer, promptFilename: ev.filename || "file", promptSize: szMb,
                summary: "Incoming File",
                body: (ev.name || ev.mac) + " \u2192 " + (ev.filename || "file") + (szMb ? " (" + szMb + ")" : ""),
                icon: "bluetooth", urgency: 2, category: "bt" })
            break
        case "file_cancelled":
            ns.addNotification({ summary: "Bluetooth", body: "File transfer cancelled",
                icon: "bluetooth", urgency: 1, category: "bt" })
            break
        case "file_auto_accepted":
            // This event is now deprecated — use file_receiving instead
            break
        case "file_receiving":
            // A file transfer has started (either auto-accepted or manually accepted)
            // The actual file will be moved by the OBEX session monitor → file_saved event
            ns.addNotification({ summary: "Receiving file…",
                body: (ev.name || ev.mac) + " → " + (ev.filename || "file") +
                      (ev.size ? " (" + ev.size + ")" : ""),
                icon: "bluetooth", urgency: 1, category: "bt" })
            break
        case "file_saved":
            // OBEX session monitor completed the file move to ~/Downloads
            ns.addNotification({ summary: "File received",
                body: (ev.name || ev.mac) + " → " + (ev.filename || "file") +
                      (ev.size ? " (" + ev.size + ")" : "") + " saved to Downloads",
                icon: "bluetooth", urgency: 1, category: "bt" })
            break
        case "auto_accept":
            // bt-agent confirmed the mode change — keep our flag in sync
            ns.btReceiving = ev.enabled === true
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
            const rem = ns.notifications.filter(function(n) {
                if (n.isPrompt || n.urgency >= 2) return true
                if (n.category === "media.playing") return (now - n.timestamp) < 5000
                return (now - n.timestamp) < 5000
            })
            if (rem.length !== ns.notifications.length) ns.notifications = rem
        }
    }

    // ═════════════════════════════════════════════════════════════════════
    //  WAYBAR STATE (write state file for the Notifications module)
    // ═════════════════════════════════════════════════════════════════════
    property bool inhibitorActive: false
    FileView {
        path: Quickshell.env("HOME") + "/.cache/waybar-idle-inhibitor.state"
        watchChanges: true; onFileChanged: reload()
        onLoaded: ns.inhibitorActive = text().trim() === "active"
    }

    function _waybarIconKey() {
        const has  = ns.history.length > 0
        const dnd  = ns.dndEnabled
        const inh  = ns.inhibitorActive
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
        const key    = ns._waybarIconKey()
        const icon   = ns._waybarIconGlyph(key)
        const count  = ns.history.length
        const tip    = ns.dndEnabled ? "Do Not Disturb ON" : "Notifications"
        const cls    = ns.dndEnabled ? "dnd" : (count > 0 ? "unread" : "")
        const json   = JSON.stringify({ text: icon, tooltip: tip, class: cls, alt: key, count: count })
        waybarStateProc._json = json
        if (!waybarStateProc.running) waybarStateProc.running = true
    }
    Process { id: waybarStateProc; property string _json: "{}"
        command: ["bash", "-c",
            "D=~/.cache/quickshell/notifications; mkdir -p \"$D\"; " +
            "printf '%s' \"$QS_NOTIF_STATE\" > \"$D/waybar-state.json\""
        ]
        environment: ({ "QS_NOTIF_STATE": waybarStateProc._json })
    }
    onDndEnabledChanged:      Qt.callLater(ns._emitWaybarState)
    onInhibitorActiveChanged: Qt.callLater(ns._emitWaybarState)
    onHistoryChanged:         Qt.callLater(ns._emitWaybarState)
}
