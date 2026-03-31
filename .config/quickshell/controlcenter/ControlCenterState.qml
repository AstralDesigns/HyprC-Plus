pragma Singleton

import QtQuick

QtObject {
    id: root

    property bool visible: false
    property string activeTab: ""

    function toggle() {
        visible = !visible
    }

    function show() {
        visible = true
    }

    function close() {
        visible = false
    }

    function switchTab(tabId) {
        if (activeTab === tabId) {
            activeTab = ""
        } else {
            activeTab = tabId
        }
    }
}
