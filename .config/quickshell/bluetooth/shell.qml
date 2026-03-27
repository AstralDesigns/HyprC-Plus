// ~/.config/quickshell/bluetooth/shell.qml
// Bluetooth manager with notifications, pairing, and file transfer handling
// Launch with: qs -c bluetooth

pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Qt.labs.settings 1.1

ShellRoot {
    id: root

    // ── Matugen colors (mirrors startmenu) ─────────────────────────────────────
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

    readonly property color cPrimary:      Qt.color(_m3primary)
    readonly property color cOnPrim:       Qt.color(_m3onPrimary)
    readonly property color cSurfHi:       Qt.color(_m3surfaceContainerHigh)
    readonly property color cSurfMid:      Qt.color(_m3surfaceContainer)
    readonly property color cOnSurf:       Qt.color(_m3onSurface)
    readonly property color cOnSurfVar:    Qt.color(_m3onSurfaceVariant)
    readonly property color cOutVar:       Qt.color(_m3outlineVariant)
    readonly property color cInvPrimary:   Qt.color(_m3inversePrimary)
    readonly property color cErr:          Qt.color(_m3error)
    readonly property color cPanelBg: Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g, Qt.color(_m3onSecondary).b, 0.4)

    function parseColors(t) {
        const re=/property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while((m=re.exec(t))!==null) switch(m[1]) {
            case "m3primary":             root._m3primary=m[2]; break
            case "m3onPrimary":           root._m3onPrimary=m[2]; break
            case "m3onSecondary":         root._m3onSecondary=m[2]; break
            case "m3background":          root._m3background=m[2]; break
            case "m3surfaceContainerHigh":root._m3surfaceContainerHigh=m[2]; break
            case "m3surfaceContainer":    root._m3surfaceContainer=m[2]; break
            case "m3onSurface":           root._m3onSurface=m[2]; break
            case "m3onSurfaceVariant":    root._m3onSurfaceVariant=m[2]; break
            case "m3outlineVariant":      root._m3outlineVariant=m[2]; break
            case "m3inversePrimary":      root._m3inversePrimary=m[2]; break
            case "m3error":               root._m3error=m[2]; break
        }
    }
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME")||(Quickshell.env("HOME")+"/.cache"))+"/quickshell/wallpaper/MatugenColors.qml"
        watchChanges:true; onFileChanged:reload(); onLoaded:root.parseColors(text())
    }

    // ── Visibility state ────────────────────────────────────────────────────────
    property bool managerVisible: false
    IpcHandler {
        target: "bluetooth"
        function toggle() { root.managerVisible = !root.managerVisible }
        function open()   { root.managerVisible = true }
        function close()  { root.managerVisible = false }
    }

    // ── Bluetooth state ───────────────────────────────────────────────────────
    property bool adapterPowered: false
    property bool adapterDiscovering: false
    property var knownDevices: []
    property var discoveredDevices: []
    property var notifications: []

    // ── Bluetooth control process ───────────────────────────────────────────────
    Item {
        // Isolate Process to prevent shell reload on exit
        Process {
            id: btctl
            property var _buf: []
            property bool _initialized: false
            command: ["bash", "-c", "echo 'Agent registered'; bluetoothctl --agent=KeyboardOnly"]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: function(line) {
                    const t = line.trim()
                    if (t) btctl._buf.push(t)
                    // Parse key events
                    if (t.includes("Agent") && !btctl._initialized) {
                        btctl._initialized = true
                        // Register agent and enable notifications
                        btctl.send("default-agent")
                        btctl.send("power on")
                        btctl.send("scan on")
                    } else if (t.includes("RequestPinCode")) {
                        const mac = t.match(/RequestPinCode (.+)/)?.[1]
                        if (mac) root._handlePinRequest(mac)
                    } else if (t.includes("RequestConfirmation")) {
                        const mac = t.match(/RequestConfirmation (.+)/)?.[1]
                        if (mac) root._handleConfirmationRequest(mac)
                    } else if (t.includes("RequestPasskey")) {
                        const mac = t.match(/RequestPasskey (.+)/)?.[1]
                        if (mac) root._handlePasskeyRequest(mac)
                    } else if (t.includes("Authorization")) {
                        const mac = t.match(/Authorization (.+)/)?.[1]
                        if (mac) root._handleAuthorizationRequest(mac)
                    } else if (t.includes("Device")) {
                        root._parseDeviceLine(t)
                    } else if (t.includes("Powered")) {
                        root.adapterPowered = t.includes("yes")
                    } else if (t.includes("Discovering")) {
                        root.adapterDiscovering = t.includes("yes")
                    } else if (t.includes("Connected") || t.includes("Disconnected")) {
                        root._parseConnectionEvent(t)
                    } else if (t.includes("Paired") || t.includes("Unpaired")) {
                        root._parsePairingEvent(t)
                    }
                }
            }
            onRunningChanged: if (running) _buf = []
            onExited: function(code) {
                // Auto-restart on unexpected exit
                if (code !== 0) {
                    btctl._initialized = false
                    restartTimer.start()
                }
            }

            function send(cmd) {
                if (running && btctl._initialized) {
                    write(cmd + "\n")
                }
            }
        }
        Timer {
            id: restartTimer
            interval: 2000
            onTriggered: btctl.running = true
        }
        Timer { interval: 100; running: true; onTriggered: btctl.running = true }
    }

    // ── OBEX (file transfer) process ───────────────────────────────────────────
    Process {
        id: obexctl
        property var _buf: []
        command: ["bash", "-c", "echo 'OBEX ready'; obexctl"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if (t) obexctl._buf.push(t)
                // Parse transfer events
                if (t.includes("Transfer")) {
                    root._parseTransferLine(t)
                } else if (t.includes("Incoming")) {
                    root._handleIncomingTransfer(t)
                }
            }
        }
        onRunningChanged: if (running) _buf = []
        Component.onCompleted: running = true

        function send(cmd) {
            if (running) {
                write(cmd + "\n")
            }
        }
    }

    // ── Event handlers ─────────────────────────────────────────────────────────
    function _handlePinRequest(mac) {
        const device = root._findDevice(mac)
        if (!device) return
        root._addNotification({
            type: "pair-request",
            title: "Pairing Request",
            message: `${device.name || mac} wants to pair. Enter PIN on device.`,
            device: mac,
            actions: ["accept", "reject"],
            timestamp: Date.now()
        })
    }

    function _handleConfirmationRequest(mac) {
        const device = root._findDevice(mac)
        if (!device) return
        root._addNotification({
            type: "confirm-request",
            title: "Pairing Confirmation",
            message: `Confirm pairing with ${device.name || mac}?`,
            device: mac,
            actions: ["confirm", "reject"],
            timestamp: Date.now()
        })
    }

    function _handlePasskeyRequest(mac) {
        const device = root._findDevice(mac)
        if (!device) return
        root._addNotification({
            type: "passkey-request",
            title: "Passkey Required",
            message: `${device.name || mac} requires a passkey.`,
            device: mac,
            actions: ["provide", "reject"],
            timestamp: Date.now()
        })
    }

    function _handleAuthorizationRequest(mac) {
        const device = root._findDevice(mac)
        if (!device) return
        root._addNotification({
            type: "auth-request",
            title: "Authorization Required",
            message: `Authorize connection from ${device.name || mac}?`,
            device: mac,
            actions: ["authorize", "reject"],
            timestamp: Date.now()
        })
    }

    function _handleIncomingTransfer(line) {
        const match = line.match(/Incoming transfer from (.+) \((.+)\)/)
        if (!match) return
        const [, name, mac] = match
        root._addNotification({
            type: "file-request",
            title: "Incoming File",
            message: `${name} wants to send a file`,
            device: mac,
            actions: ["accept", "reject"],
            timestamp: Date.now()
        })
    }

    function _parseDeviceLine(line) {
        const match = line.match(/Device (.+) (.+)/)
        if (!match) return
        const [, mac, name] = match
        const existing = root._findDevice(mac)
        if (existing) {
            existing.name = name
        } else {
            root.discoveredDevices.push({ mac: mac, name: name, paired: false, connected: false })
        }
    }

    function _parseConnectionEvent(line) {
        const match = line.match(/(.+) (Connected|Disconnected): (.+)/)
        if (!match) return
        const [, prefix, action, mac] = match
        const device = root._findDevice(mac)
        if (device) {
            device.connected = action === "Connected"
            root._addNotification({
                type: "connection",
                title: action === "Connected" ? "Device Connected" : "Device Disconnected",
                message: `${device.name || mac} ${action.toLowerCase()}`,
                device: mac,
                timestamp: Date.now()
            })
        }
    }

    function _parsePairingEvent(line) {
        const match = line.match(/(.+) (Paired|Unpaired): (.+)/)
        if (!match) return
        const [, prefix, action, mac] = match
        const device = root._findDevice(mac)
        if (device) {
            device.paired = action === "Paired"
            root._addNotification({
                type: "pairing",
                title: action === "Paired" ? "Device Paired" : "Device Unpaired",
                message: `${device.name || mac} ${action.toLowerCase()}`,
                device: mac,
                timestamp: Date.now()
            })
        }
    }

    function _parseTransferLine(line) {
        // Parse transfer status updates
        const match = line.match(/Transfer (\d+): (.+)/)
        if (!match) return
        const [, id, status] = match
        // Update transfer UI if needed
    }

    function _findDevice(mac) {
        return [...root.knownDevices, ...root.discoveredDevices].find(d => d.mac === mac)
    }

    // ── Notification system ───────────────────────────────────────────────────
    function _addNotification(notif) {
        root.notifications.unshift(notif)
        if (root.notifications.length > 10) {
            root.notifications = root.notifications.slice(0, 10)
        }
        // Auto-dismiss non-critical notifications after 10 seconds
        if (notif.type !== "pair-request" && notif.type !== "file-request") {
            dismissTimer.start()
        }
    }

    Timer {
        id: dismissTimer
        interval: 10000
        onTriggered: {
            root.notifications = root.notifications.filter(n => 
                n.type === "pair-request" || n.type === "file-request"
            )
        }
    }

    // ── Control functions ─────────────────────────────────────────────────────
    function togglePower() {
        btctl.send(root.adapterPowered ? "power off" : "power on")
    }

    function toggleDiscovery() {
        if (root.adapterDiscovering) {
            btctl.send("scan off")
        } else {
            btctl.send("scan on")
        }
    }

    function pairDevice(mac) {
        btctl.send(`pair ${mac}`)
    }

    function connectDevice(mac) {
        btctl.send(`connect ${mac}`)
    }

    function disconnectDevice(mac) {
        btctl.send(`disconnect ${mac}`)
    }

    function removeDevice(mac) {
        btctl.send(`remove ${mac}`)
    }

    function respondToNotification(notif, action) {
        switch (notif.type) {
            case "pair-request":
                if (action === "accept") {
                    btctl.send(`accept ${notif.device}`)
                    // Also send to universal notification center
                    root._sendToNotificationCenter("Pairing accepted", `${notif.device} pairing initiated`, "󰂱", "normal")
                } else {
                    btctl.send(`decline ${notif.device}`)
                    root._sendToNotificationCenter("Pairing declined", `${notif.device} pairing rejected`, "󰂲", "normal")
                }
                break
            case "confirm-request":
                if (action === "confirm") {
                    btctl.send(`yes`)
                    root._sendToNotificationCenter("Pairing confirmed", "Pairing with device confirmed", "󰂱", "normal")
                } else {
                    btctl.send(`no`)
                    root._sendToNotificationCenter("Pairing cancelled", "Device pairing cancelled", "󰂲", "normal")
                }
                break
            case "passkey-request":
                // Would need PIN input UI
                break
            case "auth-request":
                if (action === "authorize") {
                    btctl.send(`authorize ${notif.device}`)
                    root._sendToNotificationCenter("Connection authorized", `${notif.device} connection authorized`, "󰂱", "normal")
                } else {
                    btctl.send(`deny ${notif.device}`)
                    root._sendToNotificationCenter("Connection denied", `${notif.device} connection denied`, "󰂲", "normal")
                }
                break
            case "file-request":
                if (action === "accept") {
                    obexctl.send(`accept`)
                    root._sendToNotificationCenter("File transfer accepted", "Receiving file from device", "󰶫", "normal")
                } else {
                    obexctl.send(`reject`)
                    root._sendToNotificationCenter("File transfer rejected", "File transfer rejected", "󰶫", "normal")
                }
                break
        }
        // Remove notification after action
        root.notifications = root.notifications.filter(n => n !== notif)
    }

    function _sendToNotificationCenter(title, message, icon, urgency) {
        // Send to universal notification center via IPC
        const notifCenter = Quickshell.IpcHandler({
            target: "notifications"
        })
        if (notifCenter.add) {
            notifCenter.add(title, message, icon, urgency, [])
        }
    }

    // ── Window ───────────────────────────────────────────────────────────────────
    PanelWindow {
        id: win
        visible: root.managerVisible
        anchors { top: true; left: true; right: true; bottom: true }
        WlrLayershell.namespace: "quickshell:bluetooth"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.managerVisible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region { item: mainPanel }

        Item {
            anchors.fill: parent

            // Click-to-close backdrop
            MouseArea {
                anchors.fill: parent
                onClicked: root.managerVisible = false
            }

            // Main panel
            Rectangle {
                id: mainPanel
                anchors.centerIn: parent
                width: Math.min(parent.width - 80, 1200)
                height: Math.min(parent.height - 80, 800)
                radius: 23
                color: root.cPanelBg
                border.width: 1
                border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.55)

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 20
                    spacing: 16

                    // Header
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12

                        Text {
                            text: "󰂯"
                            color: root.cPrimary
                            font.pixelSize: 24
                            font.family: "Symbols Nerd Font Mono"
                        }

                        Text {
                            text: "Bluetooth Manager"
                            color: root.cOnSurf
                            font.pixelSize: 20
                            font.weight: Font.Medium
                        }

                        Item { Layout.fillWidth: true }

                        // Power toggle
                        Rectangle {
                            width: 60; height: 32
                            radius: 16
                            color: root.adapterPowered ? root.cPrimary : root.cSurfMid
                            border.width: 1
                            border.color: root.cOutVar
                            Behavior on color { ColorAnimation { duration: 200 } }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.togglePower()
                            }

                            Rectangle {
                                width: 24; height: 24
                                radius: 12
                                color: "white"
                                anchors {
                                    verticalCenter: parent.verticalCenter
                                    left: parent.left
                                    leftMargin: root.adapterPowered ? 32 : 4
                                }
                                Behavior on anchors.leftMargin {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                            }
                        }
                    }

                    // Controls
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        Rectangle {
                            width: 120; height: 34
                            radius: 17
                            color: root.adapterDiscovering ? root.cPrimary : root.cSurfMid
                            border.width: 1
                            border.color: root.cOutVar
                            Behavior on color { ColorAnimation { duration: 150 } }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: root.toggleDiscovery()
                            }

                            Text {
                                anchors.centerIn: parent
                                text: root.adapterDiscovering ? "Scanning..." : "Scan"
                                color: root.adapterDiscovering ? root.cOnPrim : root.cOnSurf
                                font.pixelSize: 12
                                font.weight: Font.Medium
                            }
                        }

                        Item { Layout.fillWidth: true }

                        Text {
                            text: `${root.knownDevices.length + root.discoveredDevices.length} devices`
                            color: root.cOnSurfVar
                            font.pixelSize: 12
                        }
                    }

                    // Device list
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                        ListView {
                            id: deviceList
                            model: [...root.knownDevices, ...root.discoveredDevices]
                            delegate: Rectangle {
                                width: deviceList.width
                                height: 60
                                radius: 12
                                color: "transparent"
                                border.width: 1
                                border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.3)

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.margins: 12
                                    spacing: 12

                                    Text {
                                        text: modelData.paired ? "󰂱" : "󰂯"
                                        color: modelData.paired ? root.cPrimary : root.cOnSurfVar
                                        font.pixelSize: 20
                                        font.family: "Symbols Nerd Font Mono"
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 2

                                        Text {
                                            text: modelData.name || modelData.mac
                                            color: root.cOnSurf
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            text: modelData.mac
                                            color: root.cOnSurfVar
                                            font.pixelSize: 11
                                        }
                                    }

                                    Rectangle {
                                        width: 80; height: 28
                                        radius: 14
                                        color: modelData.connected ? root.cPrimary : root.cSurfMid
                                        border.width: 1
                                        border.color: root.cOutVar

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                if (modelData.connected) {
                                                    root.disconnectDevice(modelData.mac)
                                                } else if (modelData.paired) {
                                                    root.connectDevice(modelData.mac)
                                                } else {
                                                    root.pairDevice(modelData.mac)
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.connected ? "Disconnect" : (modelData.paired ? "Connect" : "Pair")
                                            color: modelData.connected ? root.cOnPrim : root.cOnSurf
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // Notification overlay
            Column {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 20
                spacing: 8
                width: 320

                Repeater {
                    model: root.notifications
                    delegate: Rectangle {
                        width: parent.width
                        height: notifCol.implicitHeight + 20
                        radius: 12
                        color: Qt.rgba(root.cSurfHi.r, root.cSurfHi.g, root.cSurfHi.b, 0.95)
                        border.width: 1
                        border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.4)

                        ColumnLayout {
                            id: notifCol
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            Text {
                                text: modelData.title
                                color: root.cPrimary
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }

                            Text {
                                text: modelData.message
                                color: root.cOnSurf
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Repeater {
                                    model: modelData.actions || []
                                    delegate: Rectangle {
                                        width: 70; height: 28
                                        radius: 14
                                        color: modelData === "reject" || modelData === "deny" ? root.cErr : root.cPrimary
                                        border.width: 1
                                        border.color: modelData === "reject" || modelData === "deny" ? root.cErr : root.cPrimary

                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: root.respondToNotification(modelData, modelData)
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                                            color: "white"
                                            font.pixelSize: 11
                                            font.weight: Font.Medium
                                        }
                                    }
                                }

                                Item { Layout.fillWidth: true }

                                Rectangle {
                                    width: 28; height: 28
                                    radius: 14
                                    color: "transparent"
                                    border.width: 1
                                    border.color: root.cOutVar

                                    MouseArea {
                                        anchors.fill: parent
                                        onClicked: {
                                            root.notifications = root.notifications.filter(n => n !== modelData)
                                        }
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: "✕"
                                        color: root.cOnSurfVar
                                        font.pixelSize: 12
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
