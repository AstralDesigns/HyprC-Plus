import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

// ── Media island ─────────────────────────────────────────────────────────────
//  Shows: GJS toggle glyph | (when active) thumb/disc + prev/⏯/next controls
//  Thumb area is always thumbSize wide when active — placeholder spinning disc
//  shown when no art, image when art is available. No collapse on art changes.
//  All playerctl state lives in MediaPlayerState singleton.

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth:  padContainer.implicitWidth
    implicitHeight: Config.moduleHeight

    property real mediaMaxW: -1

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

            // ── GJS toggle button ─────────────────────────────────────────────
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
                    onClicked: if (!gjsMediaProc.running) gjsMediaProc.running = true
                }
            }

            // ── Active media area: thumb/disc + controls (hidden when stopped) ─
            Item {
                id: activeMedia
                // Animate width only on active↔inactive transitions, not on art changes
                implicitWidth: MediaPlayerState.active
                    ? (discContainer.implicitWidth + Config.modPadH + ctlRow.implicitWidth + Config.modPadH)
                    : (discContainer.implicitWidth + Config.modPadH + ctlRow.implicitWidth + Config.modPadH) //0
                implicitHeight: Config.moduleHeight
                clip: true
                Behavior on implicitWidth { NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }

                Row {
                    id: activeRow
                    anchors.centerIn: parent
                    spacing: Config.modPadH

                    // ── Thumb / placeholder disc — always thumbSize, never collapses ──
                    Item {
                        id: discContainer
                        implicitWidth:  MediaPlayerState.thumbSize
                        implicitHeight: MediaPlayerState.thumbSize
                        anchors.verticalCenter: parent.verticalCenter

                        // Placeholder: spinning music-note glyph (visible when no art)
                        Text {
                            id: discGlyph
                            visible: MediaPlayerState.artPath === "" || artImage.status !== Image.Ready
                            anchors.centerIn: parent
                            text: "" //󰎆 󰎍 󰺕 󱥸 󱨧
                            color: Config.discGlyphColor
                            font.family: Config.fontFamily
                            font.pixelSize: MediaPlayerState.thumbSize - 2
                        }

                        RotationAnimator on rotation {
                            from: discContainer.rotation; to: discContainer.rotation + 360
                            duration: 8000; loops: Animation.Infinite
                            running: MediaPlayerState.playing
                        }

                        // Album art image (fades in over placeholder)
                        Image {
                            id: artImage
                            anchors.fill: parent
                            visible: MediaPlayerState.artPath !== ""
                            source: MediaPlayerState.artPath !== ""
                                ? ("file://" + MediaPlayerState.artPath)
                                : ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true; cache: false; asynchronous: true
                            opacity: status === Image.Ready ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 120 } }
                        }
                    }

                    // ── Prev / Play-Pause / Next controls ─────────────────────
                    Row {
                        id: ctlRow
                        spacing: 1
                        anchors.verticalCenter: parent.verticalCenter

                        Repeater {
                            model: [
                                { glyph: "󰒮", cmd: "previous"   },
                                { glyph: ""   },
                                { glyphplay: MediaPlayerState.playing ? "󰏤" : "󰐊", cmd: "play-pause" },
                                { glyph: ""   },
                                { glyph: "󰒭", cmd: "next"       }
                            ]
                            delegate: Item {
                                required property var modelData
                                implicitWidth:  ctlGlyph.implicitWidth + Config.modPadH
                                implicitHeight: Config.moduleHeight
                                anchors.verticalCenter: parent ? parent.verticalCenter : undefined

                                Text {
                                    id: ctlGlyph
                                    anchors.centerIn: parent
                                    text:  modelData.glyph
                                    color: ctlMa.containsMouse ? Config.powerGlyphColor : Config.mediabtGlyphColor; opacity: 0.8
                                    font.family:    Config.fontFamily
                                    font.pixelSize: Config.mediaCtlSize
                                    font.weight:    Config.fontWeight
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }
                                
                                Text {
                                    id: ctlglyph
                                    anchors.centerIn: parent
                                    text:  modelData.glyphplay
                                    color: ctlMa.containsMouse ? Config.powerGlyphColor : Theme.cPrimaryFixedDim; opacity: 0.8
                                    font.family:    Config.fontFamily
                                    font.pixelSize: Config.mediaCtlSize
                                    font.weight:    Config.fontWeight
                                    Behavior on color { ColorAnimation { duration: 80 } }
                                }

                                opacity: ctlMa.containsMouse ? 0.7 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 80 } }

                                MouseArea {
                                    id: ctlMa; anchors.fill: parent; hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: MediaPlayerState.ctl(modelData.cmd)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
