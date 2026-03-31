import QtQuick

// Reusable button component matching candy-utils .cc-btn style
Rectangle {
    id: btn
    property string label: ""
    property bool active: false
    signal clicked()

    height: 26; radius: 6
    color: active
        ? Qt.rgba(CCTheme.cInversePrimary.r, CCTheme.cInversePrimary.g, CCTheme.cInversePrimary.b, 0.7)
        : Qt.rgba(CCTheme.cInversePrimary.r, CCTheme.cInversePrimary.g, CCTheme.cInversePrimary.b, 0.5)
    border.width: active ? 2 : 1
    border.color: active
        ? Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.7)
        : Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.15)

    Text {
        anchors.centerIn: parent
        text: btn.label
        color: CCTheme.cPrimary
        font.family: CCConfig.labelFont
        font.pixelSize: 12
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: btn.clicked()
    }

    states: State {
        when: ma.containsMouse
        PropertyChanges {
            target: btn
            color: Qt.rgba(CCTheme.cPrimary.r, CCTheme.cPrimary.g, CCTheme.cPrimary.b, 0.12)
        }
    }
}
