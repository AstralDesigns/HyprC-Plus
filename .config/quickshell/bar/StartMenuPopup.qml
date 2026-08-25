pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ═══════════════════════════════════════════════════════════════════════════
//  StartMenuPopup — start menu / system controls panel for the bar process.
//  Reads Config directly for position, margins, radius.
//  StartMenuState provides all system state (brightness, volume, network, BT).
// ═══════════════════════════════════════════════════════════════════════════

PanelWindow {
    id: startMenuPanel
    // ── Deferred-destroy animation pattern ──────────────────────────────
    property bool _stateVisible: StartMenuState.menuVisible
    Timer { id: _menuExitDelay; interval: 220; repeat: false }
    visible: _stateVisible || _menuExitDelay.running
    on_StateVisibleChanged: { if (!_stateVisible) _menuExitDelay.restart() }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:startmenu"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property bool  _barAtBottom: Config.barPosition === "bottom"
    readonly property real  _panelMargin: Config.barMode === "shell" ? Config.popupSideMargin : Config.popupSideMargin * 2
    readonly property real  _panelRadius: Config.barMode === "island" ? Config.islandRadius : Config.barRadius
    property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop) : Config.outerMarginTop) + Config.barHeight + 4
    property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom) : Config.outerMarginBottom) + Config.barHeight + 4

    anchors {
        top:    !_barAtBottom
        bottom:  _barAtBottom
        left:    true
        right:   true
    }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
        right:  _panelMargin
    }
    implicitHeight: 700
    implicitWidth: 348
    color: "transparent"

    // Click-outside dismiss
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: StartMenuState.menuVisible = false
    }

    Rectangle {
        id: panelRect
        anchors {
            top: !_barAtBottom ? parent.top : undefined
            bottom: _barAtBottom ? parent.bottom : undefined
            right: parent.right
        }
        width: 340
        height: Math.min(mainCol.implicitHeight + 18, 690)
        color: Theme.blurBackground
        //radius: startMenuPanel._panelRadius
        topLeftRadius: 20
        topRightRadius: 20
        bottomLeftRadius: 20
        bottomRightRadius: 20
        focus: true
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)
        opacity: startMenuPanel._stateVisible ? 1.0 : 0.0
        scale: startMenuPanel._stateVisible ? 1.0 : 0.92
        transformOrigin: startMenuPanel._barAtBottom ? Item.BottomRight : Item.TopRight
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Behavior on scale   { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
        Keys.onEscapePressed: StartMenuState.menuVisible = false
        Connections { target: StartMenuState; function onMenuVisibleChanged() { if (StartMenuState.menuVisible) panelRect.forceActiveFocus() } }

        ColumnLayout {
            id: mainCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            spacing: 10
            
            Rectangle {
                Layout.fillWidth: true; height: 88; radius: 12; clip: true
                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.5)
                border.width: 2
        	border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
            	// ── Row 1: user + power ────────────────────────────────────
            	RowLayout { 
            	   anchors {
		        left: parent.left; right: parent.right
			verticalCenter: parent.verticalCenter
			margins: 8
                   }
            	   Layout.fillWidth: true; spacing: 4
                   Rectangle { width: 70; height: 70; radius: 99; color: Theme.cSurfHi
                    	Image { id: smAvatar; anchors.fill: parent; fillMode: Image.PreserveAspectCrop
                            source: StartMenuState._userIconPath ? "file://" + StartMenuState._userIconPath : ""
                            smooth: true; mipmap: true; visible: StartMenuState._userIconPath !== "" }
                    	Text { anchors.centerIn: parent; visible: !smAvatar.visible; text: "󰀄"
                        	font.pixelSize: 20; font.family: Config.fontFamily; color: Theme.cOnSurfVar }
                   }
                    ColumnLayout { Layout.fillWidth: true; spacing: 1
                    	Text { text: Quickshell.env("USER"); color: Theme.cWc6; font.pixelSize: 20; font.family: Config.styleFont; font.weight: Font.Bold; font.italic: true }
                    	Text { text: Qt.formatDate(StartMenuState._now, "ddd d MMM") + " · " + Qt.formatTime(StartMenuState._now, "hh:mm"); color: Theme.cPrimary; font.pixelSize: 13 }
                    }
                    // Recorder
                    Rectangle {
			width: 30; height: 30; radius: 15
			color: StartMenuState.isRecording ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                            : rrh.containsMouse ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.18)
                            : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.6)
			border.width: 1
			border.color: StartMenuState.isRecording ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.85)
                        	: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
			Behavior on color { ColorAnimation { duration: 100 } }
                    	    Rectangle { anchors.fill: parent; radius: parent.radius; visible: StartMenuState.isRecording
                        	gradient: Gradient {
                            	orientation: Gradient.Horizontal
                            	GradientStop { position: 0.0; color: Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.85) }
                            	GradientStop { position: 1.0; color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.70) }
                        	}
                    	    }
                            Text { anchors.centerIn: parent; text: "󰑋"; font.pixelSize: 15; font.family: Config.fontFamily
                        	color: StartMenuState.isRecording ? Theme.cOnPrim : Theme.cOnSurfVar
                        	Behavior on color { ColorAnimation { duration: 100 } }
                        	SequentialAnimation on opacity { running: StartMenuState.isRecording; loops: Animation.Infinite
                            	NumberAnimation { to: 0.3; duration: 500 }
                            	NumberAnimation { to: 1.0; duration: 500 }
                        	}
                    	    }
                    	    MouseArea { id: rrh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        	onClicked: StartMenuState.toggleRecorder() }
                     }
                     // Screenshot
                     Rectangle {
                    	width: 30; height: 30; radius: 15
                    	color: ssh.containsMouse ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.18)
                        		: Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.6)
                    	border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                    	Behavior on color { ColorAnimation { duration: 100 } }
                    	Text { anchors.centerIn: parent; text: "󰹑"; font.pixelSize: 15; font.family: Config.fontFamily; color: Theme.cOnSurfVar }
                    	MouseArea { id: ssh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        	onClicked: { StartMenuState.close(); ScreenshotPopupState.toggle() } }
                    }
            	}
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16) }

            // ── Brightness ────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true; height: 25; radius: 99; clip: true
                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.5)
                border.width: 1
        	border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
            	RowLayout { Layout.fillWidth: true; spacing: 10
                	Text { text: " 󰃟"; font.pixelSize: 17; font.family: Config.fontFamily; color: Theme.cWc5 }
                	//Text { text: "Brightness"; color: Theme.cPrimary; font.pixelSize: 11; Layout.preferredWidth: 72 }
                	SliderBg {
                    		Layout.fillWidth: true; Layout.fillHeight: true; width: 218; height: 20
                    		value: StartMenuState.backlightValue
                    		onMoved: function(v) { StartMenuState.backlightValue = v; StartMenuState.setBacklight(v) }
                    		gradA: Theme.cInversePrimary; gradB: Theme.cOnSecondary; track: Theme.cScrim
                	}
                	Text { text: Math.round(StartMenuState.backlightValue * 100) + "%"; color: Theme.cPrimary
                    		font.pixelSize: 12; Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight }
                }
            }

            // ── Volume ────────────────────────────────────────────────
            Rectangle {
                    Layout.fillWidth: true; height: 25; radius: 99; clip: true
                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.5)
                    border.width: 1
        	    border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
                    RowLayout { Layout.fillWidth: true; spacing: 10
                	Text {
                        	text: StartMenuState.volumeMuted ? " 󰖁" : " 󰕾";font.pixelSize: 17; font.family: Config.fontFamily; color: Theme.cWc5
                        	MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: StartMenuState.toggleMute() }
                	}
                
                	//Text { text: "Volume"; color: Theme.cPrimary; font.pixelSize: 11; Layout.preferredWidth: 72 }
                	SliderBg {
                    		Layout.fillWidth: true; Layout.fillHeight: true; width: 218; height: 20
                    		value: StartMenuState.volumeValue
                    		onMoved: function(v) { StartMenuState.volumeValue = v; StartMenuState.setVolume(v) }
                    		gradA: Theme.cInversePrimary; gradB: Theme.cOnSecondary; track: Theme.cScrim
                	}
                	Text { text: Math.round(StartMenuState.volumeValue * 100) + "%"; color: Theme.cPrimary
                    	font.pixelSize: 12; Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight }
              	  }
            }

            // ── Microphone (only while something is actually recording) ─
            Rectangle {
                    Layout.fillWidth: true; height: 25; radius: 99; clip: true
                    visible: StartMenuState.micActive
                    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.5)
                    border.width: 1
        	    border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.85)
                    RowLayout { Layout.fillWidth: true; spacing: 10
                	Text {
                        	text: StartMenuState.micMuted ? " 󰍭" : " 󰍬"; font.pixelSize: 17; font.family: Config.fontFamily; color: Theme.cWc5
                        	MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: StartMenuState.toggleMicMute() }
                	}
                	SliderBg {
                    		Layout.fillWidth: true; Layout.fillHeight: true; width: 218; height: 20
                    		value: StartMenuState.micValue
                    		onMoved: function(v) { StartMenuState.micValue = v; StartMenuState.setMic(v) }
                    		gradA: Theme.cInversePrimary; gradB: Theme.cOnSecondary; track: Theme.cScrim
                	}
                	Text { text: Math.round(StartMenuState.micValue * 100) + "%"; color: Theme.cPrimary
                    	font.pixelSize: 12; Layout.preferredWidth: 30; horizontalAlignment: Text.AlignRight }
              	  }
            }

            // ── Night light ──────────────────────────────────────────────
            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16) }

            RowLayout {
                Layout.fillWidth: true; height: 25; spacing: 10
                Text {
                	text: " 󰖔"; font.pixelSize: 17; font.family: Config.fontFamily; color: Theme.cWc6
                }
                Text {
                	text: "Night light"; color: Theme.cPrimary; font.family: Config.labelFont; font.pixelSize: 12
                	Layout.fillWidth: true
                }
                // iOS-style pill toggle
                Rectangle {
                    	id: _nlPill
                    	width: 40; height: 22; radius: 11
                    	color: StartMenuState.nightLightOn
                        	? Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.82)
                        	: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.15)
                    	border.width: 1
                    	border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.6)
                    	Behavior on color { ColorAnimation { duration: 150 } }

                    	Rectangle {
                        	width: 16; height: 16; radius: 8
                        	color: StartMenuState.nightLightOn ? Theme.cWc6 : Theme.cWc5
                        	anchors.verticalCenter: parent.verticalCenter
                        	x: StartMenuState.nightLightOn ? parent.width - width - 3 : 3
                        	Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                        	Behavior on color { ColorAnimation { duration: 150 } }
                    	}

                    	MouseArea {
                        	anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        	onClicked: StartMenuState.toggleNightLight()
                    	}
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16) }

            // ── Network + Bluetooth ────────────────────────────────────
            ColumnLayout { Layout.fillWidth: true; spacing: 4
                // Header row
                RowLayout { Layout.fillWidth: true; spacing: 8
                    // Network icon — wifi: borderless toggle like BT; ethernet/none: static glyph
                    Text {
                        font.pixelSize: 15; font.family: Config.fontFamily
                        text: !StartMenuState.netIsWifi && !StartMenuState.netIsEthernet ? "󰤭"
                            : StartMenuState.netIsEthernet ? "󰈀"
                            : StartMenuState.netRadioEnabled ? "󰤨" : "󰤮"
                        color: StartMenuState.netIsWifi
                            ? (StartMenuState.netRadioEnabled ? Theme.cWc6 : Theme.cOnSurf)
                            : (StartMenuState.networkStatus === "connected" ? Qt.rgba(Theme.cPrimaryContainer.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00) : Theme.cOnSurf)
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea {
                            anchors.fill: parent; hoverEnabled: true
                            cursorShape: StartMenuState.netIsWifi ? Qt.PointingHandCursor : Qt.ArrowCursor
                            enabled: StartMenuState.netIsWifi
                            onClicked: StartMenuState.toggleNetRadio()
                        }
                    }
                    // Status text only — SSID is visible in the list with its own indicators
                    Text {
                        Layout.fillWidth: true
                        text: StartMenuState.networkStatus || (StartMenuState.netRadioEnabled ? "No network" : "Wi-Fi off")
                        color: Theme.cOnSurf; font.pixelSize: 11; opacity: 0.75
                        elide: Text.ElideRight
                    }
                    // Rescan button — triggers nmcli dev wifi rescan then refreshes list.
                    // Only visible while the Wi-Fi section is expanded.
                    Rectangle {
                        width: 24; height: 24; radius: 6
                        visible: StartMenuState.networkExpanded
                        color: rescanH.containsMouse
                            ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65) : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.35)
                        border.width: 1
                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b,
                                              StartMenuState.netScanProcRunning ? 0.25 : 0.50)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text {
                            anchors.centerIn: parent
                            text: "󰑐"
                            font.pixelSize: 13; font.family: Config.fontFamily
                            color: StartMenuState.netScanProcRunning ? Theme.cOnSurfVar : Theme.cPrimary
                            Behavior on color { ColorAnimation { duration: 120 } }
                            RotationAnimator on rotation {
                                running: StartMenuState.netScanProcRunning
                                from: 0; to: 360; duration: 900; loops: Animation.Infinite
                            }
                        }
                        MouseArea {
                            id: rescanH; anchors.fill: parent; hoverEnabled: true
                            cursorShape: StartMenuState.netScanProcRunning ? Qt.ArrowCursor : Qt.PointingHandCursor
                            enabled: !StartMenuState.netScanProcRunning
                            onClicked: {
                                StartMenuState.startNetScan()
                            }
                        }
                    }
                    // Advanced network settings — launches nm-connection-editor.
                    // Always visible, like the expand/minimize toggle.
                    Rectangle {
                        width: 24; height: 24; radius: 6
                        color: netSettingsH.containsMouse ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65) : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.35)
                        border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: "󰒓"
                            font.pixelSize: 13; font.family: Config.fontFamily; color: Theme.cWc5 }
                        MouseArea { id: netSettingsH; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached(["nm-connection-editor"])
                        }
                    }
                    // Expand/minimize the Wi-Fi network list — always visible,
                    // always the last control before the BT separator.
                    Rectangle {
                        width: 24; height: 24; radius: 6
                        color: nxh.containsMouse ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65) : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.35)
                        border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: StartMenuState.networkExpanded ? "󰁆" : "󰁄"
                            font.pixelSize: 13; font.family: Config.fontFamily; color: Theme.cWc5 }
                        MouseArea { id: nxh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                StartMenuState.networkExpanded = !StartMenuState.networkExpanded
                                if (StartMenuState.networkExpanded) StartMenuState.startNetScan()
                            }
                        }
                    }
                    Rectangle { width: 1; height: 20; color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.4) }
                    Text {
                        font.pixelSize: 15; font.family: Config.fontFamily
                        text: StartMenuState.btPowered ? "󰂱" : "󰂲"
                        color: StartMenuState.btPowered ? Theme.cWc6 : Theme.cOnSurf
                        Behavior on color { ColorAnimation { duration: 150 } }
                        MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: StartMenuState.toggleBtPower() }
                    }
                    Rectangle {
                        width: 24; height: 24; radius: 6
                        color: bxh.containsMouse ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65) : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.35)
                        border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.55)
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text { anchors.centerIn: parent; text: StartMenuState.btExpanded ? "󰁆" : "󰁄"
                            font.pixelSize: 13; font.family: Config.fontFamily; color: Theme.cWc5 }
                        MouseArea { id: bxh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                StartMenuState.btExpanded = !StartMenuState.btExpanded
                                if (StartMenuState.btExpanded) StartMenuState.startBtStatus()
                            }
                        }
                    }
                }

                // Wifi network list — caps at 3 rows when both net & BT are expanded, 6 rows when alone,
                // then becomes scrollable with a minimal scrollbar.
                Item {
                    id: netListWrap
                    Layout.fillWidth: true
                    clip: true
                    // 34px row + 2px spacing per entry; cap at 3 rows when both expanded, else 6.
                    readonly property real _rowH: 36
                    readonly property int  _maxRows: (StartMenuState.networkExpanded && StartMenuState.btExpanded) ? 3 : 6
                    readonly property real _maxHeight: _rowH * _maxRows
                    readonly property real _targetH: StartMenuState.networkExpanded ? Math.min(netListCol.implicitHeight, _maxHeight) : 0
                    property real _animH: 0
                    Binding on _animH { value: netListWrap._targetH }
                    Behavior on _animH { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    implicitHeight: _animH
                    Layout.preferredHeight: _animH
                    height: _animH
                    visible: _animH > 0.5 || StartMenuState.networkExpanded
                    opacity: Math.min(1.0, _targetH > 0 ? (_animH / _targetH) : 0.0)

                    Flickable {
                        id: netListFlick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: netListCol.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {
                            policy: (StartMenuState.networkList && StartMenuState.networkList.length > netListWrap._maxRows) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                            visible: (StartMenuState.networkList && StartMenuState.networkList.length > netListWrap._maxRows) && size < 1.0
                            contentItem: Rectangle {
                                implicitWidth: 3
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                                radius: 2
                            }
                            background: Rectangle { color: "transparent" }
                        }

                        Column {
                            id: netListCol
                            width: netListFlick.width; spacing: 2

                    Repeater {
                        model: StartMenuState.networkList
                        delegate: Column {
                            id: netDelegate
                            required property var modelData
                            // _showPass is derived from State so it survives networkList refreshes.
                            readonly property bool _showPass:
                                StartMenuState.netPasswordSSID === modelData.ssid
                            width: parent.width; spacing: 2

                            Rectangle {
                                id: netRow
                                width: parent.width; height: 34; radius: 8
                                color: rowHover.containsMouse
                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.10)
                                    : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.5)
                                Behavior on color { ColorAnimation { duration: 100 } }
                                border.width: netDelegate.modelData.active ? 1 : 0
                                border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.5)

                                MouseArea {
                                    id: rowHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: netDelegate.modelData.active
                                        ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: function(mouse) {
                                        if (netDelegate.modelData.active) return
                                        if (StartMenuState.netConnecting_ &&
                                            StartMenuState.netConnectTarget === netDelegate.modelData.ssid) return
                                        if (netDelegate.modelData.saved || !netDelegate.modelData.secure)
                                            StartMenuState.connectNetwork(netDelegate.modelData.ssid, "")
                                        else
                                            StartMenuState.netPasswordSSID =
                                                netDelegate._showPass ? "" : netDelegate.modelData.ssid
                                    }
                                }

                                // Inline row: signal + SSID + indicators + action buttons
                                RowLayout {
                                    anchors {
                                        left: parent.left; right: parent.right
                                        verticalCenter: parent.verticalCenter
                                        leftMargin: 8; rightMargin: 6
                                    }
                                    spacing: 6

                                    Text {
                                        text: netDelegate.modelData.isEthernet ? "󰈀"
                                            : netDelegate.modelData.signal > 70 ? "󰤨"
                                            : netDelegate.modelData.signal > 40 ? "󰤥"
                                            : netDelegate.modelData.signal > 20 ? "󰤢" : "󰤟"
                                        font.pixelSize: 12; font.family: Config.fontFamily
                                        color: netDelegate.modelData.active ? Theme.cWc4 : Theme.cOnSurfVar
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: netDelegate.modelData.ssid
                                        color: netDelegate.modelData.active ? Theme.cPrimary : Theme.cOnSurf
                                        font.pixelSize: 11; font.weight: netDelegate.modelData.active ? Font.Medium : Font.Normal
                                        elide: Text.ElideRight
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                    // Lock icon (secured + not active)
                                    Text {
                                        text: "󰒃"; font.pixelSize: 10; font.family: Config.fontFamily
                                        color: Theme.cOnSurfVar; opacity: 0.5
                                        visible: netDelegate.modelData.secure && !netDelegate.modelData.active
                                    }
                                    // Connecting spinner
                                    Text {
                                        text: "󰒖"; font.pixelSize: 11; font.family: Config.fontFamily
                                        color: Theme.cPrimary
                                        visible: StartMenuState.netConnecting_ &&
                                                 StartMenuState.netConnectTarget === netDelegate.modelData.ssid
                                        RotationAnimator on rotation {
                                            from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                            running: StartMenuState.netConnecting_ &&
                                                     StartMenuState.netConnectTarget === netDelegate.modelData.ssid
                                        }
                                    }
                                    // Just-connected checkmark
                                    Text {
                                        text: "󰄬"; font.pixelSize: 12; font.family: Config.fontFamily
                                        color: Theme.cPrimary
                                        visible: StartMenuState.netConnectedSSID === netDelegate.modelData.ssid
                                        opacity: StartMenuState.netConnectedSSID === netDelegate.modelData.ssid ? 1.0 : 0.0
                                        Behavior on opacity { NumberAnimation { duration: 400 } }
                                    }
                                    // Disconnect — active network only
                                    Rectangle {
                                        visible: netDelegate.modelData.active
                                        height: 20; radius: 5
                                        implicitWidth: visible ? dcLbl.implicitWidth + 14 : 0
                                        color: dcMA.containsMouse
                                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.18)
                                            : "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b,
                                                              dcMA.containsMouse ? 0.55 : 0.28)
                                        Behavior on color        { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }
                                        Text {
                                            id: dcLbl; anchors.centerIn: parent
                                            text: "Disconnect"; font.pixelSize: 9
                                            font.family: Config.labelFont
                                            color: dcMA.containsMouse ? Theme.cPrimary : Theme.cOnSurfVar
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            id: dcMA; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                StartMenuState.disconnectNetwork()
                                                StartMenuState.netPasswordSSID = ""
                                            }
                                        }
                                    }
                                    // Forget — any saved network (connected or not)
                                    Rectangle {
                                        visible: netDelegate.modelData.saved
                                        height: 20; radius: 5
                                        implicitWidth: visible ? fgLbl.implicitWidth + 14 : 0
                                        color: fgMA.containsMouse
                                            ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.16)
                                            : "transparent"
                                        border.width: 1
                                        border.color: Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b,
                                                              fgMA.containsMouse ? 0.55 : 0.28)
                                        Behavior on color        { ColorAnimation { duration: 100 } }
                                        Behavior on border.color { ColorAnimation { duration: 100 } }
                                        Text {
                                            id: fgLbl; anchors.centerIn: parent
                                            text: "Forget"; font.pixelSize: 9
                                            font.family: Config.labelFont
                                            color: fgMA.containsMouse ? Theme.cErr : Theme.cOnSurfVar
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                        }
                                        MouseArea {
                                            id: fgMA; anchors.fill: parent; hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                StartMenuState.forgetNetwork(netDelegate.modelData.ssid)
                                                // netPasswordSSID cleared inside forgetNetwork()
                                            }
                                        }
                                    }
                                }
                            }

                            // ── Password entry (unsaved secure networks) ─────────────
                            Row {
                                visible: netDelegate._showPass; width: parent.width; spacing: 4
                                Rectangle {
                                    width: parent.width - 34 - 4; height: 30; radius: 8
                                    color: Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.7)
                                    border.width: 1; border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.5)
                                    RowLayout { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 4
                                        TextInput {
                                            id: pwIn; Layout.fillWidth: true
                                            echoMode: StartMenuState.netPasswordVisible ? TextInput.Normal : TextInput.Password
                                            color: Theme.cOnSurf; font.pixelSize: 11
                                            // Bind to State so typed text survives networkList refreshes.
                                            text: StartMenuState.netPasswordText
                                            onTextChanged: StartMenuState.netPasswordText = text
                                            onAccepted: {
                                                StartMenuState.connectNetwork(netDelegate.modelData.ssid, text)
                                                StartMenuState.netPasswordSSID = ""
                                            }
                                        }
                                        Text {
                                            text: pwIn.text === "" ? "Password" : ""
                                            color: Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.5)
                                            font.pixelSize: 11; font.italic: true
                                            Layout.alignment: Qt.AlignVCenter
                                            visible: pwIn.text === "" && !pwIn.activeFocus
                                        }
                                        Text {
                                            text: StartMenuState.netPasswordVisible ? "󰈉" : "󰈈"
                                            font.pixelSize: 12; font.family: Config.fontFamily; color: Theme.cOnSurfVar
                                            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                                onClicked: StartMenuState.netPasswordVisible = !StartMenuState.netPasswordVisible }
                                        }
                                    }
                                }
                                Rectangle {
                                    width: 30; height: 30; radius: 8; color: Theme.cPrimary
                                    Text { anchors.centerIn: parent; text: "󰌑"; font.pixelSize: 12; font.family: Config.fontFamily; color: Theme.cOnPrim }
                                    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: {
                                        StartMenuState.connectNetwork(netDelegate.modelData.ssid, StartMenuState.netPasswordText)
                                        StartMenuState.netPasswordSSID = ""
                                    }}
                                }
                            }
                        }
                    }

                    Text {
                        visible: StartMenuState.networkList.length === 0 && !StartMenuState.netScanProcRunning
                        text: "No networks found"; color: Theme.cOnSurfVar; font.pixelSize: 11; font.italic: true; leftPadding: 12
                    }
                    } // netListCol
                    } // netListFlick
                }

                // Bluetooth panel (expanded)
                Item {
                    id: btSectionWrap
                    Layout.fillWidth: true
                    clip: true
                    readonly property real _rowH: 36
                    readonly property int  _maxRows: (StartMenuState.networkExpanded && StartMenuState.btExpanded) ? 3 : 6
                    readonly property real _maxHeight: _rowH * _maxRows
                    readonly property real _btListH: (StartMenuState.btPowered && StartMenuState.btDevices.length > 0)
                        ? Math.min(btListCol.implicitHeight, _maxHeight)
                        : (StartMenuState.btPowered ? 0 : 26)
                    readonly property real _targetH: StartMenuState.btExpanded ? (btToolbar.implicitHeight + 4 + _btListH) : 0
                    property real _animH: 0
                    Binding on _animH { value: btSectionWrap._targetH }
                    Behavior on _animH { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                    implicitHeight: _animH
                    Layout.preferredHeight: _animH
                    height: _animH
                    visible: _animH > 0.5 || StartMenuState.btExpanded
                    opacity: Math.min(1.0, _targetH > 0 ? (_animH / _targetH) : 0.0)

                    Column {
                        id: btCol
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 2

                        // Toolbar: Discoverable + Scan + Receive
                        Row {
                            id: btToolbar
                            width: parent.width; spacing: 6
                            Rectangle {
                                height: 26; radius: 8; width: 96
                                color: StartMenuState.btDiscoverable
                                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.2)
                                    : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.6)
                                border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout { anchors.centerIn: parent; spacing: 4
                                    Text { text: "󰂯"; font.pixelSize: 11; font.family: Config.fontFamily
                                        color: StartMenuState.btDiscoverable ? Theme.cPrimary : Theme.cOnSurf }
                                    Text { text: StartMenuState.btDiscoverable ? "Visible" : "Hidden"; font.pixelSize: 9; color: Config.wsPersistentColor }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: StartMenuState.btPowered ? StartMenuState.toggleBtDiscoverable() : StartMenuState.toggleBtPower() }
                            }
                            Rectangle {
                                height: 26; radius: 8; width: 82
                                color: StartMenuState.btScanning
                                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.20)
                                    : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.6)
                                border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout { anchors.centerIn: parent; spacing: 4
                                    Text {
                                        text: "󰑪"; font.pixelSize: 11; font.family: Config.fontFamily
                                        color: StartMenuState.btScanning ? Theme.cPrimary : Theme.cOnSurf
                                        RotationAnimator on rotation { from: 0; to: 360; duration: 1000; loops: Animation.Infinite
                                            running: StartMenuState.btScanning }
                                    }
                                    Text { text: StartMenuState.btScanning ? "Scanning…" : "Scan"; font.pixelSize: 10; color: Config.wsPersistentColor }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: StartMenuState.btPowered ? StartMenuState.toggleBtScan() : StartMenuState.toggleBtPower() }
                            }
                            Rectangle {
                                height: 26; radius: 8; width: 110
                                color: NotificationsState.btReceiving
                                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.20)
                                    : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.6)
                                border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout { anchors.centerIn: parent; spacing: 4
                                    Text { text: "󰶫"; font.pixelSize: 11; font.family: Config.fontFamily
                                        color: NotificationsState.btReceiving ? Theme.cPrimary : Theme.cOnSurf }
                                    Text { text: NotificationsState.btReceiving ? "Receiving…" : "Receive Files"
                                        font.pixelSize: 10; color: Config.wsPersistentColor }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                                    onClicked: NotificationsState.btToggleReceive() }
                            }
                        }

                        Text {
                            visible: !StartMenuState.btPowered
                            text: "Bluetooth is off"; color: Theme.cOnSurfVar; font.pixelSize: 11; font.italic: true; leftPadding: 4; topPadding: 4
                        }

                        // Device list — caps at 3 rows when both net & BT are expanded, 6 rows when alone
                        Item {
                            id: btListWrap
                            visible: StartMenuState.btPowered && StartMenuState.btDevices.length > 0
                            width: parent.width
                            height: Math.min(btListCol.implicitHeight, btSectionWrap._maxHeight)
                            clip: true

                            Flickable {
                                id: btListFlick
                                anchors.fill: parent
                                contentWidth: width
                                contentHeight: btListCol.implicitHeight
                                clip: true
                                boundsBehavior: Flickable.StopAtBounds
                                ScrollBar.vertical: ScrollBar {
                                    policy: (StartMenuState.btDevices && StartMenuState.btDevices.length > btSectionWrap._maxRows) ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
                                    visible: (StartMenuState.btDevices && StartMenuState.btDevices.length > btSectionWrap._maxRows) && size < 1.0
                                    contentItem: Rectangle {
                                        implicitWidth: 3
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.15)
                                        radius: 2
                                    }
                                    background: Rectangle { color: "transparent" }
                                }

                                Column {
                                    id: btListCol
                                    width: btListFlick.width; spacing: 2

                                Repeater {
                                    model: StartMenuState.btDevices
                                    delegate: Column {
                                        id: btDelegate
                                        required property var modelData
                                        required property int index
                                        width: parent.width; spacing: 2

                                        Rectangle {
                                            id: btDevRow
                                            width: parent.width; height: 34; radius: 8
                                            color: bth.containsMouse
                                                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.10)
                                                : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.5)
                                            Behavior on color { ColorAnimation { duration: 100 } }
                                            border.width: btDelegate.modelData.connected ? 1 : 0
                                            border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.5)

                                            RowLayout { anchors.fill: parent; anchors.leftMargin: 8; anchors.rightMargin: 8; spacing: 6
                                                Text {
                                                    font.pixelSize: 13; font.family: Config.fontFamily
                                                    color: btDelegate.modelData.connected ? Theme.cWc4 : Theme.cOnSurfVar
                                                    text: {
                                                        const ic = (btDelegate.modelData.icon || "").toLowerCase()
                                                        if (ic === "audio-headset" || ic === "audio-headphones" || ic === "audio-headset-gateway") return "󰋎"
                                                        if (ic === "audio-card" || ic.includes("speaker")) return "󰓃"
                                                        if (ic === "input-keyboard") return "󰌌"
                                                        if (ic === "input-mouse") return "󰍽"
                                                        if (ic === "input-gaming") return "󰊗"
                                                        if (ic === "phone") return "󰏲"
                                                        if (ic === "computer") return "󰇄"
                                                        if (ic.includes("watch") || ic.includes("wearable")) return "󰓹"
                                                        if (ic === "printer") return "󰐪"
                                                        if (ic === "camera-photo") return "󰄀"
                                                        if (ic === "camera-video") return "󰕧"
                                                        if (ic === "modem" || ic === "network-wireless") return "󰤨"
                                                        return "󰂯"
                                                    }
                                                }
                                                Text { Layout.fillWidth: true; text: btDelegate.modelData.name
                                                    color: Theme.cOnSurf; font.pixelSize: 11; elide: Text.ElideRight }
                                                Text { text: "󰒖"; font.pixelSize: 11; font.family: Config.fontFamily; color: Theme.cPrimary
                                                    visible: StartMenuState.btConnecting === btDelegate.modelData.mac
                                                    RotationAnimator on rotation { from: 0; to: 360; duration: 800; loops: Animation.Infinite
                                                        running: StartMenuState.btConnecting === btDelegate.modelData.mac } }
                                                Text { text: "󰄬"; font.pixelSize: 12; font.family: Config.fontFamily; color: Theme.cPrimary
                                                    visible: StartMenuState.btConnectedMac === btDelegate.modelData.mac
                                                    opacity: StartMenuState.btConnectedMac === btDelegate.modelData.mac ? 1.0 : 0.0
                                                    Behavior on opacity { NumberAnimation { duration: 400 } } }
                                                Text {
                                                    text: StartMenuState.btExpandedMac === btDelegate.modelData.mac ? "󰅀" : "󰅂"
                                                    font.pixelSize: 11; font.family: Config.fontFamily; color: Theme.cOnSurfVar
                                                    MouseArea { anchors.fill: parent; anchors.margins: -6; cursorShape: Qt.PointingHandCursor
                                                        onClicked: function(e) {
                                                            e.accepted = true
                                                            const m = btDelegate.modelData.mac
                                                            if (StartMenuState.btExpandedMac === m) StartMenuState.btExpandedMac = ""
                                                            else { StartMenuState.btExpandedMac = m; StartMenuState.btQueryProfile(m) }
                                                        }
                                                    }
                                                }
                                            }
                                            MouseArea { id: bth; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; z: -1
                                                onClicked: {
                                                    if (StartMenuState.btConnecting !== "") return
                                                    if (btDelegate.modelData.connected) StartMenuState.btDisconnect(btDelegate.modelData.mac)
                                                    else StartMenuState.btConnect(btDelegate.modelData.mac)
                                                }
                                            }
                                        }

                                        // Options panel
                                        Rectangle {
                                            visible: StartMenuState.btExpandedMac === btDelegate.modelData.mac
                                            width: parent.width
                                            height: visible ? optCol.implicitHeight + 12 : 0
                                            radius: 8
                                            color: Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.35)
                                            border.width: 1; border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
                                            clip: true

                                            Column {
                                                id: optCol
                                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 6 }
                                                spacing: 6

                                                RowLayout {
                                                    width: parent.width; spacing: 4
                                                    visible: StartMenuState.btHasAudioCard[btDelegate.modelData.mac] === true
                                                    Text { text: "Profile:"; font.pixelSize: 10; color: Theme.cOnSurfVar; Layout.preferredWidth: 40 }
                                                    ProfilePill { pLabel: "A2DP";    pProfile: "a2dp-sink";        pMac: btDelegate.modelData.mac }
                                                    ProfilePill { pLabel: "HSP/HFP"; pProfile: "headset-head-unit"; pMac: btDelegate.modelData.mac }
                                                    ProfilePill { pLabel: "Off";     pProfile: "off";               pMac: btDelegate.modelData.mac }
                                                    Item { Layout.fillWidth: true }
                                                }

                                                RowLayout {
                                                    width: parent.width; spacing: 4
                                                    Rectangle {
                                                        height: 22; radius: 6; implicitWidth: sdLbl.implicitWidth + 20
                                                        visible: btDelegate.modelData.connected &&
                                                                 StartMenuState.btHasAudioCard[btDelegate.modelData.mac] === true
                                                        color: sdh.containsMouse ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                                                            : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.8)
                                                        border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.50)
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        RowLayout { id: sdLbl; anchors.centerIn: parent; spacing: 4
                                                            Text { text: "󰓃"; font.pixelSize: 11; font.family: Config.fontFamily; color: Theme.cPrimary }
                                                            Text { text: "Default Output"; font.pixelSize: 10; color: Theme.cOnSurf }
                                                        }
                                                        MouseArea { id: sdh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: StartMenuState.btSetDefaultSink(btDelegate.modelData.mac) }
                                                    }
                                                    Rectangle {
                                                        id: trustRect; height: 22; radius: 6; implicitWidth: trLbl.implicitWidth + 20
                                                        property bool _isTrusted: StartMenuState.btIsTrusted(btDelegate.modelData.mac)
                                                        visible: {
                                                            const ic = (btDelegate.modelData.icon || "").toLowerCase()
                                                            return ic === "phone" || ic === "computer" || ic === "printer" ||
                                                                   ic.includes("watch") || ic.includes("wearable")
                                                        }
                                                        color: trh.containsMouse
                                                            ? (trustRect._isTrusted ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.18)
                                                                : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.20))
                                                            : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.8)
                                                        border.width: 1
                                                        border.color: trustRect._isTrusted
                                                            ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.5)
                                                            : Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        RowLayout { id: trLbl; anchors.centerIn: parent; spacing: 4
                                                            Text {
                                                                text: trustRect._isTrusted ? "󱈘" : "󱖡" //󰒃 󰒄
                                                                font.pixelSize: 11; font.family: Config.fontFamily
                                                                color: trustRect._isTrusted ? Theme.cErr : Theme.cPrimary
                                                            }
                                                            //Text { text: trustRect._isTrusted ? "Untrust" : "Trust"
                                                                //font.pixelSize: 10; color: trustRect._isTrusted ? Theme.cErr : Theme.cOnSurf }
                                                        }
                                                        MouseArea { id: trh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: StartMenuState.btSetTrust(btDelegate.modelData.mac, !trustRect._isTrusted) }
                                                    }
                                                    Rectangle {
                                                        height: 22; radius: 6; implicitWidth: sfLbl.implicitWidth + 20
                                                        visible: {
                                                            const ic = (btDelegate.modelData.icon || "").toLowerCase()
                                                            return ic === "phone" || ic === "computer" || ic === "printer" ||
                                                                   ic.includes("watch") || ic.includes("wearable")
                                                        }
                                                        color: sfh.containsMouse ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.20)
                                                            : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.8)
                                                        border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        RowLayout { id: sfLbl; anchors.centerIn: parent; spacing: 4
                                                            Text { text: "󰏢"; font.pixelSize: 11; font.family: Config.fontFamily; color: Theme.cOnSurfVar }
                                                            //Text { text: "Send File"; font.pixelSize: 10; color: Theme.cOnSurfVar }
                                                        }
                                                        MouseArea { id: sfh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: StartMenuState.btSendFile(btDelegate.modelData.mac) }
                                                    }
                                                    Item { Layout.fillWidth: true }
                                                    Rectangle {
                                                        height: 22; radius: 6; implicitWidth: rpLbl.implicitWidth + 20
                                                        color: rph.containsMouse ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                                                            : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.8)
                                                        border.width: 1; border.color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        RowLayout { id: rpLbl; anchors.centerIn: parent; spacing: 4
                                                            Text { text: "󰑓"; font.pixelSize: 11; font.family: Config.fontFamily; color: Theme.cOnSurfVar }
                                                            Text { text: "Fix"; font.pixelSize: 10; color: Theme.cOnSurfVar }
                                                        }
                                                        MouseArea { id: rph; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: StartMenuState.btRepair(btDelegate.modelData.mac) }
                                                    }
                                                    Rectangle {
                                                        height: 22; radius: 6; implicitWidth: fgLbl.implicitWidth + 20
                                                        color: fgh.containsMouse ? Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.18)
                                                            : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.8)
                                                        border.width: 1; border.color: Qt.rgba(Theme.cErr.r, Theme.cErr.g, Theme.cErr.b, 0.45)
                                                        Behavior on color { ColorAnimation { duration: 100 } }
                                                        RowLayout { id: fgLbl; anchors.centerIn: parent; spacing: 4
                                                            Text { text: "󰆴"; font.pixelSize: 11; font.family: Config.fontFamily; color: Theme.cErr; opacity: 0.8 }
                                                            //Text { text: "Forget"; font.pixelSize: 10; color: Theme.cErr; opacity: 0.8 }
                                                        }
                                                        MouseArea { id: fgh; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                            onClicked: StartMenuState.btForget(btDelegate.modelData.mac) }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: StartMenuState.btPowered && StartMenuState.btDevices.length === 0
                        text: "No paired devices — use Scan to discover"; color: Theme.cOnSurfVar
                        font.pixelSize: 11; font.italic: true; leftPadding: 4; topPadding: 4
                    }
                }
            }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16) }

            // ── Power / actions pill ──────────────────────────────────
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: pwrRow.implicitWidth + 12
                implicitHeight: 52
                radius: 99
                color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.5)
                border.width: 1
                border.color: Theme.cScrim
                Row {
                    id: pwrRow
                    anchors.centerIn: parent
                    spacing: 4
                    Repeater {
                        model: [
                            { i: "󰳌", c: Theme.cWc13, cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/power.sh lock",    show: true,     isLogout: false },
                            { i: "󰒲", c: Theme.cWc14, cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/power.sh suspend", show: true,     isLogout: false },
                            { i: "󰈉", c: Theme.cWc11, cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/power.sh hibernate", show: StartMenuState.hibernateAvailable, isLogout: false },
                            { i: "󰑙", c: Theme.cWc11, cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/power.sh reboot",  show: true,     isLogout: false },
                            { i: "󰐥", c: Theme.cWc14, cmd: Quickshell.env("HOME") + "/.config/hypr/scripts/power.sh shutdown",show: true,     isLogout: false },
                            { i: "󰗼", c: Theme.cWc13, cmd: "",                                                                 show: true,     isLogout: true }
                        ].filter(item => item.show)
                        delegate: Item {
                            required property var modelData
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent; anchors.topMargin: 2; anchors.bottomMargin: 2
                                radius: 99
                                color: ph.containsMouse
                                    ? Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.85)
                                    : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
                                border.width: 1
                                border.color: ph.containsMouse
                                    ? Qt.rgba(modelData.c.r, modelData.c.g, modelData.c.b, 0.65)
                                    : "transparent"
                                Behavior on color { ColorAnimation { duration: 130 } }
                                Behavior on border.color { ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.i
                                font.family: "Symbols Nerd Font Mono"
                                font.pixelSize: 18
                                color: modelData.c
                            }
                            MouseArea {
                                id: ph
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    StartMenuState.menuVisible = false
                                    if (modelData.isLogout) {
                                        StartMenuState.logout()
                                    } else {
                                        StartMenuState.runPowerCmd(modelData.cmd)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Item { height: 4 }
        }
    }

    // ── ProfilePill component ─────────────────────────────────────────────────
    component ProfilePill: Rectangle {
        id: pill
        required property string pLabel
        required property string pProfile
        required property string pMac
        property bool isActive: (StartMenuState.btActiveProfile[pMac] || "").indexOf(pProfile) >= 0
        height: 24; radius: 6; width: pillLbl.implicitWidth + 20
        color: isActive ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
            : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.8)
        border.width: 1
        border.color: isActive ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.7)
            : Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.4)
        Behavior on color { ColorAnimation { duration: 100 } }
        Text { id: pillLbl; anchors.centerIn: parent; text: pill.pLabel; font.pixelSize: 10
            color: pill.isActive ? Theme.cPrimary : Theme.cOnSurfVar }
        MouseArea { anchors.fill: parent; anchors.margins: -1; cursorShape: Qt.PointingHandCursor
            onClicked: StartMenuState.btSetProfile(pill.pMac, pill.pProfile) }
    }

    // ── SliderBg component ────────────────────────────────────────────────────
    component SliderBg: Item {
        id: sl
        property real value: 0.0
        property color gradA: Theme.cInversePrimary
        property color gradB: Theme.cOnSecondary
        property color track: Theme.cOutVar
        property color accent: Theme.cPrimary
        signal moved(real v)

        readonly property int trackH: 14
        readonly property int pad:    3
        readonly property int innerH: trackH - pad * 2

        Item {
            y: (parent.height - sl.trackH) / 2; width: parent.width; height: sl.trackH
            Rectangle {
                anchors.fill: parent; radius: sl.trackH / 2
                color: Qt.rgba(sl.track.r, sl.track.g, sl.track.b, 0.28)
                border.width: 1; border.color: Qt.rgba(sl.accent.r, sl.accent.g, sl.accent.b, 0.55)
            }
            Item {
                x: sl.pad; y: sl.pad
                width: Math.max(0, (parent.width - sl.pad * 2) * sl.value); height: sl.innerH; clip: true
                Rectangle {
                    width: parent.parent.width - sl.pad * 2; height: sl.innerH; radius: sl.innerH / 2
                    gradient: Gradient { orientation: Gradient.Horizontal
                        GradientStop { position: 0.0; color: sl.gradA }
                        GradientStop { position: 1.0; color: sl.gradB }
                    }
                }
            }
            Text {
                text: "󰟃"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: sl.innerH + 2
                color: Theme.cWc4; style: Text.Outline; styleColor: Qt.rgba(0, 0, 0, 0.25)
                x: { const tw = parent.width - sl.pad * 2; const cx = sl.pad + tw * sl.value - implicitWidth / 2
                     return Math.max(sl.pad - implicitWidth/2 + 1, Math.min(parent.width - sl.pad - implicitWidth/2 - 1, cx)) }
                y: (sl.trackH - implicitHeight) / 2
            }
        }
        MouseArea {
            anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; preventStealing: true
            onPressed:         function(m) { const v = Math.max(0, Math.min(1, m.x/width)); sl.value = v; sl.moved(v) }
            onPositionChanged: function(m) { if (pressed) { const v = Math.max(0, Math.min(1, m.x/width)); sl.value = v; sl.moved(v) } }
            onWheel:           function(e) { const step = 0.02 * (e.angleDelta.y > 0 ? 1 : -1); const v = Math.max(0, Math.min(1, sl.value + step)); sl.value = v; sl.moved(v) }
        }
    }
}
