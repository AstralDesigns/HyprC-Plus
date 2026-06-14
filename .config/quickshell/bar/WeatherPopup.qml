pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// Left-click → top-layer popup. Right-click → bottom-layer draggable widget.
Item {
    id: scope

    property real orbitOffset: 0
    property int _wheelPending: 0
    readonly property int _hourCount: Math.max(WeatherPopupState.hrTimes.length, 1)

    Behavior on orbitOffset {
        NumberAnimation { duration: 350; easing.type: Easing.OutQuad }
    }

    Timer {
        id: wheelCoalesce
        interval: 90
        repeat: false
        onTriggered: scope._flushWheelSteps()
    }

    function _flushWheelSteps() {
        if (_wheelPending === 0) return
        orbitOffset = Math.round(orbitOffset) + _wheelPending
        _wheelPending = 0
    }

    function stepHour(delta) {
        _wheelPending += delta
        if (!wheelCoalesce.running) {
            orbitOffset = Math.round(orbitOffset) + _wheelPending
            _wheelPending = 0
        }
        wheelCoalesce.restart()
    }

    function focusHour(targetIndex) {
        const n = _hourCount
        if (n <= 0 || targetIndex < 0 || targetIndex >= n) return
        _wheelPending = 0
        wheelCoalesce.stop()
        const base = Math.round(orbitOffset)
        const current = ((base % n) + n) % n
        let delta = targetIndex - current
        if (delta > n / 2) delta -= n
        else if (delta < -n / 2) delta += n
        if (delta === 0) return
        orbitOffset = base + delta
    }

    Connections {
        target: WeatherPopupState
        function onVisibleChanged() {
            if (WeatherPopupState.visible) {
                scope._wheelPending = 0
                scope.orbitOffset = 0
            }
        }
    }

    component WeatherPanel: Rectangle {
        id: wxPanel
        required property var root
        property bool showClose: true
        property bool popupMode: false

        width: 560
        implicitHeight: wxCol.implicitHeight + 32
        topLeftRadius: 20
        topRightRadius: 20
        bottomLeftRadius: 20
        bottomRightRadius: 20
        color: Qt.rgba(Theme.cOnPrimaryFixedVariant.r, Theme.cOnPrimaryFixedVariant.g, Theme.cOnPrimaryFixedVariant.b, 0.3)
        border.width: Config.barBorderWidth
        border.color: Qt.rgba(Config.barBorderColor.r, Config.barBorderColor.g,
                      Config.barBorderColor.b, Config.barBorderAlpha)

        scale: popupMode && WeatherPopupState.visible ? 1.0 : (popupMode ? 0.94 : 1.0)
        transformOrigin: popupMode && Config.barPosition === "bottom" ? Item.BottomRight : Item.TopRight
        Behavior on scale { enabled: popupMode; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent; enabled: popupMode }

        ColumnLayout {
            id: wxCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            spacing: 10

            // ── Header ────────────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 6

                Text {
                    text: "󰖐  Weather"
                    color: Theme.cPrimary
                    font.pixelSize: 13; font.weight: Font.Medium; font.family: Config.fontFamily
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: WeatherPopupState.city ? "󰍎  " + WeatherPopupState.city : ""
                    color: Theme.cOnSurfVar; font.pixelSize: 12; font.family: Config.labelFont
                    elide: Text.ElideRight; Layout.maximumWidth: 180
                }

                // °C / °F toggle pill
                Rectangle {
                    width: 56; height: 24; radius: 99
                    color: unitHov.containsMouse
                        ? Qt.rgba(Theme.cPrimary.r,  Theme.cPrimary.g,  Theme.cPrimary.b,  0.22)
                        : Qt.rgba(Theme.cSurfHi.r,   Theme.cSurfHi.g,   Theme.cSurfHi.b,   0.55)
                    border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.35)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: WeatherPopupState._metric ? "°C / °F" : "°F / °C"
                        color: Theme.cPrimary; font.pixelSize: 10; font.weight: Font.Medium
                    }
                    MouseArea {
                        id: unitHov
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: WeatherPopupState.toggleUnit()
                    }
                }

                // Close button (popup only)
                Rectangle {
                    visible: showClose
                    width: 24; height: 24; radius: 99
                    color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.2)
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: WeatherPopupState.close()
                        Text {
                            anchors.centerIn: parent; text: "󰅙"
                            color: Theme.cPrimary
                            font.pixelSize: 13; font.family: Config.fontFamily
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
            }

            // ── Current Conditions + Hourly Forecast Orbit ────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                // Left Side: Current conditions card
                Rectangle {
                    id: currentCondCard
                    Layout.preferredWidth: 252
                    Layout.maximumWidth: 252
                    Layout.fillHeight: true
                    implicitHeight: 172
                    radius: 20
                    clip: true
                    color: Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)
                    border.width: 1
                    border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8

                        ColumnLayout {
                            Layout.preferredWidth: 92
                            Layout.maximumWidth: 92
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 2

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: WeatherPopupState.icon
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00)
                                font.pixelSize: 40
                                font.family: Config.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: WeatherPopupState.temp
                                color: Theme.cOnSurf
                                font.pixelSize: 21
                                font.weight: Font.Bold
                                font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                            }
                            Text {
                                Layout.fillWidth: true
                                text: WeatherPopupState.condStr
                                color: Theme.cOnSurfVar
                                font.pixelSize: 10
                                font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        GridLayout {
                            columns: 2
                            rowSpacing: 5
                            columnSpacing: 6
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter

                            Repeater {
                                model: [
                                    { glyph: "󰔐", label: "Feels",    val: WeatherPopupState.feels },
                                    { glyph: "󰖌", label: "Humidity", val: WeatherPopupState.hum   },
                                    { glyph: "󰖝", label: "Wind",     val: WeatherPopupState.wind  },
                                    { glyph: "󰖗", label: "Precip",   val: WeatherPopupState.prec  }
                                ]
                                delegate: RowLayout {
                                    required property var modelData
                                    spacing: 3
                                    Layout.maximumWidth: (currentCondCard.width - 122) / 2

                                    Text {
                                        text: modelData.glyph
                                        color: Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00)
                                        font.pixelSize: 12
                                        font.family: Config.fontFamily
                                    }
                                    ColumnLayout {
                                        spacing: 0
                                        Layout.fillWidth: true
                                        Text {
                                            text: modelData.label
                                            color: Theme.cOnSurfVar
                                            font.pixelSize: 9
                                            font.family: Config.labelFont
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                        Text {
                                            text: modelData.val
                                            color: Theme.cOnSurf
                                            font.pixelSize: 10
                                            font.weight: Font.Medium
                                            font.family: Config.labelFont
                                            elide: Text.ElideRight
                                            Layout.fillWidth: true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // Right Side: Hourly forecast tilted circular orbit
                Item {
                    id: orbitContainer
                    Layout.fillWidth: true
                    implicitHeight: 160
                    clip: true

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            if (event.angleDelta.y > 0)
                                root.stepHour(-1)
                            else
                                root.stepHour(1)
                        }
                    }

                    Repeater {
                        model: WeatherPopupState.hrTimes.length
                        delegate: Rectangle {
                            id: hrCard
                            required property int index

                            readonly property real theta: (2 * Math.PI / root._hourCount) * (index - root.orbitOffset)
                            readonly property real zRatio: Math.cos(theta)
                            readonly property bool isCurrentHour: index === 0
                            readonly property bool isOrbitFront: zRatio > 0.96

                            width: 58
                            height: 78
                            radius: 99
                            clip: true

                            readonly property real cx: orbitContainer.width / 2
                            readonly property real cy: orbitContainer.height / 2

                            x: cx + 105 * Math.sin(theta) - width / 2
                            y: cy + 30 * zRatio - height / 2

                            scale: {
                                const baseScale = 0.68 + 0.32 * (zRatio + 1) / 2
                                return baseScale * (isOrbitFront && hrHover.hovered ? 1.15 : (isOrbitFront ? 1.08 : 1.0))
                            }
                            opacity: 0.20 + 0.80 * (zRatio + 1) / 2
                            z: Math.round((zRatio + 1) * 10)

                            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

                            color: isCurrentHour
                                ? "transparent"
                                : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 1.0)

                            gradient: isCurrentHour ? hrGradient : null

                            Gradient {
                                id: hrGradient
                                GradientStop { position: 0.0; color: Theme.cInversePrimary }
                                GradientStop { position: 1.0; color: Theme.cOnPrimaryFixedVariant }
                            }

                            border.width: 1
                            border.color: isCurrentHour
                                ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.45)
                                : isOrbitFront
                                    ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.30)
                                    : Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.18)

                            HoverHandler {
                                id: hrHover
                            }

                            MouseArea {
                                anchors.fill: parent
                                z: 1
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.focusHour(index)
                            }

                            Column {
                                anchors.centerIn: parent
                                spacing: 1
                                Text {
                                    text: WeatherPopupState.hrTimes[index] || "--"
                                    color: isCurrentHour ? Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00)
                                        : Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.65)
                                    font.pixelSize: 9; font.family: Config.labelFont
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: WeatherPopupState.hrIcons[index] || "󰖐"
                                    color: isCurrentHour ? Theme.cPrimary
                                        : Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00)
                                    font.pixelSize: 18; font.family: Config.fontFamily
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: WeatherPopupState.hrTemps[index] || "--"
                                    color: isCurrentHour ? Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00) : Theme.cOnSurf
                                    font.pixelSize: 9; font.weight: Font.Medium; font.family: Config.labelFont
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: WeatherPopupState.hrPrec[index] || "0%"
                                    color: isCurrentHour ? Theme.cPrimary : Theme.cSecondary
                                    font.pixelSize: 8; font.family: Config.labelFont
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.16)
            }

            // ── 7-day forecast ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Repeater {
                    model: WeatherPopupState.fcDays.length
                    delegate: Rectangle {
                        id: fcCard
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: fcCol.implicitHeight + 16
                        radius: 12
                        clip: true

                        // Gradient for current day, Theme.cOnSecondary for others
                        color: index === 0
                            ? "transparent"
                            : Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.65)

                        gradient: index === 0 ? fcGradient : null

                        Gradient {
                            id: fcGradient
                            GradientStop { position: 0.0; color: Theme.cInversePrimary }
                            GradientStop { position: 1.0; color: Theme.cOnPrimaryFixedVariant }
                        }

                        border.width: 1
                        border.color: index === 0
                            ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.35)
                            : Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.18)

                        Column {
                            id: fcCol
                            anchors.centerIn: parent
                            spacing: 3
                            Text {
                                text: WeatherPopupState.fcDays[index] || "--"
                                color: index === 0 ? Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00) : Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.65)
                                font.pixelSize: 11; font.weight: index === 0 ? Font.Bold : Font.Normal
                                font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: WeatherPopupState.fcIcons[index] || "󰖐"
                                color: index === 0 ? Theme.cPrimary : Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00); font.pixelSize: 22; font.family: Config.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: WeatherPopupState.fcHi[index] || "--"
                                color: index === 0 ? Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00) : Theme.cOnSurf; font.pixelSize: 10; font.weight: Font.Medium; font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: WeatherPopupState.fcLo[index] || "--"
                                color: index === 0 ? Theme.cPrimary : Theme.cSecondary; font.pixelSize: 10; font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
            }

            Item { height: 4 }
        }
    }

    PanelWindow {
        id: wxPopup
        readonly property bool _barAtBottom: Config.barPosition === "bottom"
        readonly property real _barGap: Config.outerMarginTop + Config.barHeight + 6
        readonly property real _barGapBot: Config.outerMarginBottom + Config.barHeight + 6
        readonly property real _panelMargin: Config.outerMarginSide * 2

        anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
        margins {
            top: _barAtBottom ? 0 : _barGap
            bottom: _barAtBottom ? _barGapBot : 0
        }

        implicitHeight: wxPanelPopup.implicitHeight
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:weather-popup"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        color: "transparent"
        visible: WeatherPopupState.visible

        Connections {
            target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
            ignoreUnknownSignals: true
            function onAddressChanged() {
                if (HyprlandFocusedClient.address !== "")
                    WeatherPopupState.close()
            }
        }

        MouseArea { anchors.fill: parent; z: -1; onClicked: WeatherPopupState.close() }

        WeatherPanel {
            id: wxPanelPopup
            root: scope
            showClose: true
            popupMode: true
            anchors {
                right: parent.right
                rightMargin: wxPopup._panelMargin
                top: parent.top
                bottom: parent.bottom
            }
        }
    }

    PinnedWidgetWindow {
        id: weatherWidget
        active: WeatherPopupState.widgetVisible
        widgetNamespace: "quickshell:weather-widget"
        onActiveChanged: {
            if (active) {
                weatherWidget.posX = WeatherPopupState.widgetX
                weatherWidget.posY = WeatherPopupState.widgetY
            }
        }
        onPositionCommitted: function(x, y) {
            WeatherPopupState.widgetX = Math.round(x)
            WeatherPopupState.widgetY = Math.round(y)
        }

        WeatherPanel {
            root: scope
            showClose: false
            popupMode: false
        }
    }
}
