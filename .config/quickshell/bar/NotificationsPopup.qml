pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ═══════════════════════════════════════════════════════════════════════════
//  NotificationsPopup — toast window + history panel
//  Reads Config directly. Uses NotificationsState singleton for all data/logic.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: notifRoot
    visible: NotificationsState.historyVisible || NotificationsState.notifications.length > 0

    // ═══════════════════════════════════════════════════════════════════
    //  TOAST WINDOW
    // ═══════════════════════════════════════════════════════════════════
    PanelWindow {
        id: toastWindow
        visible: NotificationsState.notifications.length > 0
        WlrLayershell.namespace: "quickshell:notifications:toasts"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: {
            for (let i = 0; i < NotificationsState.notifications.length; i++)
                if (NotificationsState.notifications[i].isPrompt &&
                    NotificationsState.notifications[i].promptType === "pair_pin")
                    return WlrKeyboardFocus.OnDemand
            return WlrKeyboardFocus.None
        }
        readonly property bool  _barAtBottom: Config.barPosition === "bottom"
        readonly property real  _panelMargin: Config.outerMarginSide * 2
        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true }
        margins {
            top:    _barAtBottom ? 6 : (Config.barHeight + Config.outerMarginTop + 6)
            bottom: _barAtBottom ? (Config.barHeight + Config.outerMarginBottom + 6) : 6
            left:   _panelMargin
        }
        implicitWidth:  364
        implicitHeight: toastCol.implicitHeight + 4
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        Column {
            id: toastCol
            anchors { top: parent.top; left: parent.left; right: parent.right }
            spacing: 6
            Repeater {
                model: NotificationsState.notifications
                delegate: Item {
                    required property var modelData
                    required property int index
                    readonly property var notif: modelData
                    property bool _hov: toastMA.containsMouse
                    property real _radius: 14
                    property real _p: 0
                    property real _swipeX: 0
                    property bool _dismissing: false
                    property bool _swipeLock: false

                    height: cardInner.implicitHeight + 24 + (progTrackItem.visible ? 4 : 0)
                    width: toastCol.width
                    x: _swipeX
                    opacity: _p * (1.0 - Math.min(Math.abs(_swipeX) / 160, 0.55))
                    NumberAnimation on _p { from:0; to:1; duration:200; easing.type:Easing.OutCubic; running:true }
                    Behavior on _swipeX {
                        enabled: !_swipeLock
                        NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                    }

                    function _commitDismiss() {
                        if (_dismissing) return
                        _dismissing = true
                        _swipeX = (_swipeX >= 0 ? 1 : -1) * (width + 40)
                        Qt.callLater(function() { NotificationsState.dismissNotification(notif.id) })
                    }
                    function _endSwipe() {
                        _swipeLock = false
                        if (_dismissing) return
                        if (Math.abs(_swipeX) >= width * 0.35) _commitDismiss()
                        else _swipeX = 0
                    }
                    Timer { id: toastSwipeIdle; interval:200; repeat:false; onTriggered: _endSwipe() }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled:true; maskSource:toastRoundMask
                        maskThresholdMin:0.5; maskSpreadAtMin:1.0
                    }
                    Rectangle {
                        id: toastRoundMask; anchors.fill:parent; radius:parent._radius
                        color:"white"; opacity:0; layer.enabled:true
                    }

                    // Blurred backdrop
                    Item {
                        anchors.fill:parent; layer.enabled:true
                        layer.effect: MultiEffect { blurEnabled:true; blur:1.0; blurMax:48 }
                        Rectangle {
                            x:-parent.x; y:-parent.y; width:toastWindow.width; height:toastWindow.height
                            color: Qt.rgba(Theme.cSurfMid.r, Theme.cSurfMid.g, Theme.cSurfMid.b, 0.72)
                        }
                    }

                    // Card surface
                    Rectangle {
                        anchors.fill:parent; radius:parent._radius
                        color: _hov ? Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.55)
                            : Qt.rgba(Theme.cSurfMid.r,Theme.cSurfMid.g,Theme.cSurfMid.b,0.45)
                        border.width:1
                        border.color: notif.urgency>=2 ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.6)
                            : notif.category==="bt" ? Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.5)
                            : Qt.rgba(Theme.cOutVar.r,Theme.cOutVar.g,Theme.cOutVar.b,0.38)
                        Behavior on color { ColorAnimation { duration:100 } }
                    }

                    // Urgency accent bar
                    Rectangle { x:0;y:0;width:6; height:parent.height-parent._radius
                        color: notif.urgency>=2?Theme.cErr : notif.category==="bt"?Theme.cPrimary
                            : notif.category==="media.playing"?Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,1)
                            : Qt.rgba(Theme.cOutVar.r,Theme.cOutVar.g,Theme.cOutVar.b,1) }
                    Rectangle { x:0;width:6;radius:3; y:parent.height-parent._radius*2; height:parent._radius*2
                        color: notif.urgency>=2?Theme.cErr : notif.category==="bt"?Theme.cPrimary
                            : notif.category==="media.playing"?Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,1)
                            : Qt.rgba(Theme.cOutVar.r,Theme.cOutVar.g,Theme.cOutVar.b,1) }

                    // Progress bar
                    Item {
                        id: progTrackItem
                        visible: !notif.isPrompt && notif.urgency<2
                        anchors { bottom:parent.bottom; left:parent.left; right:parent.right }
                        height: 3; clip: true
                        property real _age: 0
                        Rectangle {
                            anchors.fill:parent; radius:parent.parent._radius
                            color:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.22)
                            Timer { interval:80; repeat:true; running:progTrackItem.visible
                                onTriggered: progTrackItem._age=Math.min(1,(Date.now()-notif.timestamp)/5000) }
                            Rectangle { anchors{left:parent.left;top:parent.top;bottom:parent.bottom}
                                width:parent.width*Math.max(0,1-progTrackItem._age); color:Theme.cPrimary; radius:parent.radius
                                Behavior on width { NumberAnimation { duration:80 } } }
                        }
                    }

                    // Content
                    ColumnLayout {
                        id: cardInner
                        anchors { left:parent.left; right:parent.right; top:parent.top; leftMargin:14; rightMargin:10; topMargin:12 }
                        spacing: 6

                        // Header row
                        RowLayout { Layout.fillWidth:true; spacing:10
                            Item {
                                width: notif.category==="media.playing" ? 48 : 34
                                height: notif.category==="media.playing" ? 48 : 34
                                Rectangle { anchors.fill:parent; radius: notif.category==="media.playing" ? width/2 : 9
                                    color: notif.urgency>=2 ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.18)
                                        : Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.15) }
                                // Icon image
                                Item { id:toastIcImgWrap
                                    anchors { fill:parent; margins: notif.category==="media.playing" ? 0 : 4 }
                                    visible: toastIcImg.status===Image.Ready
                                    layer.enabled: notif.category==="media.playing"
                                    layer.effect: MultiEffect { maskEnabled:true; maskSource:toastArtMask; maskThresholdMin:0.5; maskSpreadAtMin:1.0 }
                                    Rectangle { id:toastArtMask; anchors.fill:parent; radius:width/2; color:"white"; opacity:0; layer.enabled:true }
                                    Image { id:toastIcImg; anchors.fill:parent
                                        source: notif.iconPath ? "file://"+notif.iconPath : ""
                                        fillMode:Image.PreserveAspectCrop; smooth:true; mipmap:true } }
                                // Fallback glyph
                                Text { anchors.centerIn:parent; visible:!toastIcImg.visible
                                    text: NotificationsState.iconGlyph(notif)
                                    font.pixelSize: notif.category==="media.playing" ? 22 : 17
                                    font.family: Config.fontFamily
                                    color: notif.urgency>=2 ? Theme.cErr : Theme.cPrimary }
                                // Count badge
                                Rectangle { visible:(notif.count||1)>1
                                    anchors{right:parent.right;top:parent.top;rightMargin:-2;topMargin:-2}
                                    width:16;height:16;radius:8;color:Theme.cPrimary
                                    Text { anchors.centerIn:parent; text:notif.count||1; font.pixelSize:9; color:Theme.cOnPrimary; font.weight:Font.Bold } }
                            }
                            ColumnLayout { Layout.fillWidth:true; spacing:1
                                Text { Layout.fillWidth:true; text:notif.summary||notif.appName||"Notification"
                                    color:Theme.cOnSurf; font.pixelSize:12; font.weight:Font.Medium; elide:Text.ElideRight }
                                Text { visible:notif.appName!=="" && notif.summary!==""; text:notif.appName
                                    color:Theme.cOnSurfVar; font.pixelSize:9; opacity:0.75 }
                            }
                            Rectangle { width:22;height:22;radius:6
                                color:dH.containsMouse ? Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.9) : "transparent"
                                Behavior on color { ColorAnimation{duration:80} }
                                Text { anchors.centerIn:parent; text:"×"; font.pixelSize:11; color:Theme.cOnSurfVar }
                                MouseArea { id:dH; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                    onClicked: NotificationsState.dismissNotification(notif.id) }
                            }
                        }

                        // Body
                        Text { visible:(notif.body||"")!==""; Layout.fillWidth:true
                            text:notif.body||""; color:Theme.cOnSurfVar; font.pixelSize:11
                            wrapMode:Text.WordWrap; maximumLineCount:4; leftPadding:44 }

                        // Thumbnail for file-path icons
                        Image { id:toastThumb
                            property bool _isFp: (notif.icon||"").startsWith("/")||(notif.icon||"").startsWith("file://")
                            visible: _isFp && notif.category!=="media.playing" && !notif.isPrompt && status===Image.Ready
                            Layout.fillWidth:true; Layout.preferredHeight:Math.min(implicitHeight,180)
                            source: notif.iconPath?"file://"+notif.iconPath:""
                            fillMode:Image.PreserveAspectFit; smooth:true; mipmap:true
                            layer.enabled:true
                            layer.effect: MultiEffect { maskEnabled:true; maskSource:thumbMask; maskThresholdMin:0.5; maskSpreadAtMin:1.0 }
                            Rectangle { id:thumbMask; anchors.fill:parent; radius:8; color:"white"; opacity:0; layer.enabled:true }
                        }

                        // BT Pair Confirm
                        ColumnLayout { visible:notif.isPrompt && notif.promptType==="pair_confirm"
                            Layout.fillWidth:true; spacing:8; Layout.leftMargin:44
                            Rectangle { Layout.alignment:Qt.AlignLeft; height:40; radius:10; implicitWidth:pkT.implicitWidth+32
                                color:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.12)
                                border.width:1; border.color:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.5)
                                Text { id:pkT; anchors.centerIn:parent; text:notif.promptPasskey||"------"
                                    color:Theme.cPrimary; font.pixelSize:22; font.weight:Font.Bold; font.letterSpacing:7 } }
                            Text { text:"Confirm this passkey appears on the device"
                                color:Theme.cOnSurfVar; font.pixelSize:10; font.italic:true }
                            RowLayout { spacing:8
                                Rectangle { height:32; implicitWidth:88; radius:8
                                    color:pcA.containsMouse ? Theme.cPrimary : Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.85)
                                    Behavior on color { ColorAnimation{duration:100} }
                                    Text { anchors.centerIn:parent; text:"󰄬  Accept"; color:Theme.cOnPrim; font.pixelSize:11
                                        font.family:Config.fontFamily; font.weight:Font.Medium }
                                    MouseArea { id:pcA; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                        onClicked: {
                                            NotificationsState.btAgentSend("accept_pair "+notif.promptMac)
                                            NotificationsState.dismissNotification(notif.id)
                                            NotificationsState.addNotification({summary:"Bluetooth",body:"Paired with "+notif.promptName,icon:"bluetooth",urgency:1,category:"bt"})
                                        } } }
                                Rectangle { height:32; implicitWidth:80; radius:8
                                    color:pcR.containsMouse ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.85) : Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.15)
                                    border.width:1; border.color:Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.5)
                                    Behavior on color { ColorAnimation{duration:100} }
                                    Text { anchors.centerIn:parent; text:"×  Reject"; color:pcR.containsMouse?Theme.cOnPrim:Theme.cErr; font.pixelSize:11 }
                                    MouseArea { id:pcR; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                        onClicked: {
                                            NotificationsState.btAgentSend("reject_pair "+notif.promptMac)
                                            NotificationsState.dismissNotification(notif.id)
                                        } } } } }

                        // BT Authorize
                        RowLayout { visible:notif.isPrompt && notif.promptType==="pair_authorize"
                            Layout.fillWidth:true; spacing:8; Layout.leftMargin:44
                            Rectangle { height:32; implicitWidth:80; radius:8
                                color:paA.containsMouse ? Theme.cPrimary : Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.85)
                                Behavior on color { ColorAnimation{duration:100} }
                                Text { anchors.centerIn:parent; text:"󰄬  Pair"; color:Theme.cOnPrim; font.pixelSize:11
                                    font.family:Config.fontFamily; font.weight:Font.Medium }
                                MouseArea { id:paA; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                    onClicked: {
                                        NotificationsState.btAgentSend("accept_pair "+notif.promptMac)
                                        NotificationsState.dismissNotification(notif.id)
                                        NotificationsState.addNotification({summary:"Bluetooth",body:"Paired with "+notif.promptName,icon:"bluetooth",urgency:1,category:"bt"})
                                    } } }
                            Rectangle { height:32; implicitWidth:80; radius:8
                                color:paR.containsMouse ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.85) : Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.15)
                                border.width:1; border.color:Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.5)
                                Behavior on color { ColorAnimation{duration:100} }
                                Text { anchors.centerIn:parent; text:"Reject"; color:paR.containsMouse?Theme.cOnPrim:Theme.cErr; font.pixelSize:11 }
                                MouseArea { id:paR; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                    onClicked: {
                                        NotificationsState.btAgentSend("reject_pair "+notif.promptMac)
                                        NotificationsState.dismissNotification(notif.id)
                                    } } } }

                        // BT PIN
                        ColumnLayout { visible:notif.isPrompt && notif.promptType==="pair_pin"
                            Layout.fillWidth:true; spacing:8; Layout.leftMargin:44
                            RowLayout { spacing:8
                                Rectangle { height:34; Layout.preferredWidth:160; radius:8
                                    color:Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.8)
                                    border.width:1
                                    border.color:pinIn.activeFocus?Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.7):Qt.rgba(Theme.cOutVar.r,Theme.cOutVar.g,Theme.cOutVar.b,0.5)
                                    TextInput {
                                        id:pinIn
                                        anchors{fill:parent;margins:8}
                                        color:Theme.cOnSurf
                                        font.pixelSize:15
                                        font.letterSpacing:4
                                        inputMethodHints:Qt.ImhDigitsOnly
                                        onAccepted: { if(text.length>0){NotificationsState.btAgentSend("pin_pair "+notif.promptMac+" "+text);NotificationsState.dismissNotification(notif.id)} } }
                                    Text { anchors.centerIn:pinIn; text:"PIN"; color:Qt.rgba(Theme.cOnSurfVar.r,Theme.cOnSurfVar.g,Theme.cOnSurfVar.b,0.45); font.pixelSize:13
                                        visible:pinIn.text.length===0 && !pinIn.activeFocus }
                                    Component.onCompleted: pinIn.forceActiveFocus() }
                                Rectangle { height:34; width:52; radius:8
                                    color:pOk.containsMouse?Theme.cPrimary:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.85)
                                    Behavior on color{ColorAnimation{duration:100}}
                                    Text { anchors.centerIn:parent; text:"OK"; color:Theme.cOnPrim; font.pixelSize:12; font.weight:Font.Bold }
                                    MouseArea { id:pOk; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                        onClicked: { if(pinIn.text.length>0){NotificationsState.btAgentSend("pin_pair "+notif.promptMac+" "+pinIn.text);NotificationsState.dismissNotification(notif.id)} } } }
                                Rectangle { height:34; width:64; radius:8; color:Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.15); border.width:1; border.color:Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.4)
                                    Text { anchors.centerIn:parent; text:"Cancel"; color:Theme.cErr; font.pixelSize:11 }
                                    MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                        onClicked: { NotificationsState.btAgentSend("reject_pair "+notif.promptMac); NotificationsState.dismissNotification(notif.id) } } } } }

                        // File transfer
                        RowLayout { visible:notif.isPrompt && notif.promptType==="file_accept"
                            Layout.fillWidth:true; spacing:8; Layout.leftMargin:44
                            Rectangle { height:32; implicitWidth:100; radius:8
                                color:faA.containsMouse ? Theme.cPrimary : Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.85)
                                Behavior on color{ColorAnimation{duration:100}}
                                Text { anchors.centerIn:parent; text:"󰇚  Accept"; color:Theme.cOnPrim; font.pixelSize:11
                                    font.family:Config.fontFamily; font.weight:Font.Medium }
                                MouseArea { id:faA; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                    onClicked: {
                                        if(!notif) return
                                        var fname = notif.promptFilename || "file"
                                        var fsize = notif.promptSize || ""
                                        var transfer = notif.promptTransfer || ""
                                        var nid = notif.id
                                        NotificationsState.btAgentSend("accept_file "+transfer)
                                        NotificationsState.dismissNotification(nid)
                                        NotificationsState.addNotification({summary:"Receiving file…",body:fname+(fsize?" ("+fsize+")":""),icon:"bluetooth",urgency:1,category:"bt"})
                                    } } }
                            Rectangle { height:32; implicitWidth:80; radius:8
                                color:faR.containsMouse ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.85) : Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.15)
                                border.width:1; border.color:Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.5)
                                Behavior on color{ColorAnimation{duration:100}}
                                Text { anchors.centerIn:parent; text:"Decline"; color:faR.containsMouse?Theme.cOnPrim:Theme.cErr; font.pixelSize:11 }
                                MouseArea { id:faR; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                    onClicked: { if(!notif) return; NotificationsState.btAgentSend("reject_file "+notif.promptTransfer); NotificationsState.dismissNotification(notif.id) } } }
                            Text { visible:(notif.promptSize||"")!==""; text:notif.promptSize||""; color:Theme.cOnSurfVar; font.pixelSize:10 } }

                        // Action buttons
                        Flow { visible:(notif.actions||[]).length>0 && !notif.isPrompt
                            Layout.fillWidth:true; spacing:6; leftPadding:44
                            Repeater { model:notif.actions||[]
                                delegate: Rectangle { required property var modelData
                                    visible: modelData.key!=="default"
                                    height:26; implicitWidth:aLbl.implicitWidth+16; radius:8
                                    color:aH.containsMouse?Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.22):Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.7)
                                    border.width:1; border.color:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.35)
                                    Behavior on color{ColorAnimation{duration:80}}
                                    Text { id:aLbl; anchors.centerIn:parent; text:modelData.label||modelData.key||""; color:Theme.cOnSurf; font.pixelSize:10 }
                                    MouseArea { id:aH; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                        onClicked: { NotificationsState.invokeAction(notif,modelData.key); NotificationsState.dismissNotification(notif.id) } } } } }
                        Item { height:2 }
                    }

                    MouseArea { id:toastMA; anchors.fill:parent; hoverEnabled:true; z:-1
                        acceptedButtons:Qt.LeftButton|Qt.RightButton
                        onClicked:function(e) {
                            if (notif.isPrompt) return
                            if (e.button===Qt.LeftButton) {
                                if ((notif.actions||[]).some(function(a){return a.key==="default"}))
                                    NotificationsState.invokeAction(notif,"default")
                                NotificationsState.dismissNotification(notif.id)
                            } else NotificationsState.dismissNotification(notif.id)
                        }
                    }
                    // Swipe to dismiss
                    WheelHandler {
                        onWheel:function(ev) {
                            if (notif.isPrompt) { ev.accepted=false; return }
                            const px=ev.pixelDelta.x!==0?ev.pixelDelta.x:-(ev.angleDelta.x/8.0)
                            const py=ev.pixelDelta.y!==0?ev.pixelDelta.y:-(ev.angleDelta.y/8.0)
                            const hm=Math.abs(px), vm=Math.abs(py)
                            if (hm<2||vm>hm*0.8) { ev.accepted=false; return }
                            ev.accepted=true; _swipeLock=true
                            _swipeX=Math.max(-width*1.3, Math.min(width*1.3, _swipeX+px))
                            toastSwipeIdle.restart()
                            if (Math.abs(_swipeX)>=width*0.70) _commitDismiss()
                        }
                    }
                }
            }
        }
    }

    // ═══════════════════════════════════════════════════════════════════
    //  HISTORY PANEL
    // ═══════════════════════════════════════════════════════════════════
    PanelWindow {
        id: historyWindow
        visible: NotificationsState.historyVisible
        WlrLayershell.namespace: "quickshell:notifications:history"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        readonly property bool  _barAtBottom: Config.barPosition === "bottom"
        readonly property real  _panelMargin: Config.outerMarginSide * 2
        readonly property real  _panelRadius: Config.barMode === "island" ? Config.islandRadius : Config.barRadius

        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true }
        margins { top: 6; bottom: 6; left: _panelMargin }
        implicitWidth:  380
        implicitHeight: Math.min(histScrollContent.height + histHeader.implicitHeight + histDivider.height + 42, 720)
        color: "transparent"

        Connections {
            target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
            ignoreUnknownSignals: true
            function onAddressChanged() { NotificationsState.historyVisible = false }
        }

        Rectangle {
            id: histPanel
            anchors.fill: parent
            color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.40)
            radius: historyWindow._panelRadius
            border.width: 1; border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.40)
            scale: NotificationsState.historyVisible ? 1.0 : 0.92
            transformOrigin: Item.TopLeft
            Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            Keys.onEscapePressed: NotificationsState.historyVisible = false

            // Header
            RowLayout {
                id: histHeader
                anchors { top:parent.top; left:parent.left; right:parent.right; margins:16 }
                spacing: 8
                Rectangle { id:dndBtn; height:28; width:28; radius:8
                    color:dndBtnMA.containsMouse ? Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.18)
                        : NotificationsState.dndEnabled ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.14) : "transparent"
                    border.width:1; border.color:NotificationsState.dndEnabled ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.50)
                        : Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.40)
                    Behavior on color { ColorAnimation{duration:100} }
                    Text { anchors.centerIn:parent
                        text:NotificationsState._waybarIconGlyph(NotificationsState._waybarIconKey())
                        font.pixelSize:15; font.family:Config.fontFamily
                        color:NotificationsState.dndEnabled ? Theme.cErr : Theme.cPrimary
                        Behavior on color{ColorAnimation{duration:120}} }
                    MouseArea { id:dndBtnMA; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                        onClicked:NotificationsState.dndEnabled=!NotificationsState.dndEnabled } }
                Text { text:NotificationsState.dndEnabled?"Do Not Disturb":"Notifications"
                    color:NotificationsState.dndEnabled?Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.85):Theme.cOnSurf
                    font.pixelSize:14; font.weight:Font.Medium; font.family:Config.fontFamily
                    Layout.fillWidth:true; Behavior on color{ColorAnimation{duration:120}} }
                Rectangle { width:8;height:8;radius:4
                    color:NotificationsState.btAgentReady?Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.9):Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.7) }
                Item { width:2 }
                Rectangle { height:24; implicitWidth:clrLbl.implicitWidth+16; radius:8
                    color:clrH.containsMouse?Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.18):Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.6)
                    border.width:1
                    border.color:clrH.containsMouse?Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.85):Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.55)
                    Behavior on color{ColorAnimation{duration:100}}
                    Behavior on border.color{ColorAnimation{duration:100}}
                    Text { id:clrLbl; anchors.centerIn:parent; text:"Clear all"; color:clrH.containsMouse?Theme.cErr:Theme.cOnSurfVar; font.pixelSize:11
                        Behavior on color{ColorAnimation{duration:100}} }
                    MouseArea { id:clrH; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor; onClicked:NotificationsState.clearHistory() } }
                Rectangle { height:24; width:24; radius:8
                    color:clsH.containsMouse?Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.9):"transparent"
                    Behavior on color{ColorAnimation{duration:100}}
                    Text { anchors.centerIn:parent; text:"×"; font.pixelSize:12; color:Theme.cOnSurfVar }
                    MouseArea { id:clsH; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                        onClicked:NotificationsState.historyVisible=false } }
            }

            Rectangle { id:histDivider
                anchors{top:histHeader.bottom;topMargin:8;left:parent.left;right:parent.right;leftMargin:16;rightMargin:16}
                height:1; color:Qt.rgba(Theme.cOutVar.r,Theme.cOutVar.g,Theme.cOutVar.b,0.3) }

            Flickable {
                id: histFlickable
                anchors{top:histDivider.bottom;topMargin:8;left:parent.left;right:parent.right;bottom:parent.bottom;leftMargin:10;rightMargin:10;bottomMargin:10}
                clip:true; contentHeight:histScrollContent.height
                flickableDirection:Flickable.VerticalFlick; boundsBehavior:Flickable.StopAtBounds
                ColumnLayout {
                    id: histScrollContent
                    width:parent.width; height:implicitHeight; spacing:5
                    Item { visible:NotificationsState.history.length===0; Layout.fillWidth:true; height:44
                        Text { anchors.centerIn:parent; text:"No notifications"; color:Theme.cOnSurfVar; font.pixelSize:12; font.italic:true } }
                    Repeater {
                        model: NotificationsState.history
                        delegate: Rectangle {
                            required property var modelData
                            readonly property var notif: modelData
                            property bool _exp: false
                            property real _swipeX: 0
                            property bool _dismissing: false
                            property bool _swipeLock: false
                            property var _flickable: histFlickable

                            radius:12; Layout.fillWidth:true
                            height:hcBody.implicitHeight+16
                            Layout.preferredHeight:height
                            color:hcMA.containsMouse ? Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.7)
                                : Qt.rgba(Theme.cSurfMid.r,Theme.cSurfMid.g,Theme.cSurfMid.b,0.5)
                            border.width:1
                            border.color:notif.urgency>=2 ? Qt.rgba(Theme.cErr.r,Theme.cErr.g,Theme.cErr.b,0.35)
                                : Qt.rgba(Theme.cOutVar.r,Theme.cOutVar.g,Theme.cOutVar.b,0.25)
                            Behavior on color{ColorAnimation{duration:100}}
                            Behavior on height{NumberAnimation{duration:140;easing.type:Easing.OutCubic}}
                            x:_swipeX; opacity:1.0-Math.min(Math.abs(_swipeX)/160,0.55)
                            Behavior on _swipeX{enabled:!_swipeLock;NumberAnimation{duration:220;easing.type:Easing.OutCubic}}

                            function _commitDismiss() {
                                if(_dismissing)return; _dismissing=true
                                const dir=_swipeX>=0?1:-1; _swipeX=dir*(width+40)
                                Qt.callLater(function(){NotificationsState.history=NotificationsState.history.filter(function(n){return n.id!==notif.id})})
                            }
                            function _endGesture() {
                                _swipeLock=false; _flickable.interactive=true
                                if(_dismissing)return
                                if(Math.abs(_swipeX)>=width*0.35)_commitDismiss(); else _swipeX=0
                            }
                            Timer{id:swipeIdleTimer;interval:200;repeat:false;onTriggered:_endGesture()}
                            WheelHandler{onWheel:function(ev){
                                const px=ev.pixelDelta.x!==0?ev.pixelDelta.x:-(ev.angleDelta.x/8.0)
                                const py=ev.pixelDelta.y!==0?ev.pixelDelta.y:-(ev.angleDelta.y/8.0)
                                const hm=Math.abs(px),vm=Math.abs(py)
                                if(hm<2||vm>hm*0.8){ev.accepted=false;return}
                                ev.accepted=true;_flickable.interactive=false;_swipeLock=true
                                _swipeX=Math.max(-width*1.3,Math.min(width*1.3,_swipeX+px))
                                swipeIdleTimer.restart()
                                if(Math.abs(_swipeX)>=width*0.70)_commitDismiss()
                            }}

                            ColumnLayout { id:hcBody
                                anchors{left:parent.left;right:parent.right;top:parent.top;margins:10}
                                spacing:4
                                RowLayout{Layout.fillWidth:true;spacing:8
                                    Rectangle{width:6;height:6;radius:3;anchors.verticalCenter:parent.verticalCenter
                                        color:notif.urgency>=2?Theme.cErr:notif.category==="bt"?Theme.cPrimary:Qt.rgba(Theme.cOnSurfVar.r,Theme.cOnSurfVar.g,Theme.cOnSurfVar.b,0.5)}
                                    Item{width:20;height:20
                                        Image{id:hcIcImg
                                            anchors{fill:parent;margins:1}
                                            source:{const ic=notif.icon||"";if(ic.startsWith("/")||ic.startsWith("file://"))return"";return notif.iconPath?"file://"+notif.iconPath:""}
                                            fillMode:Image.PreserveAspectFit;smooth:true;visible:status===Image.Ready}
                                        Text{anchors.centerIn:parent;visible:!hcIcImg.visible;text:NotificationsState.iconGlyph(notif);font.pixelSize:12;font.family:Config.fontFamily;color:notif.urgency>=2?Theme.cErr:Theme.cOnSurfVar}
                                    }
                                    ColumnLayout{Layout.fillWidth:true;spacing:0
                                        RowLayout{Text{Layout.fillWidth:true;text:notif.summary||notif.appName||"Notification";color:Theme.cOnSurf;font.pixelSize:11;font.weight:Font.Medium;elide:Text.ElideRight}
                                            Rectangle{visible:(notif.count||1)>1;height:16;implicitWidth:cntT.implicitWidth+10;radius:8;color:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.25);border.width:1;border.color:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.4)
                                                Text{id:cntT;anchors.centerIn:parent;text:"×"+(notif.count||1);font.pixelSize:9;color:Theme.cPrimary}
                                            }
                                        }
                                        Text{visible:notif.appName!==""&&notif.summary!=="";text:notif.appName;color:Theme.cOnSurfVar;font.pixelSize:9;opacity:0.7}
                                    }
                                    Text{text:{const d=new Date(notif.timestamp),now=new Date();const dm=Math.floor((now-d)/60000);if(dm<1)return"now";if(dm<60)return dm+"m";const dh=Math.floor(dm/60);if(dh<24)return dh+"h";return d.toLocaleDateString(undefined,{month:"short",day:"numeric"})}
                                        color:Theme.cOnSurfVar;font.pixelSize:9;opacity:0.65;anchors.verticalCenter:parent.verticalCenter}
                                    Text{visible:(notif.body||"")!==""||((notif.actions||[]).length>0)
                                        text:_exp?"󰅃":"󰅀";font.pixelSize:10;font.family:Config.fontFamily;color:Theme.cOnSurfVar;opacity:0.8;anchors.verticalCenter:parent.verticalCenter
                                        MouseArea{anchors.fill:parent;anchors.margins:-4;cursorShape:Qt.PointingHandCursor;onClicked:_exp=!_exp}}
                                    Rectangle{width:18;height:18;radius:5;color:hcDH.containsMouse?Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.9):"transparent";Behavior on color{ColorAnimation{duration:80}}
                                        Text{anchors.centerIn:parent;text:"×";font.pixelSize:9;color:Theme.cOnSurfVar;opacity:0.7}
                                        MouseArea{id:hcDH;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:NotificationsState.history=NotificationsState.history.filter(function(n){return n.id!==notif.id})}}
                                }
                                ColumnLayout{visible:_exp;Layout.fillWidth:true;spacing:6
                                    Image{id:hcThumb
                                        property bool _isFp:(notif.icon||"").startsWith("/")||(notif.icon||"").startsWith("file://")
                                        visible:_isFp&&notif.category!=="media.playing"&&status===Image.Ready
                                        Layout.fillWidth:true;Layout.preferredHeight:Math.min(implicitHeight,160)
                                        source:notif.iconPath?"file://"+notif.iconPath:"";fillMode:Image.PreserveAspectFit;smooth:true;mipmap:true
                                        layer.enabled:true;layer.effect:MultiEffect{maskEnabled:true;maskSource:hcThumbMask;maskThresholdMin:0.5;maskSpreadAtMin:1.0}
                                        Rectangle{id:hcThumbMask;anchors.fill:parent;radius:6;color:"white";opacity:0;layer.enabled:true}}
                                    Text{visible:(notif.body||"")!=="";Layout.fillWidth:true;text:notif.body||"";color:Theme.cOnSurfVar;font.pixelSize:10;wrapMode:Text.WordWrap;leftPadding:14}
                                    Flow{visible:(notif.actions||[]).length>0;Layout.fillWidth:true;spacing:5;leftPadding:14
                                        Repeater{model:notif.actions||[];delegate:Rectangle{required property var modelData;visible:modelData.key!=="default";height:22;implicitWidth:haL.implicitWidth+12;radius:6
                                            color:haH.containsMouse?Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.22):Qt.rgba(Theme.cSurfHi.r,Theme.cSurfHi.g,Theme.cSurfHi.b,0.7)
                                            border.width:1;border.color:Qt.rgba(Theme.cPrimary.r,Theme.cPrimary.g,Theme.cPrimary.b,0.3);Behavior on color{ColorAnimation{duration:80}}
                                            Text{id:haL;anchors.centerIn:parent;text:modelData.label||modelData.key||"";color:Theme.cOnSurf;font.pixelSize:9}
                                            MouseArea{id:haH;anchors.fill:parent;hoverEnabled:true;cursorShape:Qt.PointingHandCursor;onClicked:NotificationsState.invokeAction(notif,modelData.key)}}}}
                                }
                            }
                            MouseArea{id:hcMA;anchors.fill:parent;hoverEnabled:true;z:-1;propagateComposedEvents:true}
                        }
                    }
                    Item{height:4}
                }
            }
        }
    }
}
