pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Notifications toasts + history inside WlSessionLockSurface (frosted wallpaper blur).
Item {
    id: overlay

    property color cSourceColor
    property color cPrimary
    property color cOnPrimary
    property color cPrimaryContainer
    property color cOnSurf
    property color cOnSurfVar
    property color cBg
    property color cInvPrimary
    property color cSurfHi
    property color cOutVar
    property color cErr
    property color cPrimFixedDim
    property color cSecondary
    property color cSecondaryContainer
    property color cOnSecondary
    property color cTertiary
    property color cSecondaryFixedDim
    property color cTertiaryFixedDim
    property string wallpaperPath: ""

    property color cWc0
    property color cWc1
    property color cWc2
    property color cWc3
    property color cWc4
    property color cWc5
    property color cWc6
    property color cWc7
    property color cWc8
    property color cWc9
    property color cWc10
    property color cWc11
    property color cWc12
    property color cWc13
    property color cWc14
    property color cWc15

    readonly property string _fontFamily: "Symbols Nerd Font Mono"

    property bool historyVisible: false
    property bool dndEnabled: false

    property var notifications: []
    property var history: []
    property int _nextId: 1

    z: 15

    function toggleHistory() { overlay.historyVisible = !overlay.historyVisible }
    function toggleDnd()     { overlay.dndEnabled = !overlay.dndEnabled }
    function dismissNotification(id) {
        overlay.notifications = overlay.notifications.filter(function(n) { return n.id !== id })
    }
    function removeHistory(id) {
        overlay.history = overlay.history.filter(function(n) { return n.id !== id })
    }
    function clearHistory() { overlay.history = [] }

    function _groupKey(n) { return (n.appName || "") + "|" + (n.summary || "") }

    Process {
        id: actionInvokerProc
        property int _nid: 0
        property string _key: ""
        command: ["python3", "-u",
            Quickshell.env("HOME") + "/.config/quickshell/notifications/invoke-action.py",
            String(_nid), _key]
    }
    function invokeAction(notif, key) {
        if (!notif || !notif._daemonId) return
        actionInvokerProc._nid = notif._daemonId
        actionInvokerProc._key = key
        if (!actionInvokerProc.running) actionInvokerProc.running = true
    }

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
        if (ic.includes("telegram") || ap.includes("telegram"))            return "󰀪"
        if (ic.includes("spotify") || ap.includes("spotify"))              return "󰓇"
        if (ic.includes("firefox") || ap.includes("firefox"))              return "󰈹"
        if (ic.includes("chrome") || ic.includes("chromium"))              return "󰊯"
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

    function formatRelTime(ts) {
        const d = new Date(ts)
        const now = new Date()
        const dm = Math.floor((now - d) / 60000)
        if (dm < 1) return "now"
        if (dm < 60) return dm + "m"
        const dh = Math.floor(dm / 60)
        if (dh < 24) return dh + "h"
        return d.toLocaleDateString(undefined, { month: "short", day: "numeric" })
    }

    function addNotification(obj) {
        const n = Object.assign({
            id: overlay._nextId++, appName: "", summary: "", body: "", icon: "",
            iconPath: "", urgency: 1, timestamp: Date.now(), actions: [], category: "app",
            isPrompt: false, count: 1
        }, obj)
        n.groupKey = overlay._groupKey(n)

        if (!overlay.dndEnabled || n.isPrompt || n.urgency >= 2) {
            const q = overlay.notifications.slice()
            const ei = q.findIndex(function(x) { return x.groupKey === n.groupKey && !x.isPrompt })
            if (ei >= 0 && !n.isPrompt) {
                n.count = (q[ei].count || 1) + 1
                q.splice(ei, 1)
            }
            q.unshift(n)
            if (q.length > 6) q.pop()
            overlay.notifications = q
        }

        if (!n.isPrompt) {
            const h = overlay.history.slice()
            const isMedia = n.category === "media.playing"
            const hi = isMedia
                ? h.findIndex(function(x) { return x.category === "media.playing" })
                : h.findIndex(function(x) { return x.groupKey === n.groupKey })
            if (hi >= 0) {
                const updated = Object.assign({}, h[hi], {
                    appName:      isMedia ? n.appName : h[hi].appName,
                    desktopEntry: isMedia ? n.desktopEntry : h[hi].desktopEntry,
                    source_url:   isMedia ? n.source_url : h[hi].source_url,
                    summary:      n.summary,
                    body:         n.body,
                    iconPath:     n.iconPath || h[hi].iconPath,
                    icon:         n.icon,
                    timestamp:    n.timestamp,
                    count:        isMedia ? (h[hi].count || 1) : (h[hi].count || 1) + 1
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
            overlay.history = h
        }
    }

    function _handleEvent(ev) {
        if (!ev || ev.type !== "notify") return
        const urgMap = { "low": 0, "normal": 1, "critical": 2 }
        overlay.addNotification({
            appName:      ev.app_name || "",
            desktopEntry: ev.desktop_entry || "",
            summary:      ev.summary || "",
            body:         ev.body || "",
            icon:         ev.icon || "",
            iconPath:     ev.icon_path || "",
            urgency:      urgMap[ev.urgency] !== undefined ? urgMap[ev.urgency] : 1,
            actions:      ev.actions || [],
            category:     ev.category || "app",
            _daemonId:    ev.id,
            _sourceUrl:   ev.source_url || ""
        })
    }

    Process {
        id: notifHandoffProc
        command: ["bash", "-c",
            "touch /tmp/candylock-notif.lock 2>/dev/null; " +
            "pkill -f notify-daemon.py 2>/dev/null; sleep 0.3"]
        running: false
        onExited: { if (!notifDaemonProc.running) notifDaemonProc.running = true }
    }

    Process {
        id: notifDaemonProc
        command: ["python3", "-u",
            Quickshell.env("HOME") + "/.config/quickshell/notifications/notify-daemon.py"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                if (!l.trim()) return
                try { overlay._handleEvent(JSON.parse(l)) } catch (e) {}
            }
        }
        Component.onCompleted: notifHandoffProc.running = true
        onRunningChanged: if (!running) notifDaemonRestart.restart()
    }
    Timer {
        id: notifDaemonRestart
        interval: 3000; repeat: false
        onTriggered: { if (!notifDaemonProc.running) notifDaemonProc.running = true }
    }

    Timer {
        id: autoDismissTimer
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            const now = Date.now()
            const rem = overlay.notifications.filter(function(n) {
                if (n.isPrompt || n.urgency >= 2) return true
                return (now - n.timestamp) < 5000
            })
            if (rem.length !== overlay.notifications.length)
                overlay.notifications = rem
        }
    }

    // ── Frosted card (lockscreen wallpaper blur — same technique as center panel) ──
    component LockFrosted: Item {
        id: frosted
        required property Item blurRoot
        property string wp: overlay.wallpaperPath
        property int cornerRadius: 14
        property color borderCol: Qt.rgba(overlay.cOutVar.r, overlay.cOutVar.g,
                                          overlay.cOutVar.b, 0.38)
        property bool showUrgencyBar: false
        property color urgencyCol: overlay.cPrimary
        property bool showTimeoutProgress: false
        property real progressTimestamp: 0
        property int hPad: 10
        property int vPad: 10

        default property alias content: contentLay.data

        readonly property int _leftPad: hPad + (showUrgencyBar ? 4 : 0)
        implicitHeight: contentLay.implicitHeight + vPad * 2
        height: implicitHeight

        Rectangle {
            id: roundMask
            anchors.fill: parent
            radius: frosted.cornerRadius
            color: "white"
            opacity: 0
            layer.enabled: true
        }

        Item {
            anchors.fill: parent
            layer.enabled: frosted.wp !== ""
            layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
            AnimatedImage {
                property point _origin: frosted.mapToItem(frosted.blurRoot, 0, 0)
                x: -_origin.x
                y: -_origin.y
                width: frosted.blurRoot.width
                height: frosted.blurRoot.height
                source: frosted.wp ? "file://" + frosted.wp : ""
                fillMode: Image.PreserveAspectCrop
                smooth: true; playing: true; cache: true
                visible: frosted.wp !== ""
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: frosted.cornerRadius
            color: Qt.rgba(overlay.cInvPrimary.r, overlay.cInvPrimary.g,
                           overlay.cInvPrimary.b, 0.65)
            border.width: 1
            border.color: frosted.borderCol
        }

        Rectangle {
            visible: frosted.showUrgencyBar
            x: 0; y: 0; width: 5; height: parent.height
            radius: 3
            color: frosted.urgencyCol
        }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: roundMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }

        ColumnLayout {
            id: contentLay
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: vPad
            anchors.leftMargin: _leftPad
            anchors.rightMargin: hPad
            anchors.bottomMargin: vPad
        }

        Item {
            id: timeoutProg
            visible: frosted.showTimeoutProgress
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 3
            z: 10
            clip: true
            property real _age: 0
            onVisibleChanged: if (visible) _age = 0
            Connections {
                target: frosted
                function onProgressTimestampChanged() { timeoutProg._age = 0 }
            }
            Timer {
                interval: 250
                repeat: true
                running: timeoutProg.visible
                onTriggered: timeoutProg._age = Math.min(1, (Date.now() - frosted.progressTimestamp) / 5000)
            }
            Rectangle {
                anchors.fill: parent
                radius: frosted.cornerRadius
                color: Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.22)
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: parent.width * Math.max(0, 1 - timeoutProg._age)
                    color: overlay.cPrimary
                    radius: parent.radius
                    Behavior on width {
                        NumberAnimation { duration: 260; easing.type: Easing.Linear }
                    }
                }
            }
        }
    }

    // ── Toasts (top-left, below toggle) ─────────────────────────────────────
    Item {
        id: toastHost
        property bool _shouldShow: overlay.notifications.length > 0 && !overlay.historyVisible
        visible: opacity > 0.001
        opacity: _shouldShow ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 84
        anchors.leftMargin: 24
        width: 364
        implicitHeight: toastCol.implicitHeight

        Column {
            id: toastCol
            width: parent.width
            spacing: 6
            Repeater {
                model: overlay.notifications
                delegate: Item {
                    id: toastItem
                    required property var modelData
                    readonly property var notif: modelData
                    width: toastCol.width
                    property bool _dismissing: false
                    property real _slideIn: -40
                    property real _p: 0
                    property real _swipeX: 0
                    property bool _swipeLock: false

                    height: _dismissing ? 0 : toastCard.implicitHeight
                    clip: true
                    Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    opacity: (_dismissing ? 0 : _p) * (1.0 - Math.min(Math.abs(_swipeX)/160, 0.55))
                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    transform: Translate { x: _slideIn + _swipeX }
                    NumberAnimation on _slideIn { from: -40; to: 0; duration: 220; easing.type: Easing.OutCubic; running: true }
                    NumberAnimation on _p { from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic; running: true }
                    Behavior on _swipeX { enabled: !toastItem._swipeLock; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                    Timer {
                        id: toastDismissTimer
                        interval: 180
                        repeat: false
                        onTriggered: overlay.dismissNotification(notif.id)
                    }

                    function _commitDismiss() {
                        if (_dismissing) return
                        _dismissing = true
                        const dir = _swipeX >= 0 ? 1 : -1
                        _swipeX = dir * (width + 40)
                        toastDismissTimer.restart()
                    }

                    function _endGesture() {
                        _swipeLock = false
                        if (_dismissing) return
                        if (Math.abs(_swipeX) >= width * 0.35) _commitDismiss()
                        else _swipeX = 0
                    }
                    Timer { id: swipeIdleTimer; interval: 200; repeat: false; onTriggered: toastItem._endGesture() }

                    WheelHandler { onWheel: function(ev){
                        const px = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : -(ev.angleDelta.x / 8.0)
                        const py = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : -(ev.angleDelta.y / 8.0)
                        const hm = Math.abs(px), vm = Math.abs(py)
                        if (hm < 2 || vm > hm * 0.8) { ev.accepted = false; return }
                        ev.accepted = true; _swipeLock = true
                        _swipeX = Math.max(-width * 1.3, Math.min(width * 1.3, _swipeX + px))
                        swipeIdleTimer.restart()
                        if (Math.abs(_swipeX) >= width * 0.70) _commitDismiss()
                    }}

                    LockFrosted {
                        id: toastCard
                        blurRoot: overlay
                        width: toastCol.width
                        cornerRadius: 14
                        showTimeoutProgress: !notif.isPrompt && notif.urgency < 2
                        progressTimestamp: notif.timestamp
                        showUrgencyBar: notif.urgency >= 2
                        urgencyCol: notif.urgency >= 2 ? overlay.cErr : overlay.cPrimary
                        borderCol: notif.urgency >= 2
                            ? Qt.rgba(overlay.cErr.r, overlay.cErr.g, overlay.cErr.b, 0.55)
                            : notif.category === "bt"
                                ? Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.5)
                                : Qt.rgba(overlay.cOutVar.r, overlay.cOutVar.g, overlay.cOutVar.b, 0.38)

                        ColumnLayout {
                            width: toastCol.width - 20 - (notif.urgency >= 2 ? 4 : 0)
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Item {
                                    width: notif.category === "media.playing" ? 48 : 34
                                    height: notif.category === "media.playing" ? 48 : 34
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: notif.category === "media.playing" ? width / 2 : 9
                                        color: notif.urgency >= 2
                                            ? Qt.rgba(overlay.cErr.r, overlay.cErr.g, overlay.cErr.b, 0.18)
                                            : Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.15)
                                    }
                                    Item {
                                        id: toastIcWrap
                                        anchors.fill: parent
                                        anchors.margins: notif.category === "media.playing" ? 0 : 4
                                        visible: toastIcImg.status === Image.Ready
                                        layer.enabled: notif.category === "media.playing"
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: toastArtMask
                                            maskThresholdMin: 0.5
                                            maskSpreadAtMin: 1.0
                                        }
                                        Rectangle {
                                            id: toastArtMask
                                            anchors.fill: parent
                                            radius: width / 2
                                            color: "white"
                                            opacity: 0
                                            layer.enabled: true
                                        }
                                        Image {
                                            id: toastIcImg
                                            anchors.fill: parent
                                            source: notif.iconPath ? "file://" + notif.iconPath : ""
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            mipmap: true
                                            cache: false
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !toastIcWrap.visible
                                        text: overlay.iconGlyph(notif)
                                        font.pixelSize: notif.category === "media.playing" ? 22 : 17
                                        font.family: overlay._fontFamily
                                        color: notif.urgency >= 2 ? overlay.cErr : overlay.cPrimary
                                    }
                                    Rectangle {
                                        visible: (notif.count || 1) > 1
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.rightMargin: -2
                                        anchors.topMargin: -2
                                        width: 16
                                        height: 16
                                        radius: 8
                                        color: overlay.cPrimary
                                        Text {
                                            anchors.centerIn: parent
                                            text: notif.count || 1
                                            font.pixelSize: 9
                                            color: overlay.cOnSurf
                                            font.weight: Font.Bold
                                        }
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    Text {
                                        Layout.fillWidth: true
                                        text: notif.summary || notif.appName || "Notification"
                                        color: overlay.cOnSurf
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: notif.appName !== "" && notif.summary !== ""
                                        text: notif.appName
                                        color: overlay.cOnSurfVar
                                        font.pixelSize: 9
                                        opacity: 0.75
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }
                                }

                                Rectangle {
                                    width: 22
                                    height: 22
                                    radius: 6
                                    color: toastDismissH.containsMouse
                                        ? Qt.rgba(overlay.cOnSecondary.r, overlay.cOnSecondary.g,
                                                  overlay.cOnSecondary.b, 0.9)
                                        : "transparent"
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                    Text {
                                        anchors.centerIn: parent
                                        text: "×"
                                        font.pixelSize: 11
                                        color: overlay.cOnSurfVar
                                    }
                                    MouseArea {
                                        id: toastDismissH
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: toastItem._commitDismiss()
                                    }
                                }
                            }

                            Text {
                                visible: (notif.body || "").length > 0
                                Layout.fillWidth: true
                                text: notif.body
                                color: overlay.cOnSurfVar
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                maximumLineCount: 4
                                leftPadding: notif.category === "media.playing" ? 58 : 44
                            }

                            Flow {
                                visible: (notif.actions || []).length > 0
                                Layout.fillWidth: true
                                spacing: 5
                                leftPadding: notif.category === "media.playing" ? 58 : 44
                                Repeater {
                                    model: notif.actions || []
                                    delegate: Rectangle {
                                        required property var modelData
                                        visible: modelData && modelData.key !== "default"
                                        height: 22
                                        implicitWidth: taL.implicitWidth + 12
                                        radius: 6
                                        color: taH.containsMouse
                                            ? Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.25)
                                            : Qt.rgba(overlay.cOnSecondary.r, overlay.cOnSecondary.g, overlay.cOnSecondary.b, 0.2)
                                        border.width: 1
                                        border.color: Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.35)
                                        Behavior on color { ColorAnimation { duration: 80 } }
                                        Text {
                                            id: taL
                                            anchors.centerIn: parent
                                            text: modelData ? (modelData.label || modelData.key || "") : ""
                                            color: overlay.cWc5
                                            font.pixelSize: 9
                                        }
                                        MouseArea {
                                            id: taH
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: overlay.invokeAction(notif, modelData.key)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ── History panel ───────────────────────────────────────────────────────
    Item {
        id: histHost
        visible: opacity > 0.001
        opacity: overlay.historyVisible ? 1.0 : 0.0
        scale:   overlay.historyVisible ? 1.0 : 0.92
        enabled: overlay.historyVisible
        transformOrigin: Item.TopLeft
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 84
        anchors.leftMargin: 24
        width: 380
        clip: true
        implicitHeight: Math.min(histPanel.implicitHeight, 560)
        z: 2

        MouseArea {
            anchors.fill: parent
            z: -1
            onClicked: overlay.historyVisible = false
        }

        LockFrosted {
            id: histPanel
            width: histHost.width
            blurRoot: overlay
            cornerRadius: 18
            borderCol: Qt.rgba(overlay.cOutVar.r, overlay.cOutVar.g, overlay.cOutVar.b, 0.40)

            ColumnLayout {
                id: histBody
                width: histHost.width - 20
                spacing: 8

                RowLayout {
                    id: histHdr
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        text: overlay.dndEnabled ? "Do Not Disturb" : "Notifications"
                        color: overlay.dndEnabled ? Qt.rgba(overlay.cWc6.r, overlay.cWc6.g, overlay.cWc6.b, 1.0) : overlay.cWc5
                        font.pixelSize: 14
                        font.weight: Font.Medium
                        Layout.fillWidth: true
                    }
                    Rectangle {
                        height: 24; implicitWidth: clrLbl.implicitWidth + 14; radius: 8
                        color: clrH.containsMouse
                            ? Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g,
                            	      overlay.cPrimary.b, 0.4)
                            : Qt.rgba(overlay.cOnSecondary.r, overlay.cOnSecondary.g,
                                      overlay.cOnSecondary.b, 0.2)
                        border.width: 1
                        border.color: Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g,
                                              overlay.cPrimary.b, 0.4)
                        Text {
                            id: clrLbl; anchors.centerIn: parent
                            text: "Clear all"; color: overlay.cOnSurfVar; font.pixelSize: 11
                        }
                        MouseArea {
                            id: clrH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: overlay.clearHistory()
                        }
                    }
                }

                Rectangle {
                    Layout.fillWidth: true; height: 1
                    color: Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.16)
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(histCol.implicitHeight, 420)
                    clip: true
                    contentHeight: histCol.implicitHeight
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: histCol
                        width: parent.width
                        spacing: 6

                        Text {
                            visible: overlay.history.length === 0
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: "No notifications"
                            color: overlay.cOnSurfVar
                            font.pixelSize: 12
                            font.italic: true
                        }

                        Repeater {
                            model: overlay.history
                            delegate: Rectangle {
                                id: histCardItem
                                required property var modelData
                                readonly property var notif: modelData
                                property bool _exp: false
                                property bool _dismissing: false
                                property real _entryP: 0
                                property real _swipeX: 0
                                property bool _swipeLock: false

                                Layout.fillWidth: true
                                clip: true
                                height: _dismissing ? 0 : (histRow.implicitHeight + 16)
                                Layout.preferredHeight: height
                                Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                                opacity: (_dismissing ? 0 : _entryP) * (1.0 - Math.min(Math.abs(_swipeX)/160, 0.55))
                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                NumberAnimation on _entryP { from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic; running: true }

                                x: _swipeX
                                Behavior on _swipeX { enabled: !histCardItem._swipeLock; NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

                                radius: 10
                                color: Qt.rgba(overlay.cOnSecondary.r, overlay.cOnSecondary.g,
                                               overlay.cOnSecondary.b, 0.22)
                                border.width: 1
                                border.color: notif.urgency >= 2
                                    ? Qt.rgba(overlay.cErr.r, overlay.cErr.g, overlay.cErr.b, 0.35)
                                    : Qt.rgba(overlay.cOutVar.r, overlay.cOutVar.g, overlay.cOutVar.b, 0.25)

                                Timer {
                                    id: histDismissTimer
                                    interval: 180
                                    repeat: false
                                    onTriggered: overlay.removeHistory(notif.id)
                                }

                                function _commitDismiss() {
                                    if (_dismissing) return
                                    _dismissing = true
                                    const dir = _swipeX >= 0 ? 1 : -1
                                    _swipeX = dir * (width + 40)
                                    histDismissTimer.restart()
                                }

                                function _endGesture() {
                                    _swipeLock = false
                                    if (_dismissing) return
                                    if (Math.abs(_swipeX) >= width * 0.35) _commitDismiss()
                                    else _swipeX = 0
                                }
                                Timer { id: histSwipeIdleTimer; interval: 200; repeat: false; onTriggered: histCardItem._endGesture() }

                                WheelHandler { onWheel: function(ev){
                                    const px = ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : -(ev.angleDelta.x / 8.0)
                                    const py = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : -(ev.angleDelta.y / 8.0)
                                    const hm = Math.abs(px), vm = Math.abs(py)
                                    if (hm < 2 || vm > hm * 0.8) { ev.accepted = false; return }
                                    ev.accepted = true; _swipeLock = true
                                    _swipeX = Math.max(-width * 1.3, Math.min(width * 1.3, _swipeX + px))
                                    histSwipeIdleTimer.restart()
                                    if (Math.abs(_swipeX) >= width * 0.70) _commitDismiss()
                                }}

                                ColumnLayout {
                                    id: histRow
                                    anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            Layout.alignment: Qt.AlignVCenter
                                            color: notif.urgency >= 2 ? overlay.cErr
                                                : notif.category === "bt" ? overlay.cPrimary
                                                : Qt.rgba(overlay.cOnSurfVar.r, overlay.cOnSurfVar.g,
                                                          overlay.cOnSurfVar.b, 0.5)
                                        }

                                        Item {
                                            width: 20; height: 20
                                            Image {
                                                id: hcIcImg
                                                anchors.fill: parent
                                                anchors.margins: notif.category === "media.playing" ? 0 : 1
                                                source: {
                                                    const ic = notif.icon || ""
                                                    if (ic.startsWith("/") || ic.startsWith("file://")) return ""
                                                    return notif.iconPath ? "file://" + notif.iconPath : ""
                                                }
                                                fillMode: notif.category === "media.playing"
                                                    ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                                visible: status === Image.Ready
                                                cache: false
                                                layer.enabled: notif.category === "media.playing"
                                                layer.effect: MultiEffect {
                                                    maskEnabled: true
                                                    maskSource: hcArtMask
                                                    maskThresholdMin: 0.5
                                                    maskSpreadAtMin: 1.0
                                                }
                                                Rectangle {
                                                    id: hcArtMask
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: "white"
                                                    opacity: 0
                                                    layer.enabled: true
                                                }
                                            }
                                            Text {
                                                anchors.centerIn: parent
                                                visible: !hcIcImg.visible
                                                text: overlay.iconGlyph(notif)
                                                font.pixelSize: 12
                                                font.family: overlay._fontFamily
                                                color: notif.urgency >= 2 ? overlay.cErr : overlay.cOnSurfVar
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            RowLayout {
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: notif.summary || notif.appName || "Notification"
                                                    color: overlay.cOnSurf
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    visible: (notif.count || 1) > 1
                                                    height: 16
                                                    implicitWidth: histCntT.implicitWidth + 10
                                                    radius: 8
                                                    color: Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g,
                                                                   overlay.cPrimary.b, 0.25)
                                                    border.width: 1
                                                    border.color: Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g,
                                                                          overlay.cPrimary.b, 0.4)
                                                    Text {
                                                        id: histCntT
                                                        anchors.centerIn: parent
                                                        text: "×" + (notif.count || 1)
                                                        font.pixelSize: 9
                                                        color: overlay.cPrimary
                                                    }
                                                }
                                            }
                                            Text {
                                                visible: notif.appName !== "" && notif.summary !== ""
                                                text: notif.appName
                                                color: overlay.cOnSurfVar
                                                font.pixelSize: 9
                                                opacity: 0.7
                                            }
                                        }

                                        Text {
                                            text: overlay.formatRelTime(notif.timestamp)
                                            color: overlay.cOnSurfVar
                                            font.pixelSize: 9
                                            opacity: 0.65
                                            Layout.alignment: Qt.AlignVCenter
                                        }

                                        Text {
                                            visible: (notif.body || "").length > 0 || (notif.actions || []).length > 0
                                            text: histCardItem._exp ? "󰅃" : "󰅀"
                                            font.pixelSize: 10
                                            font.family: overlay._fontFamily
                                            color: overlay.cOnSurfVar
                                            opacity: 0.8
                                            Layout.alignment: Qt.AlignVCenter
                                            MouseArea {
                                                anchors.fill: parent
                                                anchors.margins: -4
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: histCardItem._exp = !histCardItem._exp
                                            }
                                        }

                                        Rectangle {
                                            width: 18; height: 18; radius: 5
                                            color: histDismissH.containsMouse
                                                ? Qt.rgba(overlay.cOnSecondary.r, overlay.cOnSecondary.g,
                                                          overlay.cOnSecondary.b, 0.9)
                                                : "transparent"
                                            Behavior on color { ColorAnimation { duration: 80 } }
                                            Text {
                                                anchors.centerIn: parent
                                                text: "×"
                                                font.pixelSize: 9
                                                color: overlay.cOnSurfVar
                                                opacity: 0.7
                                            }
                                            MouseArea {
                                                id: histDismissH
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: histCardItem._commitDismiss()
                                            }
                                        }
                                    }

                                    // Collapsible body section
                                    ColumnLayout {
                                        visible: histCardItem._exp
                                        Layout.fillWidth: true
                                        spacing: 6

                                        Image {
                                            id: hcThumb
                                            property bool _isFp: (notif.icon || "").startsWith("/") || (notif.icon || "").startsWith("file://")
                                            visible: _isFp && notif.category !== "media.playing" && status === Image.Ready
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: Math.min(implicitHeight, 140)
                                            source: notif.iconPath ? "file://" + notif.iconPath : ""
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            mipmap: true
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                maskEnabled: true
                                                maskSource: hcThumbMask
                                                maskThresholdMin: 0.5
                                                maskSpreadAtMin: 1.0
                                            }
                                            Rectangle { id: hcThumbMask; anchors.fill: parent; radius: 6; color: "white"; opacity: 0; layer.enabled: true }
                                        }

                                        Text {
                                            visible: (notif.body || "").length > 0
                                            Layout.fillWidth: true
                                            text: notif.body
                                            color: overlay.cOnSurfVar
                                            font.pixelSize: 10
                                            wrapMode: Text.WordWrap
                                            leftPadding: 14
                                        }

                                        Flow {
                                            visible: (notif.actions || []).length > 0
                                            Layout.fillWidth: true
                                            spacing: 5
                                            leftPadding: 14
                                            Repeater {
                                                model: notif.actions || []
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    visible: modelData && modelData.key !== "default"
                                                    height: 22
                                                    implicitWidth: haL.implicitWidth + 12
                                                    radius: 6
                                                    color: haH.containsMouse
                                                        ? Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.25)
                                                        : Qt.rgba(overlay.cOnSecondary.r, overlay.cOnSecondary.g, overlay.cOnSecondary.b, 0.2)
                                                    border.width: 1
                                                    border.color: Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.35)
                                                    Behavior on color { ColorAnimation { duration: 80 } }
                                                    Text {
                                                        id: haL
                                                        anchors.centerIn: parent
                                                        text: modelData ? (modelData.label || modelData.key || "") : ""
                                                        color: overlay.cWc5
                                                        font.pixelSize: 9
                                                    }
                                                    MouseArea {
                                                        id: haH
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: overlay.invokeAction(notif, modelData.key)
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
