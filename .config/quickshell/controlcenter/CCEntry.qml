import QtQuick
import QtQuick.Controls

// Reusable text entry matching candy-utils .cc-entry style
TextField {
    id: entry
    height: 26
    leftPadding: 6; rightPadding: 6
    font.family: CCConfig.labelFont
    font.pixelSize: 12
    color: CCTheme.cPrimary
    selectionColor: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.3)
    selectedTextColor: CCTheme.cPrimary
    verticalAlignment: Text.AlignVCenter

    background: Rectangle {
        radius: 6
        color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.06)
        border.width: entry.activeFocus ? 2 : 1
        border.color: entry.activeFocus
            ? CCTheme.cPrimaryFixedDim
            : Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.15)
    }
}
