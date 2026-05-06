pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

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

    // ── Smart redirect launcher ───────────────────────────────────────────
    // Opens a path in Nautilus, navigating to the containing folder and
    // selecting the file. Used for screenshot/recording save notifications.
    // ── Smart redirect ────────────────────────────────────────────────────
    // Opens a path in Nautilus with the file selected (screenshot/recording).
    Process { id: nautilusSelectProc; property string _path: ""
        command: ["nautilus", "--select", nautilusSelectProc._path]
        onRunningChanged: {
            if (!running && nautilusSelectProc._pending !== "") {
                nautilusSelectProc._path = nautilusSelectProc._pending
                nautilusSelectProc._pending = ""
                Qt.callLater(function() { nautilusSelectProc.running = true })
            }
        }
        property string _pending: ""
    }
    function _launchNautilus(path) {
        if (nautilusSelectProc.running) {
            nautilusSelectProc._pending = path
        } else {
            nautilusSelectProc._path = path
            nautilusSelectProc.running = true
        }
    }

    // Bash fallback launcher for apps not reachable via DesktopEntries.execute()
    Process { id: _notifLaunchProc; property string _cmd: ""
        command: ["bash", "-c", _notifLaunchProc._cmd] }
    Timer { id: _notifLaunchTimer; interval: 0; repeat: false
        onTriggered: {
            if (_notifLaunchProc._cmd !== "") {
                _notifLaunchProc.running = false
                _notifLaunchProc.running = true
            }
        }
    }

    // ── Notif app state writer — mirrors DesktopLayer/_writeProc pattern ──
    // Bare Process; command is assigned dynamically in _writeNotifAppState().
    Process { id: _notifWriteProc; running: false }


    // ── Saved file path extractor ─────────────────────────────────────────
    function _savedFilePath(notif) {
        const body = notif.body || ""
        const m = body.match(/(\/[^\s"'<>]+\.(png|jpg|jpeg|webp|mp4|mkv|webm|gif))/i)
        if (m) return m[1]
        const ip = notif.iconPath || ""
        if (ip && (ip.includes("Screenshots") || ip.includes("Recordings") ||
                   ip.includes("Pictures")    || ip.includes("Videos"))) return ip
        return ""
    }

    // ── Primary redirect entry point ──────────────────────────────────────
    // 1. Screenshot/recording path → Nautilus select
    // 2. Screenshot/recording app  → open save folder
    // 3. Look up NotifAppState for stored desktopId + url:
    //    a. Try Hyprland.windows scan by address, then by class/desktopId
    //    b. If running → focuswindow (+ togglespecialworkspace if needed)
    //    c. If not running → DesktopEntries.byId(desktopId).execute() or bash
    //    d. If URL present → also/instead xdg-open the URL
    function redirectNotification(notif) {
        const ic = (notif.icon    || "").toLowerCase()
        const ap = (notif.appName || "").toLowerCase()

        // 1. Screenshot/recording with embedded file path → Nautilus select
        const fp = ns._savedFilePath(notif)
        if (fp) {
            ns._launchNautilus(fp)
            return
        }

        // 2. Screenshot/recording by app identity → open save folder
        const isScreenshot = ic.includes("screenshot") || ap.includes("screenshot") ||
                             ap.includes("flameshot")  || ap.includes("spectacle")  ||
                             ap.includes("grimblast")  || ap.includes("grim")
        const isRecording  = ic.includes("record") || ap.includes("record") ||
                             ap.includes("obs")    || ap.includes("wf-recorder") ||
                             ap.includes("kooha")
        if (isScreenshot) {
            ns._launchNautilus(Quickshell.env("HOME") + "/Pictures/Screenshots")
            return
        }
        if (isRecording) {
            ns._launchNautilus(Quickshell.env("HOME") + "/Videos/Recordings")
            return
        }

        // 3. Resolve via NotifAppState
        // For media notifications the cls key is the icon name, not the appName
        const genericNames2 = ["now playing", "media player", "music", "audio"]
        const isGenericAp = genericNames2.includes(ap.trim())
        const lookupKey = isGenericAp ? ic : ap
        const stored    = NotifAppState.lookup(lookupKey) || NotifAppState.lookup(ap) || {}
        const desktopId = stored.desktopId || ""
        const storedUrl = stored.url || ""
        const bodyUrl   = (notif.body || "").match(/https?:\/\/[^\s"'<>]+/)
        const url       = bodyUrl ? bodyUrl[0] : storedUrl

        // 3a. Try to find a running Hyprland window
        let client = null
        if (Hyprland.windows) {
            const vals = Hyprland.windows.values
            const normAp = ap.split(".").pop()
            const normId = desktopId.replace(/\.desktop$/, "").toLowerCase()
            for (let i = 0; i < vals.length; i++) {
                const w = vals[i]
                if (!w) continue
                const wc = (w.class        || "").toLowerCase()
                const wi = (w.initialClass || "").toLowerCase()
                const wt = (w.title        || "").toLowerCase()
                if (wc.includes(normAp) || wi.includes(normAp) ||
                    (normId && (wc.includes(normId) || wi.includes(normId)))) {
                    client = w
                    break
                }
            }
        }

        if (client) {
            // 3b. Focus running window
            const wsName = (client.workspace?.name || "")
            if (wsName.startsWith("special:")) {
                Hyprland.dispatch("togglespecialworkspace " + wsName.replace(/^special:/, ""))
            }
            Hyprland.dispatch("focuswindow address:" + client.address)
            // Open URL in the already-running instance via xdg-open (reuses existing process)
            if (url) {
                urlOpenerProc._url = url
                Qt.callLater(function() { if (!urlOpenerProc.running) urlOpenerProc.running = true })
            }
            return
        }

        // 3c. Not running — launch via DesktopEntries or bash
        if (url && !desktopId) {
            // Pure URL with no known app → xdg-open (lets the default handler decide)
            urlOpenerProc._url = url
            if (!urlOpenerProc.running) urlOpenerProc.running = true
            return
        }
        if (desktopId) {
            const entry = DesktopEntries.byId(desktopId)
            if (entry) {
                // Always pass URL to the entry so the browser opens the right tab,
                // not a new window on its default page.
                if (url) {
                    const clean = (entry.execString || "").replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
                    _notifLaunchProc._cmd = clean + " " + JSON.stringify(url) + " &"
                    _notifLaunchTimer.restart()
                } else {
                    entry.execute()
                }
                return
            }
        }
        // 3d. Fallback — try the resolved entry via NotifAppState directly
        const fallbackEntry = NotifAppState._findEntry(notif.appName || notif.icon || "")
        if (fallbackEntry) {
            if (url) {
                const clean = (fallbackEntry.execString || "").replace(/%[UuFfIiDdNnVvKk]/g, "").trim()
                _notifLaunchProc._cmd = clean + " " + JSON.stringify(url) + " &"
                _notifLaunchTimer.restart()
            } else {
                fallbackEntry.execute()
            }
            return
        }
        if (url) {
            urlOpenerProc._url = url
            if (!urlOpenerProc.running) urlOpenerProc.running = true
        }
    }

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

    // In-memory map — mirrors what's on disk, avoids re-reading the file
    property var _notifAppMap: ({})

    function _writeNotifAppState(appName, iconName, summary, body) {
        if (!appName) return

        // Screenshot and recorder notifications are handled via Nautilus directly;
        // never persist them to the state file.
        const apLow = appName.toLowerCase()
        const icLow = (iconName || "").toLowerCase()
        const _skipCls = ["screenshot", "recorder", "grimblast", "grim",
                          "flameshot", "spectacle", "wf-recorder", "kooha",
                          "obs", "obs-studio"]
        for (const sc of _skipCls) {
            if (apLow.includes(sc) || icLow.includes(sc)) return
        }

        // For generic app names like "now playing", "media player" etc.
        // the icon name is the real identifier (e.g. "spotify").
        const genericNames = ["now playing", "media player", "music", "audio"]
        const isGeneric = genericNames.includes(apLow.trim())

        // cls is the lookup key — use icon/resolved name for generic media,
        // but store the *real* resolved appName so redirects find the right app.
        const cls = isGeneric
            ? (iconName || appName).toLowerCase()
            : apLow

        // Resolve desktop entry — try most-specific first
        let entry = null
        const candidates = isGeneric
            ? [iconName, summary, appName]
            : [appName, iconName, summary]
        for (const c of candidates) {
            if (!c) continue
            entry = NotifAppState._findEntry(c)
            if (entry) break
        }

        const desktopId = entry ? (entry.id || "") : ""
        const urlMatch  = body ? body.match(/https?:\/\/[^\s"'<>]+/) : null
        const url       = urlMatch ? urlMatch[0] : ""

        const existing = ns._notifAppMap[cls]

        // Always write on first encounter; skip only on exact repeat
        if (existing &&
            existing.desktopId === desktopId &&
            existing.url === url) return

        // Store the real app name so media redirects resolve properly
        const realName = (entry && entry.name) ? entry.name : (isGeneric ? (iconName || appName) : appName)
        ns._notifAppMap[cls] = { cls, desktopId, url, realName }

        // Build arg list for notif-app-write.sh (one JSON line per entry)
        const lines = Object.values(ns._notifAppMap)
            .filter(e => e && e.cls)
            .map(e => JSON.stringify(e))

        const scriptPath = Config.barDir + "/scripts/notif-app-write.sh"
        _notifWriteProc.command = [scriptPath, ...lines]
        _notifWriteProc.running = false
        _notifWriteProc.running = true
    }

    function _handleNotifEvent(ev) {
        if (ev.type !== "notify") return
        const urgMap = { "low": 0, "normal": 1, "critical": 2 }
        const appName = ev.app_name || ""
        const body    = ev.body     || ""
        const icon    = ev.icon     || ""

        // For media/generic app names, resolve the real source name so it
        // shows in the card subline instead of "now playing".
        const genericNames = ["now playing", "media player", "music", "audio"]
        const isGeneric = genericNames.includes(appName.toLowerCase().trim())
        let resolvedAppName = appName
        if (isGeneric && icon) {
            const stored = NotifAppState.lookup(icon.toLowerCase())
            if (stored && stored.realName) resolvedAppName = stored.realName
            else {
                const entry = NotifAppState._findEntry(icon)
                if (entry && entry.name) resolvedAppName = entry.name
            }
        }

        ns.addNotification({
            appName:  resolvedAppName,
            summary:  ev.summary   || "",
            body:     body,
            icon:     icon,
            iconPath: ev.icon_path || "",
            urgency:  urgMap[ev.urgency] !== undefined ? urgMap[ev.urgency] : 1,
            actions:  ev.actions   || [],
            category: ev.category  || "app",
            _daemonId: ev.id
        })
        // Resolve desktop entry and write to ~/.config/notif-running-apps
        ns._writeNotifAppState(appName, icon, ev.summary || "", body)
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
