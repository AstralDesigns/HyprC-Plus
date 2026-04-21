pragma Singleton

import QtQuick

QtObject {
    id: root
    property bool visible: false
    function toggle() { root.visible = !root.visible }
    function open()   { root.visible = true  }
    function close()  { root.visible = false }
}
