import QtQuick

// ═══════════════════════════════════════════════════════════════════════════
//  CCSegmented.qml — pill segmented control (authored fresh, per plan).
//
//  Used by the launcher (Apps | Groups, Emojis | Glyphs) and any ControlCenter
//  rework. `options` is a list of { key, label } records (plain strings also
//  accepted — the key then equals the label). The active option is highlighted
//  with a Theme.cSurfaceTint pill; selection emits picked(key).
// ═══════════════════════════════════════════════════════════════════════════

Rectangle {
    id: root

    property var options: []           // [{key,label}] or ["label", …]
    property string current: ""        // active key
    signal picked(string key)

    readonly property real _h: 28
    height: _h
    radius: _h / 2
    implicitWidth: segRow.implicitWidth + 8
    color: Qt.rgba(Theme.cInversePrimary.r, Theme.cInversePrimary.g,
                   Theme.cInversePrimary.b, 0.28)
    border.width: 1
    border.color: Qt.rgba(Theme.cScrim.r, Theme.cScrim.g, Theme.cScrim.b, 0.5)

    function _keyOf(opt) {
        return (opt && typeof opt === "object") ? String(opt.key ?? opt.label ?? "")
                                                : String(opt)
    }
    function _labelOf(opt) {
        return (opt && typeof opt === "object") ? String(opt.label ?? opt.key ?? "")
                                                : String(opt)
    }

    Row {
        id: segRow
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.options
            delegate: Rectangle {
                id: seg
                required property var modelData
                readonly property string key: root._keyOf(modelData)
                readonly property bool active: root.current === key

                width: segText.implicitWidth + 22
                height: root._h - 6
                radius: height / 2
                color: active ? Theme.cSurfaceTint
                     : segMa.containsMouse
                       ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g,
                                 Theme.cPrimary.b, 0.10)
                       : "transparent"
                Behavior on color { ColorAnimation { duration: 140 } }

                Text {
                    id: segText
                    anchors.centerIn: parent
                    text: root._labelOf(modelData)
                    font.pixelSize: 11
                    font.bold: seg.active
                    color: seg.active ? Theme.cOnSecondary : Theme.cPrimary
                }

                MouseArea {
                    id: segMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // Emit only — never assign root.current here. The parent's
                        // `current:` binding is the single source of truth; an
                        // imperative write would break it so later programmatic
                        // changes (e.g. win.subTab after group create) stop
                        // moving the highlight.
                        root.picked(seg.key)
                    }
                }
            }
        }
    }
}
