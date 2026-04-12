pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

Singleton {
    id: root
    property bool overviewOpen: false
    property bool superReleaseMightTrigger: true
    property real activeWindowStripScrollX: 0
    property int focusedWinIndex: -1   // -1 = none highlighted

    function resetStripScroll() {
        activeWindowStripScrollX = 0;
    }

    function resetWinFocus() {
        focusedWinIndex = -1;
    }
}
