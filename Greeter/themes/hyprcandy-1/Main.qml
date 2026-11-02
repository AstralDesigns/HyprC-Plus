import QtQuick 2.15
import QtQuick.Window 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15
import QtQuick.Effects 2.15

// hyprcandy-1 — Material You glass greeter (Qt6).
// Palette comes from ../hyprcandy-shared (matugen + wallust, synced by
// greeter-sync.sh); layout knobs come from theme.conf (config.*).
Pane {
    id: root

    // ── config helpers ──────────────────────────────────────────────────
    function bgUrl() {
        const b = config.Background || ""
        if (b === "")
            return ""
        if (b.indexOf("/") === 0 || b.indexOf("file://") === 0 || b.indexOf("image://") === 0)
            return b
        return Qt.resolvedUrl(b)
    }
    function faceFor(name) {
        if (!name)
            return ""
        return "image:///usr/share/sddm/faces/" + name.toLowerCase() + ".face.icon"
    }

    readonly property int cardRadius: parseInt(config.RoundCorners) || 20
    readonly property real blurAmt: Math.min(1.0, Math.max(0.0, (parseInt(config.BlurRadius) || 0) / 100))
    readonly property string labelFont: config.Font && config.Font !== "" ? config.Font : "Noto Sans"

    // Theme.qml (sibling file) = matugen M3 + wallust bridge
    Theme {
        id: theme
    }

    // Config overrides win when set; otherwise M3 palette decides
    readonly property color colText: (config.MainColor && config.MainColor !== "")
        ? config.MainColor : theme.cOnSurface
    readonly property color colAccent: (config.AccentColor && config.AccentColor !== "")
        ? config.AccentColor : theme.cPrimary
    readonly property color colWindow: (config.BackgroundColor && config.BackgroundColor !== "")
        ? config.BackgroundColor : theme.cSurfaceContainerHighest

    background: Rectangle { color: root.colWindow }

    // ── Background image ────────────────────────────────────────────────
    Image {
        id: bgImage
        anchors.fill: parent
        source: root.bgUrl()
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: status === Image.Ready
    }

    // ── Login card ──────────────────────────────────────────────────────
    readonly property real cardPos: config.FormPosition === "left" ? 0.16
                                  : config.FormPosition === "right" ? 0.84 : 0.5

    // Blurred backdrop clipped to the card silhouette (glass)
    Item {
        id: cardGlass
        width: card.width
        height: card.height
        x: card.x
        y: card.y

        Rectangle {
            id: glassMask
            anchors.fill: parent
            radius: root.cardRadius
            visible: false
        }

        Image {
            anchors.fill: parent
            source: bgImage.source
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            visible: root.blurAmt > 0.02 && status === Image.Ready
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: root.blurAmt
                blurMax: 64
                maskEnabled: true
                maskSource: glassMask
            }
        }
    }

    Rectangle {
        id: card
        width: 380
        height: cardCol.implicitHeight + 44
        x: root.width * root.cardPos - width / 2 + cardShake.offset
        y: root.height / 2 - height / 2
        radius: root.cardRadius
        color: theme.panelGlass
        border.width: 1
        border.color: theme.outlineSoft

        layer.enabled: (parseInt(config.InterfaceShadowSize) || 0) > 0
        layer.effect: MultiEffect {
            shadowEnabled: true
            shadowColor: "#99000000"
            shadowBlur: Math.min(1.0, (parseInt(config.InterfaceShadowSize) || 6) / 24)
            shadowVerticalOffset: 6
            shadowHorizontalOffset: 0
        }

        // shake offset driven by NumberAnimation (never animates x itself,
        // so the positional binding survives)
        QtObject {
            id: cardShake
            property real offset: 0
            function shake() {
                shakeSeq.stop()
                offset = 0
                shakeSeq.start()
            }
        }
        SequentialAnimation {
            id: shakeSeq
            running: false
            NumberAnimation { target: cardShake; property: "offset"; to: -8; duration: 50; easing.type: Easing.OutQuad }
            NumberAnimation { target: cardShake; property: "offset"; to: 8; duration: 60; easing.type: Easing.OutQuad }
            NumberAnimation { target: cardShake; property: "offset"; to: -5; duration: 50; easing.type: Easing.OutQuad }
            NumberAnimation { target: cardShake; property: "offset"; to: 0; duration: 40 }
        }

        ColumnLayout {
            id: cardCol
            anchors { fill: parent; margins: 22 }
            spacing: 10

            // Clock + date
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: clockTimer.clockText
                color: root.colText
                font.family: root.labelFont
                font.pixelSize: 40
                font.weight: Font.Light
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: clockTimer.dateText
                color: root.colText
                opacity: 0.65
                font.family: root.labelFont
                font.pixelSize: 13
            }
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: text !== ""
                text: (config.HeaderText && config.HeaderText !== "")
                    ? config.HeaderText : "HyprCandy+"
                color: root.colAccent
                font.family: root.labelFont
                font.pixelSize: 20
                font.weight: Font.SemiBold
                topPadding: 4
            }

            Item { Layout.preferredHeight: 6 }

            // Avatar + user cycling
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 14

                Rectangle {
                    visible: userModel.count > 1
                    width: 30; height: 30; radius: 15
                    color: prevHov.containsMouse ? theme.hoverTint : "transparent"
                    border.width: 1; border.color: theme.outlineSoft
                    Text { anchors.centerIn: parent; text: "<"; color: root.colText; font.pixelSize: 14 }
                    MouseArea {
                        id: prevHov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: userModel.currentIndex = (userModel.currentIndex + userModel.count - 1) % userModel.count
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 84
                    Layout.preferredHeight: 84
                    radius: 42
                    color: theme.cSurfaceContainer
                    border.width: 2
                    border.color: theme.cPrimary

                    Rectangle {
                        id: faceMask
                        anchors.fill: parent
                        radius: 42
                        visible: false
                    }

                    Image {
                        id: avatar
                        anchors.fill: parent
                        anchors.margins: 2
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        asynchronous: false
                        source: root.faceFor(userModel.currentName)
                        sourceSize: Qt.size(168, 168)
                        onFailed: source = ""
                        visible: status === Image.Ready
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: faceMask
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 40
                        visible: avatar.status !== Image.Ready
                        color: theme.cPrimaryContainer
                        Text {
                            anchors.centerIn: parent
                            text: (userModel.currentName || "?").slice(0, 1).toUpperCase()
                            color: theme.cOnPrimaryContainer
                            font.pixelSize: 34
                        }
                    }
                }

                Rectangle {
                    visible: userModel.count > 1
                    width: 30; height: 30; radius: 15
                    color: nextHov.containsMouse ? theme.hoverTint : "transparent"
                    border.width: 1; border.color: theme.outlineSoft
                    Text { anchors.centerIn: parent; text: ">"; color: root.colText; font.pixelSize: 14 }
                    MouseArea {
                        id: nextHov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: userModel.currentIndex = (userModel.currentIndex + 1) % userModel.count
                    }
                }
            }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: userModel.currentName || ""
                color: root.colText
                font.family: root.labelFont
                font.pixelSize: 16
                font.weight: Font.DemiBold
            }

            // Password field
            Rectangle {
                Layout.fillWidth: true
                height: 42
                radius: Math.min(root.cardRadius, 12)
                color: theme.fieldGlass
                border.width: pwdField.activeFocus ? 2 : 1
                border.color: pwdField.activeFocus ? root.colAccent : theme.outlineSoft
                Behavior on border.color { ColorAnimation { duration: 120 } }

                TextInput {
                    id: pwdField
                    anchors {
                        fill: parent
                        leftMargin: 14
                        rightMargin: 44
                        verticalCenter: parent.verticalCenter
                    }
                    clip: true
                    color: root.colText
                    echoMode: revealBtn.on ? TextInput.Normal : TextInput.Password
                    font.family: root.labelFont
                    font.pixelSize: 14
                    selectionColor: root.colAccent
                    selectedTextColor: theme.cOnPrimary
                    onAccepted: loginHov.clicked()

                    Text {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        visible: !pwdField.displayText && !pwdField.activeFocus
                        text: "Password"
                        color: root.colText
                        opacity: 0.45
                        font.family: pwdField.font.family
                        font.pixelSize: pwdField.font.pixelSize
                    }
                }

                Rectangle {
                    id: revealBtn
                    property bool on: false
                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                    width: 30; height: 30; radius: 15
                    color: hov.containsMouse ? theme.hoverTint : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: revealBtn.on ? "\u{F0208}" : "\u{F0701}"
                        color: root.colText
                        opacity: 0.8
                        font.pixelSize: 13
                    }
                    MouseArea {
                        id: hov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: revealBtn.on = !revealBtn.on
                    }
                }
            }

            // warnings
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                Text {
                    visible: root.failure
                    Layout.fillWidth: true
                    text: "Login failed!"
                    color: theme.cError
                    font.family: root.labelFont
                    font.pixelSize: 12
                }
                Text {
                    visible: keyboard.capsLock
                    Layout.fillWidth: true
                    text: "Capslock is on"
                    color: root.colAccent
                    font.family: root.labelFont
                    font.pixelSize: 12
                    opacity: 0.9
                }
            }

            // session selector (click cycles; index kept by hidden model)
            Rectangle {
                Layout.fillWidth: true
                height: 36
                radius: 10
                color: sessionHov.containsMouse ? theme.hoverTint : "transparent"
                border.width: 1
                border.color: theme.outlineSoft

                RowLayout {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 8 }
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: "Session: " + (sessionModel.count > 0
                            ? sessionModel.get(sessionSelect.currentIndex).name : "none")
                        color: root.colText
                        opacity: 0.85
                        font.family: root.labelFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text { text: "▾"; color: root.colText; opacity: 0.6; font.pixelSize: 12 }
                }

                MouseArea {
                    id: sessionHov
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: sessionSelect.currentIndex =
                        (sessionSelect.currentIndex + 1) % Math.max(1, sessionModel.count)
                }
            }

            ComboBox {
                id: sessionSelect
                visible: false
                model: sessionModel
                currentIndex: sessionModel.defaultIndex >= 0
                    ? sessionModel.defaultIndex : 0
            }

            // login button
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                height: 40
                radius: Math.min(root.cardRadius, 12)
                color: loginHov.containsMouse ? theme.cPrimary : theme.cPrimaryContainer
                border.width: 1
                border.color: theme.outlineSoft
                Behavior on color { ColorAnimation { duration: 120 } }

                Text {
                    anchors.centerIn: parent
                    text: "Login"
                    color: theme.cOnPrimaryContainer
                    font.family: root.labelFont
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                MouseArea {
                    id: loginHov
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        const user = userModel.currentName || ""
                        sddm.login(user.indexOf(" ") > -1 ? user.toLowerCase() : user,
                                   pwdField.text, sessionSelect.currentIndex)
                    }
                }
            }

            // power row
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                spacing: 10

                Repeater {
                    model: [
                        { label: "Suspend", can: sddm.canSuspend,  what: "suspend" },
                        { label: "Reboot",  can: sddm.canReboot,   what: "reboot" },
                        { label: "Power",   can: sddm.canPowerOff, what: "powerOff" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        required property int index
                        visible: modelData.can
                        height: 28
                        implicitWidth: pwrLbl.implicitWidth + 18
                        radius: 9
                        color: pwrHov.containsMouse ? theme.hoverTint : "transparent"
                        border.width: 1
                        border.color: theme.outlineSoft
                        Text {
                            id: pwrLbl
                            anchors.centerIn: parent
                            text: modelData.label
                            color: root.colText
                            opacity: 0.85
                            font.family: root.labelFont
                            font.pixelSize: 11
                        }
                        MouseArea {
                            id: pwrHov
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.what === "suspend") sddm.suspend()
                                else if (modelData.what === "reboot") sddm.reboot()
                                else sddm.powerOff()
                            }
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: 2 }

            Text {
                Layout.alignment: Qt.AlignHCenter
                text: sddm.hostName
                color: root.colText
                opacity: 0.5
                font.family: root.labelFont
                font.pixelSize: 11
            }
        }
    }

    // ── login lifecycle ─────────────────────────────────────────────────
    property bool failure: false

    Connections {
        target: sddm
        function onLoginSucceeded() { }
        function onLoginFailed() {
            root.failure = true
            pwdField.text = ""
            pwdField.forceActiveFocus()
            cardShake.shake()
        }
    }

    // ── clock ───────────────────────────────────────────────────────────
    QtObject {
        id: clockTimer
        property string clockText: ""
        property string dateText: ""
        function refresh() {
            const now = new Date()
            clockText = Qt.formatTime(now, config.HourFormat && config.HourFormat !== "" ? config.HourFormat : "HH:mm")
            dateText = Qt.formatDate(now, config.DateFormat && config.DateFormat !== "" ? config.DateFormat : "dddd, d of MMMM")
        }
        Component.onCompleted: refresh()
        Timer {
            interval: 1000
            repeat: true
            running: true
            onTriggered: clockTimer.refresh()
        }
    }

    Component.onCompleted: {
        if (config.ForcePasswordFocus === "true")
            pwdField.forceActiveFocus()
    }
}
