pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import "."

Variants {
    id: lockTransVariants
    model: Quickshell.screens

    PanelWindow {
        id: transWindow
        required property var modelData
        screen: modelData

        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell"
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        visible: LockTransitionState.active

        Rectangle {
            anchors.fill: parent
            color: Theme.blurBackground
            opacity: LockTransitionState.active ? 1.0 : 0.0
            Behavior on opacity {
                NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
            }
        }
    }
}
