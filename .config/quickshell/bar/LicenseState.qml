pragma Singleton

import QtQuick
import QtCore
import Quickshell.Io

// ── HyprCandy+ LicenseState ───────────────────────────────────────────────
// Single source of truth for activation status.
// Read by shell.qml Loader gates and CC tab-forcing logic.
// Written by ControlCenterPopup when Gumroad verification succeeds/fails.
//
// On deactivate (or first load when not active) we also write activeTab=6
// directly into hyprcandy-bar.conf via sed so the CC opens on the activation
// tab even before QML's onVisibleChanged has a chance to run.

QtObject {
    id: root

    // Persisted licence settings — same category as ControlCenterPopup so
    // both singletons read/write the same underlying QSettings keys.
    property var _s: Settings {
        category: "cc-license-v1"
        property string licenseStatus: ""
    }

    // The one property everything else reads
    readonly property bool activated: _s.licenseStatus === "active"

    // sed the [cc-tabs-v1] activeTab key in hyprcandy-bar.conf so QSettings
    // picks up tab 6 on the next QS start before any QML onCompleted runs.
    property var _tabProc: Process {
        id: _tabProc
        running: false
        onExited: running = false
    }

    function _forceTab6() {
        _tabProc.command = [
            "bash", "-c",
            "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
            "sed -i 's/^activeTab=.*/activeTab=6/' \"$f\""
        ]
        _tabProc.running = true
    }

    function _clearTab6() {
        // Return to Bar tab (idx 0) after successful activation
        _tabProc.command = [
            "bash", "-c",
            "f=\"$HOME/.config/hyprcandy/hyprcandy-bar.conf\"; " +
            "sed -i 's/^activeTab=.*/activeTab=0/' \"$f\""
        ]
        _tabProc.running = true
    }

    // Called by ControlCenterPopup after a successful Gumroad verification
    function activate() {
        _s.licenseStatus = "active"
        _clearTab6()
    }

    // Called by ControlCenterPopup after a failed/revoked verification
    function deactivate() {
        _s.licenseStatus = "invalid"
        _forceTab6()
    }

    // On startup: if not activated, ensure the conf already points at tab 6
    Component.onCompleted: {
        if (_s.licenseStatus !== "active") _forceTab6()
    }
}
