pragma Singleton
import QtQuick

QtObject {
    id: root
    property bool   visible:   false
    property string text:      ""
    property bool   hasUpdates: false
    property int    anchorX:   0

    function open(x, txt, has)  { anchorX = x; text = txt; hasUpdates = has; visible = true  }
    function close()             { visible = false }
    function toggle(x, txt, has) { visible ? close() : open(x, txt, has) }
}
