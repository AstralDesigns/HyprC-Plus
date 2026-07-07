import QtQuick
import QtQuick.Layouts
import ".."

Rectangle {
    id: pp
    required property string pLabel
    required property string pProfile
    required property string pMac
    height: 22; radius: 6; implicitWidth: ppLbl.implicitWidth + 16

    readonly property bool _active: {
        const profile = StartMenuState.btActiveProfile[pMac]
        if (!profile) return false
        return profile.includes(pProfile.replace(/-/g, "_") || pProfile)
    }

    color: pph.containsMouse ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
        : pp._active ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.25)
        : Qt.rgba(Theme.cSurfHi.r, Theme.cSurfHi.g, Theme.cSurfHi.b, 0.8)
    border.width: 1
    border.color: pp._active ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.6)
        : Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.3)
    Behavior on color { ColorAnimation { duration: 100 } }

    Text {
        id: ppLbl; anchors.centerIn: parent
        text: pp.pLabel; font.pixelSize: 10; font.family: Config.fontFamily
        color: pp._active ? Theme.cPrimary : Theme.cOnSurfVar
    }
    MouseArea { id: pph; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
        onClicked: StartMenuState.btSetProfile(pp.pMac, pp.pProfile) }
}
