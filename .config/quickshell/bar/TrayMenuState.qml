pragma Singleton

import QtQuick

// State singleton for the custom styled tray context menu popup.
// Call TrayMenuState.open(menuHandle, screenX) from SystemTray.qml;
// TrayMenuPopup.qml reads this to render the menu.
QtObject {
    id: root

    property bool visible: false
    property var  menu:    null    // QsMenuHandle from the tray item
    property int  anchorX: 0      // horizontal screen-space hint

    function open(menuHandle, x) {
        menu    = menuHandle
        anchorX = x
        visible = true
    }

    function close() {
        visible = false
    }
}
