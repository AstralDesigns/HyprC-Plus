import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../../common"
import "../../common/functions"
import "../../services"

Item { // Window
    id: root
    property var toplevel
    property var windowData
    property var monitorData
    property var scale
    property var availableWorkspaceWidth
    property var availableWorkspaceHeight
    property bool restrictToWorkspace: true
    property real initX: ((windowData?.at[0] ?? 0) - (monitorData?.x ?? 0) - (monitorData?.reserved?.[0] ?? 0)) * root.scale + xOffset
    property real initY: Math.max(((windowData?.at[1] ?? 0) - (monitorData?.y ?? 0) - (monitorData?.reserved?.[1] ?? 0)) * root.scale, 0) + yOffset
    property real xOffset: 0
    property real yOffset: 0
    property int widgetMonitorId: 0
    
    property var targetWindowWidth: (windowData?.size[0] ?? 100) * scale
    property var targetWindowHeight: (windowData?.size[1] ?? 100) * scale
    property bool hovered: false
    property bool pressed: false

    property var iconToWindowRatio: 0.25
    property var xwaylandIndicatorToIconRatio: 0.35
    property var iconToWindowRatioCompact: 0.45
    property var entry: DesktopEntries.heuristicLookup(windowData?.class)
    property var iconPath: Quickshell.iconPath(entry?.icon ?? windowData?.class ?? "application-x-executable", "image-missing")
    property bool compactMode: {
        const w = root.restrictToWorkspace ? targetWindowWidth  : root.width;
        const h = root.restrictToWorkspace ? targetWindowHeight : root.height;
        return Appearance.font.pixelSize.smaller * 4 > h || Appearance.font.pixelSize.smaller * 4 > w;
    }

    property bool indicateXWayland: windowData?.xwayland ?? false

    // True when window is scrolled far enough off-screen that screencopy
    // won't have a frame for it (Hyprland doesn't capture off-screen windows)
    property bool offScreen: {
        if (!monitorData || !windowData) return false
        const monResL = monitorData.reserved?.[0] ?? 0
        const monResT = monitorData.reserved?.[1] ?? 0
        const monW = (monitorData.width  ?? 1366) / (monitorData.scale ?? 1)
        const monH = (monitorData.height ?? 768)  / (monitorData.scale ?? 1)
        const winX = (windowData.at?.[0] ?? 0) - (monitorData.x ?? 0)
        const winY = (windowData.at?.[1] ?? 0) - (monitorData.y ?? 0)
        return winX + (windowData.size?.[0] ?? 0) <= 0
            || winX >= monW
            || winY + (windowData.size?.[1] ?? 0) <= 0
            || winY >= monH
    }

    // In cell mode (restrictToWorkspace: false) the parent Item has the correct
    // size already; we sit at origin and fill it.  In workspace-overlay mode we
    // position ourselves from window coordinates.
    x: restrictToWorkspace ? initX : 0
    y: restrictToWorkspace ? initY : 0
    width: restrictToWorkspace ? Math.min((windowData?.size[0] ?? 100) * root.scale, availableWorkspaceWidth) : (parent?.width ?? 100)
    height: restrictToWorkspace ? Math.min((windowData?.size[1] ?? 100) * root.scale, availableWorkspaceHeight) : (parent?.height ?? 100)
    opacity: (windowData?.monitor ?? -1) == widgetMonitorId ? 1 : 0.4

    clip: true

    Behavior on x {
        enabled: root.restrictToWorkspace && !root.pressed
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on y {
        enabled: root.restrictToWorkspace && !root.pressed
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on width {
        enabled: root.restrictToWorkspace && !root.pressed
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }
    Behavior on height {
        enabled: root.restrictToWorkspace && !root.pressed
        animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
    }

    // Off-screen fallback: shown when screencopy has no frame (window beyond monitor)
    Rectangle {
        visible: root.offScreen
        anchors.fill: parent
        radius: Appearance.rounding.windowRounding * root.scale
        color: root.hovered
            ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7)
            : ColorUtils.transparentize(Appearance.colors.colLayer2)
        border.color: ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 2

            Item { Layout.fillHeight: true }

            Image {
                property real iconSize: Math.min(parent.width * 0.55, root.height * 0.45)
                Layout.alignment: Qt.AlignHCenter
                source: root.iconPath
                width: iconSize
                height: iconSize
                sourceSize: Qt.size(iconSize, iconSize)
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignHCenter
                horizontalAlignment: Text.AlignHCenter
                text: root.windowData?.title ?? root.windowData?.class ?? ""
                font.pixelSize: Math.max(Appearance.font.pixelSize.smaller * root.scale * 8, 7)
                elide: Text.ElideRight
                color: Appearance.colors.colOnLayer1
            }

            Item { Layout.fillHeight: true }
        }
    }

    ScreencopyView {
        id: windowPreview
        visible: !root.offScreen
        anchors.fill: parent
        captureSource: root.toplevel
        live: true

        Rectangle {
            anchors.fill: parent
            radius: Appearance.rounding.windowRounding * root.scale
            color: pressed ? ColorUtils.transparentize(Appearance.colors.colLayer2Active, 0.5) : 
                hovered ? ColorUtils.transparentize(Appearance.colors.colLayer2Hover, 0.7) : 
                ColorUtils.transparentize(Appearance.colors.colLayer2)
            border.color : ColorUtils.transparentize(Appearance.m3colors.m3outline, 0.7)
            border.width : 1
        }

        ColumnLayout {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            spacing: Appearance.font.pixelSize.smaller * 0.5

            Image {
                id: windowIcon
                property var iconSize: {
                    const w = root.restrictToWorkspace ? targetWindowWidth : root.width;
                    const h = root.restrictToWorkspace ? targetWindowHeight : root.height;
                    return Math.min(w, h) * (root.compactMode ? root.iconToWindowRatioCompact : root.iconToWindowRatio) / (root.monitorData?.scale ?? 1);
                }
                Layout.alignment: Qt.AlignHCenter
                source: root.iconPath
                width: iconSize
                height: iconSize
                sourceSize: Qt.size(iconSize, iconSize)

                Behavior on width {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on height {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
            }
        }
    }
}
