import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."

Item {
    id: root
    Layout.alignment: Qt.AlignVCenter
    implicitWidth: Config.moduleHeight
    implicitHeight: Config.moduleHeight

    // This button sits at the trailing (right) edge, so nudge its tooltip left by
    // the active mode's side margin to keep the popup off the screen edge.
    readonly property real _tipMargin: Config.barMode === "shell" ? Config.popupSideMargin * 3 : Config.popupSideMargin * 2

    Process {
        id: smProc
        command: [Config.scriptsDir + "/startmenu.sh"]
        running: false
    }

    // Single power glyph; every StartMenu visibility change (button toggle open/
    // close, backdrop click, or Esc) spins it a further 180° in the same direction.
    Text {
        id: powerText
        property real _spin: 0
        anchors.centerIn: parent
        text: ""
        color: Config.powerGlyphColor
        font.family: Config.fontFamily
        font.pixelSize: Config.fontSize
        transformOrigin: Item.Center
        rotation: _spin
        Behavior on rotation { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }

        Connections {
            target: StartMenuState
            function onMenuVisibleChanged() { powerText._spin += 180 }
        }
    }

    opacity: ma.containsMouse ? 0.7 : 1.0
    Behavior on opacity { NumberAnimation { duration: 80 } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (Config.tipPower) BarTipState.show("Left-click: Start menu", parent, -root._tipMargin)
        onExited: BarTipState.hide(parent)
        onClicked: {
            if (!smProc.running) smProc.running = true
        }
    }
}
