import QtQuick
import QtQuick.Layouts
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  ImagePicker.qml — Internal file browser for selecting a user icon image.
//  Since the control center is a layer shell (no native file dialog),
//  this provides an in-panel directory browser that lists image files.
//  Selected images are processed via ImageMagick (magick) to create a
//  128×128 center-cropped PNG saved to ~/.config/hyprcandy/user-icon.png.
// ═══════════════════════════════════════════════════════════════════════════

Item {
    id: picker
    implicitWidth: parent ? parent.width : 300
    implicitHeight: parent ? parent.height : 500

    property string currentDir: CCConfig.home
    property var fileList: []
    property bool loading: false

    // ── Directory listing process ────────────────────────────────────────
    Process {
        id: lsProc
        command: ["bash", "-c",
            "echo 'DIR:..'; " +
            "for f in \"" + picker.currentDir + "\"/*; do " +
            "  if [ -d \"$f\" ]; then echo \"DIR:$(basename \"$f\")\"; " +
            "  elif echo \"$f\" | grep -qiE '\\.(png|jpg|jpeg|webp|bmp|gif|svg|tiff)$'; then echo \"IMG:$(basename \"$f\")\"; fi; " +
            "done 2>/dev/null || true"
        ]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                let entries = []
                const lines = text.trim().split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i].trim()
                    if (line.startsWith("DIR:")) {
                        entries.push({ name: line.substring(4), isDir: true, isImg: false })
                    } else if (line.startsWith("IMG:")) {
                        entries.push({ name: line.substring(4), isDir: false, isImg: true })
                    }
                }
                picker.fileList = entries
                picker.loading = false
            }
        }
    }

    function refresh() {
        loading = true
        fileList = []
        lsProc.running = true
    }

    function navigateTo(dir) {
        if (dir === "..") {
            const parts = currentDir.split("/")
            if (parts.length > 2) {
                parts.pop()
                currentDir = parts.join("/")
            } else {
                currentDir = "/"
            }
        } else {
            currentDir = currentDir + "/" + dir
        }
        refresh()
    }

    function selectImage(filename) {
        const fullPath = currentDir + "/" + filename
        magickProc._src = fullPath
        magickProc.running = true
    }

    // ── ImageMagick process ──────────────────────────────────────────────
    Process {
        id: magickProc
        property string _src: ""
        command: ["magick", magickProc._src,
                  "-resize", "128x128^", "-gravity", "center",
                  "-extent", "128x128", CCConfig.userIconPath]
        running: false
        onExited: {
            // Go back to the main view after picking
            ControlCenterState.switchTab("")
        }
    }

    Component.onCompleted: refresh()

    // ── UI ───────────────────────────────────────────────────────────────
    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 4

        // Header with back button
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            // Back to main menu
            Rectangle {
                width: 28; height: 28; radius: 6
                color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.1)
                Text {
                    anchors.centerIn: parent
                    text: "\uf060"
                    font.family: CCConfig.fontFamily; font.pixelSize: 14
                    color: CCTheme.cPrimary
                }
                MouseArea {
                    anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                    onClicked: ControlCenterState.switchTab("")
                }
            }

            Text {
                Layout.fillWidth: true
                text: "Select User Icon"
                color: CCTheme.cPrimary
                font.family: CCConfig.labelFont
                font.pixelSize: 14; font.weight: Font.Bold
                elide: Text.ElideMiddle
            }
        }

        // Current path display
        Rectangle {
            Layout.fillWidth: true
            height: 24; radius: 6
            color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.06)
            Text {
                anchors.fill: parent; anchors.margins: 4
                text: picker.currentDir
                color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.6)
                font.family: CCConfig.labelFont; font.pixelSize: 10
                elide: Text.ElideLeft; verticalAlignment: Text.AlignVCenter
            }
        }

        // Home shortcut buttons
        RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Repeater {
                model: [
                    { label: "\uf015 Home", path: CCConfig.home },
                    { label: "\uf03e Pictures", path: CCConfig.home + "/Pictures" },
                    { label: "\uf019 Downloads", path: CCConfig.home + "/Downloads" }
                ]
                Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 24; radius: 6
                    color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.08)
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: CCTheme.cPrimary
                        font.family: CCConfig.labelFont; font.pixelSize: 9
                    }
                    MouseArea {
                        anchors.fill: parent; cursorShape: Qt.PointingHandCursor
                        onClicked: { picker.currentDir = modelData.path; picker.refresh() }
                    }
                }
            }
        }

        // File list
        ListView {
            id: fileListView
            Layout.fillWidth: true; Layout.fillHeight: true
            clip: true; spacing: 2

            model: picker.fileList

            delegate: Rectangle {
                required property var modelData
                required property int index
                width: fileListView.width
                height: 32; radius: 6
                color: ma.containsMouse
                    ? Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.12)
                    : Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.04)

                RowLayout {
                    anchors.fill: parent; anchors.margins: 4; spacing: 6

                    Text {
                        text: modelData.isDir ? "\uf07b" : "\uf03e"
                        font.family: CCConfig.fontFamily; font.pixelSize: 14
                        color: modelData.isDir ? CCTheme.cPrimary : CCTheme.cTertiary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: modelData.name
                        color: CCTheme.cPrimary
                        font.family: CCConfig.labelFont; font.pixelSize: 11
                        elide: Text.ElideRight
                    }

                    // Image preview thumbnail for image files
                    Image {
                        visible: modelData.isImg
                        source: modelData.isImg ? "file://" + picker.currentDir + "/" + modelData.name : ""
                        Layout.preferredWidth: 24; Layout.preferredHeight: 24
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent; hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (modelData.isDir) {
                            picker.navigateTo(modelData.name)
                        } else if (modelData.isImg) {
                            picker.selectImage(modelData.name)
                        }
                    }
                }
            }

            // Empty state
            Text {
                anchors.centerIn: parent
                visible: picker.fileList.length === 0 && !picker.loading
                text: "No images or folders found"
                color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.4)
                font.family: CCConfig.labelFont; font.pixelSize: 12
            }

            // Loading indicator
            Text {
                anchors.centerIn: parent
                visible: picker.loading
                text: "Loading..."
                color: CCTheme.cPrimary
                font.family: CCConfig.labelFont; font.pixelSize: 12
            }
        }
    }
}
