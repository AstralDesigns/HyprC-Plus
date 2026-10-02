// Phase-0 spike: verify QtWebEngine composites + accepts input inside a
// quickshell layer-shell overlay surface. Gated by env HYPRCANDY_QS_WEBENGINE_SMOKE=1
// (see shell.qml). Removed or kept dormant once the web tabs land.
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import QtWebEngine

PanelWindow {
    id: spike
    WlrLayershell.namespace: "hyprcandy-qsmoke"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    color: "transparent"
    implicitWidth: 800
    implicitHeight: 600
    anchors { top: true; left: true }

    Rectangle {
        anchors.fill: parent
        color: "#202028"
        Text {
            anchors { top: parent.top; left: parent.left; margins: 6 }
            text: "QtWebEngine spike — check input & compositing"
            color: "#e0e0e0"
        }
        WebEngineView {
            id: view
            anchors { top: parent.top; left: parent.left; right: parent.right; bottom: parent.bottom; margins: 34 }
            url: "https://example.com"
            // Qt 6.11 API: bool `loading` + loadingChanged(QWebEngineLoadingInfo).
            onLoadingChanged: console.log("[qsmoke] loading=" + view.loading
                + " progress=" + view.loadProgress + " title=" + view.title)
            onTitleChanged: console.log("[qsmoke] title: " + view.title)
            onRenderProcessTerminated: (status, code) => console.log("[qsmoke] render process terminated: " + status + " " + code)
        }
    }

    // Self-destruct after 25 s so an unattended smoke run does not linger.
    Timer { interval: 25000; running: true; onTriggered: Quickshell.exit(0) }
}
