import QtQuick
import Quickshell
import Quickshell.Wayland

// WorkspaceTileTooltip — floating tooltip for the per-window icons shown
// inside WorkspacesPopup. Rendered as its own top-level layer-shell surface
// (mirroring how WorkspacesPopup itself floats independently of the bar) so
// its size and position aren't constrained by WorkspacesPopup's small,
// tightly-content-fit window. Grows/shrinks with its text automatically.

PanelWindow {
    id: tip
    color: "transparent"
    visible: WorkspacesPopupState.tileTooltipVisible

    WlrLayershell.namespace: "quickshell"
    WlrLayershell.layer: WlrLayer.Overlay   // always render above other surfaces
    exclusionMode: ExclusionMode.Ignore

    readonly property bool _barAtBottom: Config.barPosition === "bottom"

    // Same bar-relative gap math WorkspacesPopup.qml uses, plus room to clear
    // that popup's own 32px height so the tooltip sits just beyond it.
    readonly property real _barGap: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginTop) : Config.outerMarginTop) + Config.barHeight + 4
    readonly property real _barGapBot: (Config.barMode === "shell" ? (Config.shellArmThickness + Config.outerMarginBottom) : Config.outerMarginBottom) + Config.barHeight + 4
    readonly property real _popupHeight: 32
    readonly property real _gapFromPopup: 6

    readonly property real _calcLeft: Math.max(4,
        WorkspacesPopupState.tileTooltipCenterX - (implicitWidth / 2))

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true }
    margins {
        top:    _barAtBottom ? 0 : (_barGap + _popupHeight + _gapFromPopup)
        bottom: _barAtBottom ? (_barGapBot + _popupHeight + _gapFromPopup) : 0
        left:   _calcLeft
    }

    implicitWidth:  tipText.implicitWidth + 20
    implicitHeight: tipText.implicitHeight + 10

    Rectangle {
        anchors.fill: parent
        radius: 7
        color: Theme.cOnSecondary

        Text {
            id: tipText
            anchors.centerIn: parent
            text: WorkspacesPopupState.tileTooltipText
            color: Theme.cPrimary
            font.family: Config.fontFamily
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
        }
    }
}
