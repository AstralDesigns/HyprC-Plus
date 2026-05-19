pragma Singleton

import QtQuick

// State singleton for the system-tray dropdown popup.
// The tray toggle button in the grouped island calls toggle(anchorX).
// SysTrayPopup.qml reads this to know when/where to render.
QtObject {
    id: root

    property bool visible:  false
    property int  anchorX:  0   // screen-space X of the toggle button centre

    function open(x)         { anchorX = x; visible = true  }
    function close()         { visible = false               }
    function toggle(x)       { visible ? close() : open(x)  }
}
