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
        visible: overlay.notifications.length > 0 && !overlay.historyVisible
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 84
        anchors.leftMargin: 6
        width: 364
        implicitHeight: toastCol.implicitHeight

        Column {
            id: toastCol
            width: parent.width
            spacing: 6
            Repeater {
                model: overlay.notifications
                delegate: Item {
                    required property var modelData
                    width: toastCol.width
                    height: toastCard.implicitHeight

                    LockFrosted {
                        id: toastCard
                        blurRoot: overlay
                        width: toastCol.width
                        cornerRadius: 14
                        showTimeoutProgress: !modelData.isPrompt && modelData.urgency < 2
                        progressTimestamp: modelData.timestamp
                        showUrgencyBar: modelData.urgency >= 2
                        urgencyCol: modelData.urgency >= 2 ? overlay.cErr : overlay.cPrimary
                        borderCol: modelData.urgency >= 2
                            ? Qt.rgba(overlay.cErr.r, overlay.cErr.g, overlay.cErr.b, 0.55)
                            : modelData.category === "bt"
                                ? Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.5)
                                : Qt.rgba(overlay.cOutVar.r, overlay.cOutVar.g, overlay.cOutVar.b, 0.38)

                        ColumnLayout {
                            width: toastCol.width - 20 - (modelData.urgency >= 2 ? 4 : 0)
                            spacing: 6

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 10

                                Item {
                                    width: modelData.category === "media.playing" ? 48 : 34
                                    height: modelData.category === "media.playing" ? 48 : 34
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: modelData.category === "media.playing" ? width / 2 : 9
                                        color: modelData.urgency >= 2
                                            ? Qt.rgba(overlay.cErr.r, overlay.cErr.g, overlay.cErr.b, 0.18)
                                            : Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 0.15)
                                    }
                                    Item {
                                        id: toastIcWrap
                                        anchors.fill: parent
                                        anchors.margins: modelData.category === "media.playing" ? 0 : 4
                                        visible: toastIcImg.status === Image.Ready
                                        layer.enabled: modelData.category === "media.playing"
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
                                            source: modelData.iconPath ? "file://" + modelData.iconPath : ""
                                            fillMode: Image.PreserveAspectCrop
                                            smooth: true
                                            mipmap: true
                                            cache: false
                                        }
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !toastIcWrap.visible
                                        text: overlay.iconGlyph(modelData)
                                        font.pixelSize: modelData.category === "media.playing" ? 22 : 17
                                        font.family: overlay._fontFamily
                                        color: modelData.urgency >= 2 ? overlay.cErr : overlay.cPrimary
                                    }
                                    Rectangle {
                                        visible: (modelData.count || 1) > 1
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
                                            text: modelData.count || 1
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
                                        text: modelData.summary || modelData.appName || "Notification"
                                        color: overlay.cOnSurf
                                        font.pixelSize: 12
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    Text {
                                        visible: modelData.appName !== "" && modelData.summary !== ""
                                        text: modelData.appName
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
                                        onClicked: overlay.dismissNotification(modelData.id)
                                    }
                                }
                            }

                            Text {
                                visible: (modelData.body || "").length > 0
                                Layout.fillWidth: true
                                text: modelData.body
                                color: overlay.cOnSurfVar
                                font.pixelSize: 11
                                wrapMode: Text.WordWrap
                                maximumLineCount: 4
                                leftPadding: modelData.category === "media.playing" ? 58 : 44
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
        visible: overlay.historyVisible
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: 84
        anchors.leftMargin: 6
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
                        color: overlay.dndEnabled ? Qt.rgba(overlay.cPrimary.r, overlay.cPrimary.g, overlay.cPrimary.b, 1.0) : overlay.cPrimary
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
                    color: Qt.rgba(overlay.cOutVar.r, overlay.cOutVar.g, overlay.cOutVar.b, 0.3)
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
                                required property var modelData
                                Layout.fillWidth: true
                                implicitHeight: histRow.implicitHeight + 16
                                radius: 10
                                color: Qt.rgba(overlay.cOnSecondary.r, overlay.cOnSecondary.g,
                                               overlay.cOnSecondary.b, 0.22)
                                border.width: 1
                                border.color: Qt.rgba(overlay.cOutVar.r, overlay.cOutVar.g,
                                                      overlay.cOutVar.b, 0.25)

                                ColumnLayout {
                                    id: histRow
                                    anchors.fill: parent
                                    anchors.margins: 8
                                    spacing: 4

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: 8

                                        Rectangle {
                                            width: 6; height: 6; radius: 3
                                            Layout.alignment: Qt.AlignVCenter
                                            color: modelData.urgency >= 2 ? overlay.cErr
                                                : modelData.category === "bt" ? overlay.cPrimary
                                                : Qt.rgba(overlay.cOnSurfVar.r, overlay.cOnSurfVar.g,
                                                          overlay.cOnSurfVar.b, 0.5)
                                        }

                                        Item {
                                            width: 20; height: 20
                                            Image {
                                                id: hcIcImg
                                                anchors.fill: parent
                                                anchors.margins: modelData.category === "media.playing" ? 0 : 1
                                                source: {
                                                    const ic = modelData.icon || ""
                                                    if (ic.startsWith("/") || ic.startsWith("file://")) return ""
                                                    return modelData.iconPath ? "file://" + modelData.iconPath : ""
                                                }
                                                fillMode: modelData.category === "media.playing"
                                                    ? Image.PreserveAspectCrop : Image.PreserveAspectFit
                                                smooth: true
                                                mipmap: true
                                                visible: status === Image.Ready
                                                cache: false
                                                layer.enabled: modelData.category === "media.playing"
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
                                                text: overlay.iconGlyph(modelData)
                                                font.pixelSize: 12
                                                font.family: overlay._fontFamily
                                                color: modelData.urgency >= 2 ? overlay.cErr : overlay.cOnSurfVar
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 0
                                            RowLayout {
                                                Text {
                                                    Layout.fillWidth: true
                                                    text: modelData.summary || modelData.appName || "Notification"
                                                    color: overlay.cOnSurf
                                                    font.pixelSize: 11
                                                    font.weight: Font.Medium
                                                    elide: Text.ElideRight
                                                }
                                                Rectangle {
                                                    visible: (modelData.count || 1) > 1
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
                                                        text: "×" + (modelData.count || 1)
                                                        font.pixelSize: 9
                                                        color: overlay.cPrimary
                                                    }
                                                }
                                            }
                                            Text {
                                                visible: modelData.appName !== "" && modelData.summary !== ""
                                                text: modelData.appName
                                                color: overlay.cOnSurfVar
                                                font.pixelSize: 9
                                                opacity: 0.7
                                            }
                                        }

                                        Text {
                                            text: overlay.formatRelTime(modelData.timestamp)
                                            color: overlay.cOnSurfVar
                                            font.pixelSize: 9
                                            opacity: 0.65
                                            Layout.alignment: Qt.AlignVCenter
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
                                                onClicked: overlay.removeHistory(modelData.id)
                                            }
                                        }
                                    }

                                    Text {
                                        visible: (modelData.body || "").length > 0
                                        Layout.fillWidth: true
                                        text: modelData.body
                                        color: overlay.cOnSurfVar
                                        font.pixelSize: 10
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        leftPadding: 14
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
