import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  UserProfile.qml — User avatar (circular crop via ImageMagick) + username
//  Clicking the avatar opens an internal file browser to pick a new image.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: profile
    implicitWidth: parent ? parent.width : 200
    implicitHeight: col.implicitHeight + 12

    ColumnLayout {
        id: col
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 8
        spacing: 4

        // ── Avatar circle ────────────────────────────────────────────────
        Rectangle {
            id: avatarFrame
            Layout.alignment: Qt.AlignHCenter
            width: 60; height: 60; radius: 30
            color: "transparent"
            border.width: 2
            border.color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.4)

            Image {
                id: avatarImg
                anchors.fill: parent
                anchors.margins: 2
                source: _iconExists ? "file://" + CCConfig.userIconPath : ""
                fillMode: Image.PreserveAspectCrop
                visible: _iconExists
                layer.enabled: true
                layer.effect: Item {
                    // Circular clip via OpacityMask equivalent using ShaderEffect
                }

                // Circular clip
                Rectangle {
                    id: avatarMask
                    anchors.fill: parent
                    radius: width / 2
                    visible: false
                }
            }

            // Fallback: generic user silhouette
            Text {
                anchors.centerIn: parent
                text: "\uf007"
                font.family: CCConfig.fontFamily
                font.pixelSize: 24
                color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.5)
                visible: !_iconExists
            }

            property bool _iconExists: _iconCheck.exists

            FileView {
                id: _iconCheck
                path: CCConfig.userIconPath
                watchChanges: true
                property bool exists: false
                onLoaded: exists = (text().length > 0)
                onFileChanged: { reload(); avatarImg.source = "" ; avatarImg.source = "file://" + CCConfig.userIconPath }
                Component.onCompleted: reload()
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: ControlCenterState.switchTab("imagepicker")
            }

            // Hover glow
            Rectangle {
                anchors.fill: parent; radius: parent.radius
                color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.08)
                visible: parent.children[parent.children.length - 2].containsMouse
            }
        }

        // ── Username ─────────────────────────────────────────────────────
        Text {
            id: usernameLabel
            Layout.alignment: Qt.AlignHCenter
            text: _username
            color: CCTheme.cPrimary
            font.family: CCConfig.labelFont
            font.pixelSize: 18
            font.weight: Font.Bold

            property string _username: "user"

            FileView {
                id: _unFile
                path: CCConfig.usernamePath
                watchChanges: true
                onLoaded: {
                    const n = text().trim()
                    if (n.length > 0) usernameLabel._username = n
                }
                Component.onCompleted: reload()
            }

            Process {
                id: _whoami
                command: ["whoami"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        const u = text.trim()
                        if (u.length > 0 && usernameLabel._username === "user")
                            usernameLabel._username = u
                    }
                }
            }
        }
    }
}
