pragma Singleton

import QtQuick

QtObject {
    property bool visible:       false
    property bool widgetVisible: false
    property int  widgetX:       120
    property int  widgetY:       160

    function toggle()       { visible       = !visible }
    function close()        { visible       = false }
    function toggleWidget() { widgetVisible = !widgetVisible }
    function closeWidget()  { widgetVisible = false }
}
