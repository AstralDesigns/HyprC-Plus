pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Events store + holiday fetch + reminder engine for the calendar Events popup.
QtObject {
    id: root

    // ── Paths ──────────────────────────────────────────────────────────────
    readonly property string _dir:         Quickshell.env("HOME") + "/.config/hyprcandy"
    readonly property string _eventsFile:  _dir + "/events.json"

    // ── State ──────────────────────────────────────────────────────────────
    property var    events:          []
    property var    holidays:        ({})          // "YYYY-MM-DD" -> name
    property string countryOverride: ""
    property string _detected:       ""
    readonly property string country: countryOverride !== "" ? countryOverride : _detected

    property var    _yearsLoaded:    []
    property var    _fired:          ({})
    property bool   _loaded:         false

    function pad(n) { return (n < 10 ? "0" : "") + n }
    function keyOf(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
    function dtOf(dateKey, time) {
        const p = dateKey.split("-").map(Number)
        const t = (time || "00:00").split(":").map(Number)
        return new Date(p[0], p[1] - 1, p[2], t[0] || 0, t[1] || 0, 0, 0)
    }

    // ── Init ───────────────────────────────────────────────────────────────
    function init() {
        if (_loaded) return
        mkdirProc.running = true
        // Provisional fallback from locale; tzProc refines it to the real country.
        const loc = Qt.locale().name || ""
        const parts = loc.split(/[_@.]/)
        _detected = (parts.length > 1 && parts[1].length === 2) ? parts[1].toUpperCase() : "US"
        tzProc.running = true
    }

    function _afterLoad() {
        _loaded = true
        ensureYear(new Date().getFullYear())
    }

    // ── Persistence ───────────────────────────────────────────────────────
    property var mkdirProc: Process { id: mkdirProc; command: ["bash", "-c", 'mkdir -p "$1"', "--", root._dir]; running: false }

    // Geographic country from the system timezone (/etc/localtime -> zone.tab).
    property var tzProc: Process {
        id: tzProc
        command: ["bash", "-c", "TZP=\"$(readlink -f /etc/localtime 2>/dev/null)\"; TZP=\"${TZP#/usr/share/zoneinfo/}\"; [ -n \"$TZP\" ] && awk -F'\\t' -v t=\"$TZP\" '$3==t{print $1; exit}' /usr/share/zoneinfo/zone.tab"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const cc = text.trim().toUpperCase()
                if (/^[A-Z]{2}$/.test(cc)) root._detected = cc
                root.loadProc.running = true
            }
        }
    }

    property var loadProc: Process {
        id: loadProc
        command: ["bash", "-c", 'cat "$1" 2>/dev/null', "--", root._eventsFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t) {
                    try {
                        const o = JSON.parse(t)
                        root.events = Array.isArray(o.events) ? o.events : []
                        root.countryOverride = o.country || ""
                    } catch (e) { root.events = [] }
                }
                root._afterLoad()
            }
        }
    }

    property var saveProc: Process {
        id: saveProc
        property string payload: ""
        command: ["bash", "-c", 'printf %s "$2" > "$1"', "--", root._eventsFile, payload]
        running: false
    }

    function save() {
        saveProc.payload = JSON.stringify({ version: 1, country: countryOverride, events: events })
        saveProc.running = false
        saveProc.running = true
    }

    // ── CRUD ───────────────────────────────────────────────────────────────
    function addEvent(o) {
        o.id = Date.now() + Math.floor(Math.random() * 1000)
        events = events.concat([o])
        save()
    }
    function updateEvent(id, o) {
        events = events.map(e => e.id === id ? Object.assign({}, e, o, { id: id }) : e)
        save()
    }
    function removeEvent(id) {
        events = events.filter(e => e.id !== id)
        save()
    }

    function setCountry(cc) {
        countryOverride = cc
        holidays = ({})
        _yearsLoaded = []
        save()
        ensureYear(new Date().getFullYear())
    }

    // ── Occurrence matching ────────────────────────────────────────────────
    function _matches(e, dateKey) {
        if (!e || !e.date) return false
        const rec = e.recurrence || "none"
        if (rec === "none") return e.date === dateKey
        if (dateKey < e.date) return false
        const a = e.date.split("-").map(Number)
        const b = dateKey.split("-").map(Number)
        const da = new Date(a[0], a[1] - 1, a[2])
        const db = new Date(b[0], b[1] - 1, b[2])
        switch (rec) {
            case "daily":   return true
            case "weekly":  return da.getDay() === db.getDay()
            case "monthly": return a[2] === b[2]
            case "yearly":  return a[1] === b[1] && a[2] === b[2]
            default:        return e.date === dateKey
        }
    }

    function eventsOn(dateKey) {
        return events.filter(e => _matches(e, dateKey))
    }

    function itemsFor(dateKey) {
        const h = holidays[dateKey]
        return { holidays: h ? [h] : [], events: eventsOn(dateKey) }
    }

    // ── Holidays (Nager.Date, cached to disk) ──────────────────────────────
    function ensureYear(year) {
        const cc = country
        if (!cc) return
        const key = cc + "-" + year
        if (_yearsLoaded.indexOf(key) >= 0) return
        _yearsLoaded = _yearsLoaded.concat([key])
        holidayProc.url   = "https://date.nager.at/api/v3/PublicHolidays/" + year + "/" + cc
        holidayProc.cache = _dir + "/holidays-" + key + ".json"
        holidayProc.running = false
        holidayProc.running = true
    }

    property var holidayProc: Process {
        id: holidayProc
        property string url: ""
        property string cache: ""
        command: ["bash", "-c",
            'U="$1"; C="$2"; curl -sf --max-time 12 "$U" -o "$C.tmp" && mv "$C.tmp" "$C"; cat "$C" 2>/dev/null',
            "--", url, cache]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (!t) return
                try {
                    const arr = JSON.parse(t)
                    if (!Array.isArray(arr)) return
                    const map = Object.assign({}, root.holidays)
                    for (const h of arr)
                        if (h && h.date) map[h.date] = h.localName || h.name || ""
                    root.holidays = map
                } catch (e) {}
            }
        }
    }

    // ── Reminder engine ────────────────────────────────────────────────────
    function _checkReminders() {
        const now = new Date()
        const todayKey = keyOf(now)
        const nf = {}
        for (const k in _fired) if (k.indexOf(todayKey + "|") === 0) nf[k] = true
        _fired = nf
        for (const e of eventsOn(todayKey)) {
            if (e.reminderMin === undefined || e.reminderMin < 0 || !e.time) continue
            const dt = dtOf(todayKey, e.time)
            const fireAt = dt.getTime() - (e.reminderMin | 0) * 60000
            const nowMs = now.getTime()
            const key = todayKey + "|" + e.id
            // Fire on the first tick at/after fireAt within a 2-min grace so a 60s
            // cadence always lands (the old `now < dt` bound blocked "At time").
            if (nowMs >= fireAt && nowMs - fireAt < 120000 && !_fired[key]) {
                _fired[key] = true
                _notify(e.title || "Event", e.time + (e.notes ? " - " + e.notes : ""))
            }
        }
    }

    function _notify(title, body) {
        notifyProc._t = title
        notifyProc._b = body
        notifyProc.running = false
        notifyProc.running = true
    }

    property var notifyProc: Process {
        id: notifyProc
        property string _t: ""
        property string _b: ""
        command: ["notify-send", "-a", "Events", "-i", "dialog-calendar", _t, _b]
        running: false
    }

    property var reminderTimer: Timer {
        interval: 60000
        running: root._loaded
        repeat: true
        onTriggered: root._checkReminders()
    }
}
