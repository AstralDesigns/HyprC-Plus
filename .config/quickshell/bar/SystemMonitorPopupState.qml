pragma Singleton

import QtQuick

QtObject {
    id: root
    property bool visible: false
    property bool widgetVisible: false
    property int widgetX: 72
    property int widgetY: 480

    function toggle() { root.visible = !root.visible }
    function open()   { root.visible = true  }
    function close()  { root.visible = false }

    function toggleWidget() { root.widgetVisible = !root.widgetVisible }
    function closeWidget()  { root.widgetVisible = false }
}
