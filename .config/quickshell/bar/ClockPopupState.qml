pragma Singleton

import QtQuick
import Quickshell

QtObject {
    property bool visible: false
    property bool widgetVisible: false
    property int widgetX: Quickshell.screens[0] ? Math.round((Quickshell.screens[0].width - 156) / 2) : 900
    property int widgetY: 60

    function toggle() { visible = !visible }
    function close()  { visible = false }

    function toggleWidget() { widgetVisible = !widgetVisible }
    function closeWidget()  { widgetVisible = false }
}
