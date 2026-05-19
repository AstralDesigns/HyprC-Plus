import QtQuick
import Quickshell
import Quickshell.Wayland

// A zero-size, permanently mapped layer-shell surface whose only purpose is
// to keep the IdleInhibitor Wayland protocol object alive even while the bar
// PanelWindow is hidden during autohide.
//
// Placed on WlrLayer.Background with exclusiveZone 0 so it claims no screen
// real-estate and never intercepts input.
PanelWindow {
    id: anchor

    // Zero size — invisible and non-interactive
    implicitWidth:  0
    implicitHeight: 0
    visible:        true

    WlrLayershell.layer:     WlrLayer.Background
    WlrLayershell.namespace: "quickshell:inhibitor-anchor"
    exclusiveZone:           0
    exclusionMode:           ExclusionMode.Ignore

    Component.onCompleted: InhibitorState._load()

    // The real protocol object — stays mapped as long as this window is visible.
    IdleInhibitor {
        window:  anchor
        enabled: InhibitorState.active
    }
}
