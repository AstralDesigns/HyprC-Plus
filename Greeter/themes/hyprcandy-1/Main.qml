import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

// hyprcandy-1 — Material You glass greeter (Qt6).
// Palette comes from ../hyprcandy-shared (matugen + wallust, synced by
// greeter-sync.sh); layout knobs come from theme.conf (config.*).
//
// Layering mirrors candylock: a blurred InversePrimary outer form wraps
// dark inner sub-cards (header + login) and a StartMenu-style power pill.
// SDDM API notes: UserModel exposes count/lastIndex + name/icon roles (no
// currentName/get()); SessionModel exposes count/lastIndex + name role.
Pane {
    id: root

    // Fill the physical screen; honor a config size only when the user set
    // one smaller than the real screen (otherwise the wallpaper auto-fits).
    width: (parseInt(config.ScreenWidth) || 0) > 0 && parseInt(config.ScreenWidth) < Screen.width
        ? parseInt(config.ScreenWidth) : Screen.width
    height: (parseInt(config.ScreenHeight) || 0) > 0 && parseInt(config.ScreenHeight) < Screen.height
        ? parseInt(config.ScreenHeight) : Screen.height

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
    function doLogin() {
        const user = root.activeUser
        if (user === "")
            return
        sddm.login(user.indexOf(" ") > -1 ? user.toLowerCase() : user,
                   pwdField.text, sessionSelect.currentIndex)
    }

    // Current user tracked by index into userModel; the avatar Repeater
    // publishes the active name for the login call.
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    property string activeUser: ""
    property bool failure: false

    readonly property int cardRadius: parseInt(config.RoundCorners) || 20
    readonly property real blurAmt: Math.min(1.0, Math.max(0.0, (parseInt(config.BlurRadius) || 0) / 100))
    readonly property string labelFont: config.Font && config.Font !== "" ? config.Font : "Noto Sans"
    readonly property string iconFont: "Symbols Nerd Font Mono"
    readonly property string clockFont: "C059"

    // Theme.qml (sibling) = matugen M3 + wallust bridge.
    Theme { id: theme }

    // Outer form opacity follows the CC "Blur R" slider (config.BlurRadius).
    Binding {
        target: theme
        property: "formAlpha"
        value: 0.25 + root.blurAmt * 0.5
    }

    // Config overrides win when set; otherwise M3 palette decides.
    readonly property color colText: (config.MainColor && config.MainColor !== "")
        ? config.MainColor : theme.cOnSurface
    readonly property color colAccent: (config.AccentColor && config.AccentColor !== "")
        ? config.AccentColor : theme.cPrimary
    readonly property color colWindow: (config.BackgroundColor && config.BackgroundColor !== "")
        ? config.BackgroundColor : theme.cSurfaceContainerHighest

    background: Rectangle { color: root.colWindow }

    // ── Background (fills screen; animates gif when enabled) ────────────
    readonly property bool animateBg: config.AnimatedImage !== "false"
    readonly property url bgSrc: root.bgUrl()

    Image {
        id: bgImage
        anchors.fill: parent
        source: root.animateBg ? "" : root.bgSrc
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: status === Image.Ready
    }

    AnimatedImage {
        id: bgAnim
        anchors.fill: parent
        source: root.animateBg ? root.bgSrc : ""
        fillMode: Image.PreserveAspectCrop
        playing: true
        cache: false
        visible: status === Image.Ready
    }

    // ── Login lifecycle ─────────────────────────────────────────────────
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

    // Shake offset driven by a NumberAnimation (never animates x itself, so
    // the positional binding on the form survives).
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

    // ── Form position ───────────────────────────────────────────────────
    readonly property real cardPos: config.FormPosition === "left" ? 0.16
                                  : config.FormPosition === "right" ? 0.84 : 0.5

    // Real frosted blur: an aligned, blurred copy of the wallpaper clipped to
    // the form silhouette, sitting behind the translucent InversePrimary form.
    Rectangle {
        id: formBlur
        x: form.x
        y: form.y
        width: form.width
        height: form.height
        radius: root.cardRadius
        color: "transparent"
        clip: true

        Image {
            x: -form.x
            y: -form.y
            width: root.width
            height: root.height
            source: root.bgSrc
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
            visible: status === Image.Ready
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: root.blurAmt
                blurMax: 64
            }
        }
    }

    // ── Outer form (InversePrimary glass wrapping the inner cards) ──────
    Rectangle {
        id: form
        width: 384
        height: formCol.implicitHeight + 32
        x: root.width * root.cardPos - width / 2 + cardShake.offset
        y: root.height / 2 - height / 2
        radius: root.cardRadius
        color: theme.formGlass
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

        ColumnLayout {
            id: formCol
            anchors { fill: parent; margins: 16 }
            spacing: 14

            // ── Header inner card: clock + date + title ─────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerCol.implicitHeight + 22
                radius: Math.min(root.cardRadius, 16)
                color: theme.innerCard
                border.width: 1
                border.color: theme.outlineSoft

                ColumnLayout {
                    id: headerCol
                    anchors { fill: parent; margins: 11 }
                    spacing: 1

                    // Candylock-style split clock with wallust accent colors.
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6
                        Text {
                            text: clockTimer.clockHour
                            color: theme.cWc5
                            font.family: root.clockFont
                            font.pixelSize: 40
                            font.bold: true
                            font.italic: true
                        }
                        // Vertical seconds coverflow replacing the ":" — the
                        // current second sits centred; neighbours fan above and
                        // below, scaled down and dimmed, sliding up one slot per
                        // tick (candylock coverflow rotated to the vertical).
                        Item {
                            id: secStage
                            Layout.preferredWidth: 34
                            Layout.preferredHeight: 46
                            Layout.alignment: Qt.AlignVCenter
                            clip: true
                            readonly property int sec: clockTimer.sec
                            readonly property real slot: 20
                            property bool _primed: false
                            Timer {
                                id: secPrimeTimer
                                interval: 350
                                onTriggered: secStage._primed = true
                            }
                            onVisibleChanged: if (visible) secPrimeTimer.restart()
                            Component.onCompleted: if (visible) secPrimeTimer.restart()
                            Repeater {
                                model: 60
                                delegate: Text {
                                    required property int modelData
                                    readonly property int role: {
                                        let r = modelData - secStage.sec
                                        if (r > 30) r -= 60
                                        if (r < -30) r += 60
                                        return r
                                    }
                                    visible: Math.abs(role) <= 2
                                    text: modelData < 10 ? "0" + modelData : "" + modelData
                                    font.family: root.clockFont
                                    font.pixelSize: 17
                                    font.italic: true
                                    font.weight: Font.Bold
                                    color: theme.cPrimary
                                    x: secStage.width / 2 - width / 2
                                    y: secStage.height / 2 - height / 2 + role * secStage.slot
                                    scale: role === 0 ? 1.0 : (Math.abs(role) === 1 ? 0.6 : 0.4)
                                    opacity: role === 0 ? 1.0 : (Math.abs(role) === 1 ? 0.45 : 0.16)
                                    z: role === 0 ? 10 : 5 - Math.abs(role)
                                    Behavior on y { enabled: secStage._primed; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                    Behavior on scale { enabled: secStage._primed; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                    Behavior on opacity { enabled: secStage._primed; NumberAnimation { duration: 320; easing.type: Easing.OutCubic } }
                                }
                            }
                        }
                        Text {
                            text: clockTimer.clockMin
                            color: theme.cWc3
                            font.family: root.clockFont
                            font.pixelSize: 40
                            font.bold: true
                            font.italic: true
                        }
                    }
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: clockTimer.dateText
                        color: root.colText
                        opacity: 0.6
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 2
                        font.family: root.labelFont
                        font.pixelSize: 11
                    }
                }
            }

            // ── Login inner card ────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: loginCol.implicitHeight + 24
                radius: Math.min(root.cardRadius, 16)
                color: theme.innerCardAlt
                border.width: 1
                border.color: theme.outlineSoft

                ColumnLayout {
                    id: loginCol
                    anchors { fill: parent; margins: 12 }
                    spacing: 10

                    // Avatar + user cycling (only shown when >1 user).
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        Rectangle {
                            visible: userModel.count > 1
                            width: 30; height: 30; radius: 15
                            color: prevHov.containsMouse ? theme.hoverTint : "transparent"
                            border.width: 1; border.color: theme.outlineSoft
                            Text {
                                anchors.centerIn: parent
                                text: "\u{F0141}"
                                color: root.colText
                                font.family: root.iconFont
                                font.pixelSize: 16
                            }
                            MouseArea {
                                id: prevHov
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.userIndex =
                                    (root.userIndex + userModel.count - 1) % userModel.count
                            }
                        }

                        Repeater {
                            model: userModel
                            delegate: Rectangle {
                                required property int index
                                required property string name
                                required property var icon
                                visible: index === root.userIndex
                                onVisibleChanged: if (visible) root.activeUser = name
                                Component.onCompleted: if (index === root.userIndex) root.activeUser = name

                                Layout.preferredWidth: 130
                                Layout.preferredHeight: 130
                                radius: 65
                                color: theme.cSurfaceContainer

                                // Image clipped just inside the 4px ring so its
                                // bottom arc can't bleed past the border (the
                                // lockscreen fix).
                                Rectangle {
                                    anchors { fill: parent; margins: 4 }
                                    radius: 61
                                    clip: true
                                    color: "transparent"
                                    Image {
                                        id: avatarImg
                                        anchors.fill: parent
                                        source: (icon && icon.toString() !== "")
                                            ? icon : root.faceFor(name)
                                        fillMode: Image.PreserveAspectCrop
                                        smooth: true
                                        cache: false
                                        visible: status === Image.Ready
                                    }
                                    Text {
                                        anchors.centerIn: parent
                                        visible: avatarImg.status !== Image.Ready
                                        text: (name || "?").slice(0, 1).toUpperCase()
                                        color: theme.cOnSurfaceVariant
                                        font.family: root.labelFont
                                        font.pixelSize: 56
                                        font.weight: Font.DemiBold
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 65
                                    color: "transparent"
                                    border.width: 4
                                    border.color: theme.cWc5
                                }
                            }
                        }

                        Rectangle {
                            visible: userModel.count > 1
                            width: 30; height: 30; radius: 15
                            color: nextHov.containsMouse ? theme.hoverTint : "transparent"
                            border.width: 1; border.color: theme.outlineSoft
                            Text {
                                anchors.centerIn: parent
                                text: "\u{F0142}"
                                color: root.colText
                                font.family: root.iconFont
                                font.pixelSize: 16
                            }
                            MouseArea {
                                id: nextHov
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.userIndex = (root.userIndex + 1) % userModel.count
                            }
                        }
                    }

                    // Username (click opens the user popup when >1 user).
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: userRow.implicitWidth + 18
                        height: 28
                        radius: 8
                        color: userHov.containsMouse ? theme.hoverTint : "transparent"

                        RowLayout {
                            id: userRow
                            anchors.centerIn: parent
                            spacing: 6
                            Text {
                                text: "\u{F0004}"
                                font.family: root.iconFont
                                font.pixelSize: 15
                                color: theme.cWc5
                            }
                            Repeater {
                                model: userModel
                                delegate: Text {
                                    required property int index
                                    required property string name
                                    visible: index === root.userIndex
                                    text: name
                                    color: theme.cPrimary
                                    font.family: root.labelFont
                                    font.pixelSize: 16
                                    font.weight: Font.DemiBold
                                }
                            }
                            Text {
                                visible: userModel.count > 1
                                text: "\u{F0140}"
                                color: root.colText
                                opacity: 0.6
                                font.family: root.iconFont
                                font.pixelSize: 14
                            }
                        }
                        MouseArea {
                            id: userHov
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            enabled: userModel.count > 1
                            onClicked: userPopup.open()
                        }
                    }

                    // Password field — minimal sugar-candy sizing; text/dots
                    // centred across the field with the key icon pinned left and
                    // the reveal toggle right.
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 240
                        height: 34
                        radius: 10
                        color: theme.fieldGlass
                        border.width: pwdField.activeFocus ? 2 : 1
                        border.color: pwdField.activeFocus ? theme.cWc3 : theme.outlineSoft
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        TextInput {
                            id: pwdField
                            anchors { fill: parent; leftMargin: 26; rightMargin: 26 }
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment: TextInput.AlignVCenter
                            color: root.colText
                            echoMode: revealBtn.on ? TextInput.Normal : TextInput.Password
                            font.family: root.labelFont
                            font.pixelSize: 12
                            selectionColor: theme.cPrimary
                            selectedTextColor: theme.cOnPrimary
                            onAccepted: root.doLogin()
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 9; verticalCenter: parent.verticalCenter }
                            text: "\u{F030B}"
                            font.family: root.iconFont
                            font.pixelSize: 13
                            color: theme.cWc3
                            opacity: 0.85
                        }
                        Rectangle {
                            id: revealBtn
                            property bool on: false
                            anchors { right: parent.right; rightMargin: 5; verticalCenter: parent.verticalCenter }
                            width: 22; height: 22; radius: 11
                            color: revealHov.containsMouse ? theme.hoverTint : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: revealBtn.on ? "\u{F0208}" : "\u{F0209}"
                                color: root.colText
                                opacity: 0.8
                                font.family: root.iconFont
                                font.pixelSize: 13
                            }
                            MouseArea {
                                id: revealHov
                                anchors.fill: parent; hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: revealBtn.on = !revealBtn.on
                            }
                        }
                        Text {
                            anchors.centerIn: pwdField
                            visible: !pwdField.text && !pwdField.activeFocus
                            text: "Password"
                            color: root.colText
                            opacity: 0.4
                            font.family: root.labelFont
                            font.pixelSize: 12
                        }
                    }

                    // Warnings.
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
                            color: theme.cWc11
                            font.family: root.labelFont
                            font.pixelSize: 12
                            opacity: 0.9
                        }
                    }

                    // Login button — pill (radius 99), SurfaceTint glass with
                    // OnSecondary label, hugs its own width.
                    Rectangle {
                        id: loginBtn
                        Layout.alignment: Qt.AlignHCenter
                        Layout.preferredWidth: 120
                        Layout.topMargin: 2
                        height: 30
                        radius: 99
                        readonly property bool enabledLogin:
                            config.AllowEmptyPassword === "true" || pwdField.text.length > 0
                        color: !enabledLogin ? theme.cSurfaceContainer
                             : (loginHov.containsMouse ? theme.cSurfaceTint : theme.pill)
                        border.width: 1
                        border.color: theme.outlineSoft
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Text {
                            anchors.centerIn: parent
                            text: "Login"
                            color: loginBtn.enabledLogin ? theme.cOnSecondary : theme.cSurfaceTint
                            font.family: root.labelFont
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                        MouseArea {
                            id: loginHov
                            anchors.fill: parent; hoverEnabled: true
                            enabled: loginBtn.enabledLogin
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.doLogin()
                        }
                    }

                    // Session selector — no enclosing pill: Primary text sits
                    // directly on the card, a cWc5 chevron one space after it.
                    // The dropdown itself is a SurfaceTint panel.
                    ComboBox {
                        id: sessionSelect
                        Layout.alignment: Qt.AlignHCenter
                        height: 22
                        model: sessionModel
                        textRole: "name"
                        currentIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0

                        contentItem: Row {
                            spacing: 5
                            Text {
                                id: sessText
                                text: sessionModel.count > 0 ? sessionSelect.currentText : "none"
                                color: theme.cPrimary
                                font.family: root.labelFont
                                font.pixelSize: 11
                            }
                            Text {
                                anchors.verticalCenter: sessText.verticalCenter
                                text: "\u{F0140}"
                                color: theme.cWc5
                                font.family: root.iconFont
                                font.pixelSize: 12
                            }
                        }

                        indicator: Item { width: 0; height: 0 }

                        background: Item {}

                        delegate: ItemDelegate {
                            required property int index
                            required property string name
                            width: ListView.view ? ListView.view.width : 220
                            contentItem: Text {
                                text: parent.name
                                color: parent.highlighted ? theme.cInversePrimary : theme.cOnSecondary
                                font.family: root.labelFont
                                font.pixelSize: 11
                            }
                            highlighted: sessionSelect.highlightedIndex === index
                            background: Rectangle {
                                radius: 6
                                color: highlighted
                                    ? Qt.rgba(theme.cOnSecondary.r, theme.cOnSecondary.g, theme.cOnSecondary.b, 0.2)
                                    : "transparent"
                            }
                        }

                        popup: Popup {
                            x: (sessionSelect.width - 220) / 2
                            y: sessionSelect.height
                            width: 220
                            implicitHeight: contentItem.implicitHeight + 8
                            padding: 4
                            contentItem: ListView {
                                clip: true
                                implicitHeight: contentHeight
                                model: sessionSelect.popup.visible ? sessionSelect.delegateModel : null
                                currentIndex: sessionSelect.highlightedIndex
                            }
                            background: Rectangle {
                                radius: 10
                                color: theme.cSurfaceTint
                                border.width: 1
                                border.color: theme.outlineSoft
                            }
                        }
                    }
                }
            }

            // Host name (only reserves space when actually set).
            Text {
                Layout.alignment: Qt.AlignHCenter
                visible: text !== ""
                text: sddm.hostName
                color: root.colText
                opacity: 0.5
                font.family: root.labelFont
                font.pixelSize: 11
            }
        }
    }

    // ── Power pill: its own frosted form below the main form (candylock
    //    layout — the login area and the power pill each sit in their own
    //    glass, so the main form stays evenly framed). ──────────────────
    Rectangle {
        id: pillBlur
        x: powerPill.x
        y: powerPill.y
        width: powerPill.width
        height: powerPill.height
        radius: 99
        color: "transparent"
        clip: true

        Image {
            x: -powerPill.x
            y: -powerPill.y
            width: root.width
            height: root.height
            source: root.bgSrc
            fillMode: Image.PreserveAspectCrop
            smooth: true
            cache: false
            visible: status === Image.Ready
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: root.blurAmt
                blurMax: 64
            }
        }
    }

    Rectangle {
        id: powerPill
        width: pwrRow.implicitWidth + 16
        height: 56
        radius: 99
        x: root.width * root.cardPos - width / 2 + cardShake.offset
        y: form.y + form.height + 16
        color: theme.formGlass
        border.width: 1
        border.color: theme.outlineSoft

        Row {
            id: pwrRow
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: [
                    { icon: "\u{F04B2}", what: "suspend",   can: sddm.canSuspend,   c: theme.cSurfaceTint },
                    { icon: "\u{F0904}", what: "hibernate", can: sddm.canHibernate, c: theme.cWc11 },
                    { icon: "\u{F0459}", what: "reboot",    can: sddm.canReboot,    c: theme.cWc11 },
                    { icon: "\u{F0425}", what: "powerOff",  can: sddm.canPowerOff,  c: theme.cSurfaceTint }
                ]
                delegate: Item {
                    required property var modelData
                    visible: modelData.can
                    width: 44; height: 44
                    Rectangle {
                        anchors { fill: parent; topMargin: 2; bottomMargin: 2 }
                        radius: 99
                        color: pwrHov.containsMouse ? theme.cOnSecondary : theme.pillBtn
                        border.width: 1
                        border.color: pwrHov.containsMouse
                            ? Qt.rgba(modelData.c.r, modelData.c.g, modelData.c.b, 0.65)
                            : "transparent"
                        Behavior on color { ColorAnimation { duration: 130 } }
                        Behavior on border.color { ColorAnimation { duration: 130 } }
                    }
                    Text {
                        anchors.centerIn: parent
                        text: modelData.icon
                        font.family: root.iconFont
                        font.pixelSize: 18
                        color: modelData.c
                    }
                    MouseArea {
                        id: pwrHov
                        anchors.fill: parent; hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (modelData.what === "suspend") sddm.suspend()
                            else if (modelData.what === "hibernate") sddm.hibernate()
                            else if (modelData.what === "reboot") sddm.reboot()
                            else sddm.powerOff()
                        }
                    }
                }
            }
        }
    }

    // ── User selection popup (for multiple users) ───────────────────────
    Popup {
        id: userPopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: 240
        padding: 4
        contentItem: ListView {
            clip: true
            implicitHeight: contentHeight
            model: userModel
            delegate: ItemDelegate {
                id: udel
                required property int index
                required property string name
                width: ListView.view ? ListView.view.width : 200
                contentItem: Text {
                    text: udel.name
                    color: udel.highlighted ? theme.cOnPrimary : root.colText
                    font.family: root.labelFont
                    font.pixelSize: 13
                }
                highlighted: udel.index === root.userIndex
                background: Rectangle { color: udel.highlighted ? theme.cPrimary : "transparent" }
                onClicked: { root.userIndex = udel.index; userPopup.close() }
            }
        }
        background: Rectangle {
            radius: 12
            color: theme.innerCard
            border.width: 1
            border.color: theme.outlineSoft
        }
    }

    // ── Clock ───────────────────────────────────────────────────────────
    QtObject {
        id: clockTimer
        property string clockHour: ""
        property string clockMin: ""
        property string dateText: ""
        property int sec: 0
        function refresh() {
            const now = new Date()
            clockHour = Qt.formatTime(now, "hh")
            clockMin = Qt.formatTime(now, "mm")
            sec = now.getSeconds()
            dateText = Qt.formatDate(now, config.DateFormat && config.DateFormat !== "" ? config.DateFormat : "dddd, d MMMM")
        }
        Component.onCompleted: refresh()
    }
    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: clockTimer.refresh()
    }

    Component.onCompleted: {
        if (config.ForcePasswordFocus === "true")
            pwdField.forceActiveFocus()
    }
}
