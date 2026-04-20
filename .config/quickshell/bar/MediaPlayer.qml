import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Io
import ".."

// ── Media island ─────────────────────────────────────────────────────────────
//  All playerctl state lives in MediaPlayerState singleton (one process total).
//  This component is pure UI — instantiated once per screen, reads shared state.

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  padContainer.implicitWidth
    implicitHeight: Config.moduleHeight

    // ── Per-instance UI state (not shared) ───────────────────────────────────
    property bool shrinkToControls: false
    property real mediaMaxW: -1

    readonly property real _titleMaxW: {
        if (mediaMaxW < 0 || shrinkToControls) return -1
        const controlsW = padContainer.implicitWidth - (titleClip.implicitWidth > 0 ? titleClip.implicitWidth : 0)
        return Math.max(0, mediaMaxW - controlsW)
    }

    // ── GJS media-player toggle ───────────────────────────────────────────────
    Process { id: gjsMediaProc; command: [Config.candyDir + "/GJS/toggle-media-player.sh"]; running: false }

    // ── Padding container ─────────────────────────────────────────────────────
    Item {
        id: padContainer
        anchors.centerIn: parent
        implicitWidth:  mediaRow.implicitWidth + Config.mediaPadLeft + Config.mediaPadRight + Config.modulePadH
        implicitHeight: Config.moduleHeight

        Row {
            id: mediaRow
            anchors.centerIn: parent
            spacing: 0

            // ── GJS toggle button ─────────────────────────────────────────
            Item {
                implicitWidth:  gjsIcon.implicitWidth + Config.modPadH * 2
                implicitHeight: Config.moduleHeight
                Text {
                    id: gjsIcon; anchors.centerIn: parent
                    text: Config.mediaToggleGlyph
                    color: Config.mediaGlyphColor
                    font.family: Config.fontFamily; font.pixelSize: Config.mediaGlyphSize
                    font.weight: Config.fontWeight
                }
                opacity: gjsMa.containsMouse ? 0.7 : 1.0
                Behavior on opacity { NumberAnimation { duration: 80 } }
                MouseArea {
                    id: gjsMa; anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: function(ev) {
                        if (ev.button === Qt.RightButton)
                            root.shrinkToControls = !root.shrinkToControls
                        else if (!gjsMediaProc.running) gjsMediaProc.running = true
                    }
                }
            }

            // ── Track info (hidden when stopped) ─────────────────────────
            Item {
                visible: MediaPlayerState.active
                implicitWidth: visible ? (trackRow.implicitWidth + Config.modPadH) : 0
                implicitHeight: Config.moduleHeight
                Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                Row {
                    id: trackRow; anchors.centerIn: parent; spacing: 5

                    // ── Spinning disc ─────────────────────────────────────
                    Rectangle {
                        id: discContainer
                        width: MediaPlayerState.thumbSize; height: MediaPlayerState.thumbSize
                        radius: width / 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"
                        layer.enabled: true
                        layer.smooth: true
                        layer.effect: MultiEffect {
                            maskEnabled: true
                            maskSource: discMask
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1.0
                        }
                        Rectangle {
                            id: discMask; anchors.fill: parent
                            radius: width / 2; color: "white"; opacity: 0; layer.enabled: true
                        }

                        // Circular background for placeholder state — declared first so
                        // it renders behind the glyph Text
                        Rectangle {
                            visible: MediaPlayerState.artPath === ""
                            anchors.fill: parent
                            radius: width / 2
                            color: Qt.rgba(Theme.cSurfMid.r, Theme.cSurfMid.g,
                                           Theme.cSurfMid.b, 0.85)
                        }

                        Image {
                            visible: MediaPlayerState.artPath !== ""
                            anchors.fill: parent
                            source: MediaPlayerState.artPath !== "" ? ("file://" + MediaPlayerState.artPath.split("?")[0]) : ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true; cache: false; asynchronous: true
                        }

                        Text {
                            visible: MediaPlayerState.artPath === ""
                            anchors.centerIn: parent
                            text: Config.mediaToggleGlyph
                            color: Config.glyphColor
                            font.family: Config.fontFamily
                            font.pixelSize: MediaPlayerState.thumbSize - 2
                        }

                        RotationAnimator on rotation {
                            from: discContainer.rotation; to: discContainer.rotation + 360
                            duration: 8000; loops: Animation.Infinite
                            running: MediaPlayerState.playing
                        }
                    }

                    // ── Play/Pause icon ────────────────────────────────────
                    Text {
                        text: MediaPlayerState.playing ? "󰐊" : "󰏤"
                        color: Config.mediaGlyphColor
                        font.family: Config.fontFamily
                        font.pixelSize: Config.mediaPlayPauseSize
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    // ── Title – Artist ─────────────────────────────────────
                    Item {
                        id: titleClip
                        implicitWidth: {
                            if (root.shrinkToControls) return 0
                            const nat = titleLbl.implicitWidth
                            if (root._titleMaxW < 0) return nat
                            return Math.min(nat, root._titleMaxW)
                        }
                        implicitHeight: titleLbl.implicitHeight
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Behavior on implicitWidth { NumberAnimation { duration: 180; easing.type: Easing.InOutQuad } }
                        Text {
                            id: titleLbl
                            text: MediaPlayerState.label
                            color: Config.textColor
                            font.family: Config.labelFont
                            font.pixelSize: Config.mediaInfoFontSize
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }

                opacity: trackMa.containsMouse ? 0.7 : 1.0
                Behavior on opacity { NumberAnimation { duration: 80 } }

                MouseArea {
                    id: trackMa; anchors.fill: parent; hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: function(ev) {
                        if (ev.button === Qt.RightButton) MediaPlayerState.ctl("next")
                        else MediaPlayerState.ctl("play-pause")
                    }
                    onWheel: function(ev) {
                        MediaPlayerState.ctl(ev.angleDelta.y > 0 ? "previous" : "next")
                    }
                }
            }
        }
    }
}
