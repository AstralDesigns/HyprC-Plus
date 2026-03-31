import QtQuick
import QtQuick.Layouts
import ".."

// ═══════════════════════════════════════════════════════════════════════════
//  BarNumericRow.qml — Reusable ±entry row for numeric bar config properties
// ═══════════════════════════════════════════════════════════════════════════

RowLayout {
    id: row
    spacing: 4

    property string propKey: ""
    property string propLabel: ""
    property int lo: 0
    property int hi: 100
    property string configPath: ""

    signal valueChanged(string key, string value)

    function setValue(v) {
        _entry.text = v
    }

    CCButton {
        Layout.preferredWidth: 26; label: "\u2212"
        onClicked: {
            let n = Math.max(row.lo, parseInt(_entry.text) - 1)
            _entry.text = n.toString()
            row.valueChanged(row.propKey, n.toString())
        }
    }
    CCEntry {
        id: _entry
        Layout.preferredWidth: 50
        text: ""
        onAccepted: {
            let n = parseInt(text)
            if (!isNaN(n) && n >= row.lo && n <= row.hi)
                row.valueChanged(row.propKey, n.toString())
        }
    }
    CCButton {
        Layout.preferredWidth: 26; label: "+"
        onClicked: {
            let n = Math.min(row.hi, parseInt(_entry.text) + 1)
            _entry.text = n.toString()
            row.valueChanged(row.propKey, n.toString())
        }
    }
    Text {
        text: row.propLabel
        color: CCTheme.cPrimary
        font.family: CCConfig.labelFont; font.pixelSize: 10
    }
}
