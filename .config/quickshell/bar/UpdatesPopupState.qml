pragma Singleton
import QtQuick

QtObject {
    id: root

    // ── System updates ────────────────────────────────────────────────────────
    property bool   visible:    false
    property string text:       ""
    property bool   hasUpdates: false
    property int    anchorX:    0

    // ── HyprCandy Plus updates ────────────────────────────────────────────────
    property bool   hcHasUpdates: false
    property string hcTooltip:    ""
    property bool   hcNoStore:    false

    // ── Signal fired after an update completes to trigger immediate rescan ────
    signal rescanRequested()

    // ── Lifecycle ─────────────────────────────────────────────────────────────
    function open(x, txt, has) {
        anchorX    = x
        text       = txt
        hasUpdates = has
        visible    = true
    }
    function close()              { visible = false }
    function toggle(x, txt, has) { visible ? close() : open(x, txt, has) }

    // Called by Updates.qml whenever the HC check script emits a result
    function updateHC(hasUp, tooltip, noStore) {
        hcHasUpdates = hasUp
        hcTooltip    = tooltip
        hcNoStore    = noStore
    }

    // Called by UpdatesPopup after either update process completes
    function requestRescan() { rescanRequested() }
}
