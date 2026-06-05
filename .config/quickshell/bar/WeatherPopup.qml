pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

// ─────────────────────────────────────────────────────────────────────────────
//  WeatherPopup — pure display layer.
//
//  All data lives in WeatherPopupState (singleton). The popup opens with data
//  already populated because Weather.qml keeps the singleton refreshed on its
//  poll interval. No fetch is triggered here.
// ─────────────────────────────────────────────────────────────────────────────
PanelWindow {
    id: wxWin

    readonly property bool _barAtBottom:  Config.barPosition === "bottom"
    readonly property real _barGap:       Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot:    Config.outerMarginBottom + Config.barHeight + 6
    readonly property real _panelMargin:  Config.outerMarginSide * 2

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }

    implicitHeight: wxPanel.implicitHeight

    exclusionMode:            ExclusionMode.Ignore
    WlrLayershell.layer:      WlrLayer.Top
    WlrLayershell.namespace:  "quickshell:weather-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color:   "transparent"
    visible: WeatherPopupState.visible

    // ── Dismiss on focus change ───────────────────────────────────────────
    Connections {
        target: (typeof HyprlandFocusedClient !== "undefined") ? HyprlandFocusedClient : null
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                WeatherPopupState.close()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onClicked: WeatherPopupState.close() }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: wxPanel
        anchors {
            right: parent.right; rightMargin: wxWin._panelMargin
            top: parent.top; bottom: parent.bottom
        }
        width: 560
        implicitHeight: wxCol.implicitHeight + 32

        //radius: startMenuPanel._panelRadius
        topLeftRadius: 20
        topRightRadius: 20
        bottomLeftRadius: 20
        bottomRightRadius: 20
        color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g, Theme.cInversePrimary.b, 0.40)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.40)

        scale: WeatherPopupState.visible ? 1.0 : 0.94
        transformOrigin: wxWin._barAtBottom ? Item.BottomRight : Item.TopRight
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

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

                // Close button
                Rectangle {
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
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
            }

            // ── Current conditions ────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 18

                Column {
                    spacing: 2; Layout.alignment: Qt.AlignVCenter
                    Text {
                        text: WeatherPopupState.icon
                        color: Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00)
                        font.pixelSize: 52; font.family: Config.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: WeatherPopupState.temp
                        color: Theme.cOnSurf
                        font.pixelSize: 26; font.weight: Font.Bold; font.family: Config.labelFont
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: WeatherPopupState.condStr
                        color: Theme.cOnSurfVar
                        font.pixelSize: 11; font.family: Config.labelFont
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }

                Grid {
                    columns: 2; rowSpacing: 6; columnSpacing: 20
                    Layout.alignment: Qt.AlignVCenter
                    Repeater {
                        model: [
                            { glyph: "󰔐", label: "Feels",    val: WeatherPopupState.feels },
                            { glyph: "󰖌", label: "Humidity", val: WeatherPopupState.hum   },
                            { glyph: "󰖝", label: "Wind",     val: WeatherPopupState.wind  },
                            { glyph: "󰖗", label: "Precip",   val: WeatherPopupState.prec  }
                        ]
                        delegate: Row {
                            required property var modelData
                            spacing: 6
                            Text {
                                text: modelData.glyph; color: Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00)
                                font.pixelSize: 14; font.family: Config.fontFamily
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                spacing: 0
                                Text { text: modelData.label; color: Theme.cOnSurfVar; font.pixelSize: 10; font.family: Config.labelFont }
                                Text { text: modelData.val;   color: Theme.cOnSurf;    font.pixelSize: 12; font.weight: Font.Medium; font.family: Config.labelFont }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true; height: 1
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
            }

            // ── Hourly forecast — next 12 hours ───────────────────────────
            Item {
                Layout.fillWidth: true
                visible: WeatherPopupState.hrTimes.length > 0
                implicitHeight: visible ? hrRow.implicitHeight : 0

                RowLayout {
                    id: hrRow
                    anchors { left: parent.left; right: parent.right }
                    spacing: 0
                    Repeater {
                        model: WeatherPopupState.hrTimes.length
                        delegate: Item {
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: hrCol.implicitHeight
                            Column {
                                id: hrCol
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 2
                                Text {
                                    text: WeatherPopupState.hrTimes[index] || "--"
                                    color: index === 0 ? Theme.cOnSurf : Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.65)
                                    font.pixelSize: 15; font.family: Config.labelFont
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: WeatherPopupState.hrIcons[index] || "󰖐"
                                    color: Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00); font.pixelSize: 24; font.family: Config.fontFamily
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: WeatherPopupState.hrTemps[index] || "--"
                                    color: Theme.cOnSurf; font.pixelSize: 11; font.weight: Font.Medium; font.family: Config.labelFont
                                    horizontalAlignment: Text.AlignHCenter
                                    anchors.horizontalCenter: parent.horizontalCenter
                                }
                                Text {
                                    text: WeatherPopupState.hrPrec[index] || "0%"
                                    color: Theme.cSecondary; font.pixelSize: 11; font.family: Config.labelFont
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
                color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28)
            }

            // ── 7-day forecast ────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: WeatherPopupState.fcDays.length
                    delegate: Item {
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: fcCol.implicitHeight
                        Column {
                            id: fcCol
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            Text {
                                text: WeatherPopupState.fcDays[index] || "--"
                                color: index === 0 ? Theme.cOnSurf : Qt.rgba(Theme.cOnSurfVar.r, Theme.cOnSurfVar.g, Theme.cOnSurfVar.b, 0.65)
                                font.pixelSize: 15; font.weight: index === 0 ? Font.Medium : Font.Normal
                                font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: WeatherPopupState.fcIcons[index] || "󰖐"
                                color: Qt.rgba(Theme.cPrimary.r, Theme.cSourceColor.g, Theme.cSourceColor.b, 1.00); font.pixelSize: 24; font.family: Config.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: WeatherPopupState.fcHi[index] || "--"
                                color: Theme.cOnSurf; font.pixelSize: 11; font.weight: Font.Medium; font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: WeatherPopupState.fcLo[index] || "--"
                                color: Theme.cSecondary; font.pixelSize: 11; font.family: Config.labelFont
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
}
