pragma Singleton

import QtQuick
import Quickshell

QtObject {
    id: root
    property bool visible: false
    property bool widgetVisible: false
    property int widgetX: Quickshell.screens[0] ? Math.round((Quickshell.screens[0].width - 612) / 2) : 674
    property int widgetY: Quickshell.screens[0] ? (Quickshell.screens[0].height - 148 - 120) : 752

    function toggle() { root.visible = !root.visible }
    function open()   { root.visible = true  }
    function close()  { root.visible = false }

    function toggleWidget() { root.widgetVisible = !root.widgetVisible }
    function closeWidget()  { root.widgetVisible = false }
}
