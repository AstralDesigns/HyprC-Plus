pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// ═══════════════════════════════════════════════════════════════════════════
//  WeatherPopupState — singleton that owns:
//    • popup visibility toggle
//    • all weather data properties (current + hourly + 7-day forecast)
//    • the complete location → fetch → cache pipeline
//
//  Weather.qml calls WeatherPopupState.refresh() on every bar-module poll
//  tick. The popup binds directly to the properties here and therefore
//  always opens with data already populated — no loading delay on open.
// ═══════════════════════════════════════════════════════════════════════════
QtObject {
    id: root

    // ── Visibility ────────────────────────────────────────────────────────
    property bool visible: false
    property bool widgetVisible: false
    property int widgetX: 480
    property int widgetY: 100

    function toggle() { root.visible = !root.visible }
    function open()   { root.visible = true  }
    function close()  { root.visible = false }

    function toggleWidget() { root.widgetVisible = !root.widgetVisible }
    function closeWidget()  { root.widgetVisible = false }

    // ── File paths ────────────────────────────────────────────────────────
    readonly property string _pinnedLocFile: Quickshell.env("HOME") + "/.config/hyprcandy/weather-location.conf"
    readonly property string _locationCache: Quickshell.env("HOME") + "/.config/hyprcandy/waybar-weather-ipinfo.json"
    readonly property string _weatherCache:  Quickshell.env("HOME") + "/.config/hyprcandy/astal-weather-cache.json"

    // ── Location + unit state ─────────────────────────────────────────────
    property bool   _metric:   true
    property string city:      ""
    property real   _lat:      0
    property real   _lon:      0
    property bool   _locReady: false

    // Last raw API response kept in memory so unit toggles re-render
    // instantly from cached data without touching the network or disk
    property var    _lastRaw:  null

    // ── Current conditions ────────────────────────────────────────────────
    property string icon:    "󰖐"
    property string condStr: "Loading…"
    property string temp:    "--"
    property string feels:   "--"
    property string wind:    "--"
    property string hum:     "--"
    property string prec:    "--"

    // ── 7-day forecast ────────────────────────────────────────────────────
    property var fcDays:  []
    property var fcIcons: []
    property var fcHi:    []
    property var fcLo:    []

    // ── Hourly forecast (next 12 h) ───────────────────────────────────────
    property var hrTimes: []
    property var hrIcons: []
    property var hrTemps: []
    property var hrPrec:  []

    // ── Unit helpers ──────────────────────────────────────────────────────
    function _unitSuffix() { return _metric ? "°C" : "°F" }
    function _cvtTemp(c)   { return _metric ? Math.round(c) : Math.round(c * 9/5 + 32) }
    function _cvtWind(kmh) { return _metric ? Math.round(kmh) + " km/h" : Math.round(kmh * 0.621371) + " mph" }

    function _cond(code, isDay, h) {
        if (code===0)             return {t:'Clear Sky',             i:isDay?'☀️':'🌙'};
        if (code===1)             return {t:'Mainly Clear',          i:isDay?'☀️':'🌙'};
        if (code===2)             return {t:'Partly Cloudy',         i:isDay?'⛅':'☁️'};
        if (code===3)             return h>=90?{t:'Cloudy (Rainy)',i:isDay?'🌦️':'🌧️'}:{t:'Cloudy',i:isDay?'⛅':'☁️'};
        if (code===45||code===48) return {t:'Fog',              i:isDay?'🌫':'🌫'};
        if (code>=51)             return {t:'Rainy',            i:isDay?'🌦️':'🌧️'};
        if (code>=53)             return {t:'Moderate Drizzle', i:isDay?'🌦️':'🌧️'};
        if (code>=55)             return {t:'Dense Drizzle',    i:isDay?'🌦️':'🌧️'};
        if (code===56)            return {t:'Light Freezing Rain',   i:isDay?'🌦️':'🌧️'};
        if (code===57)            return {t:'Dense Freezing Drizzle',i:isDay?'🌦️':'🌧️'};
        if (code===61)            return {t:'Slight Rain',           i:isDay?'🌦️':'🌧️'};
        if (code===63)            return {t:'Moderate Rain',         i:isDay?'🌦️':'🌧️'};
        if (code===65)            return {t:'Heavy Rain',            i:'⛈️'};
        if (code===66||code===67) return {t:'Freezing Rain',         i:'⛈️'};
        if (code>=71&&code<=75)   return {t:code===71?'Light Snow':code===73?'Moderate Snow':'Heavy Snow',i:'❄️'};
        if (code===77)            return {t:'Snow Grains',           i:'🌨️'};
        if (code>=80&&code<=82)   return {t:'Rain Showers',          i:'🌨️'};
        if (code===85||code===86) return {t:'Snow Showers',          i:'🌨️'};
        if (code===95)            return {t:'Thunderstorm',          i:'⚡'};
        if (code===96||code===99) return {t:'Thunderstorm + Hail',   i:isDay?'⛈':'⛈'};
        return {t:'Unknown', i:'󰖐'};
    }

    // ── Apply a full open-meteo JSON response ─────────────────────────────
    function applyData(d) {
        _lastRaw = d          // cache in memory for instant unit re-renders
        let c = d.current
        
        // Use 15-minutely data for current conditions if available for better accuracy
        if (d.minutely_15) {
            const now = new Date().toISOString().slice(0, 16)
            let idx = d.minutely_15.time.findIndex(t => t >= now)
            if (idx === -1) idx = d.minutely_15.time.length - 1
            if (idx <= 0) {
                c.temperature_2m = d.minutely_15.temperature_2m[idx]
                c.weather_code = d.minutely_15.weather_code[idx]
            }
        }

        const info = _cond(c.weather_code, c.is_day, c.relative_humidity_2m)
        icon    = info.i
        condStr = info.t
        temp    = _cvtTemp(c.temperature_2m)       + _unitSuffix()
        feels   = _cvtTemp(c.apparent_temperature) + _unitSuffix()
        wind    = _cvtWind(c.wind_speed_10m)
        hum     = c.relative_humidity_2m + "%"
        prec    = (c.precipitation || 0) + " mm"

        if (d.daily) {
            const DAYS  = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            const dates = d.daily.time || []
            const dn=[]; const ic=[]; const hi=[]; const lo=[]
            for (let i = 0; i < Math.min(7, dates.length); i++) {
                const dt = new Date(dates[i] + "T12:00:00")
                dn.push(i === 0 ? "Today" : DAYS[dt.getDay()])
                ic.push(_cond(d.daily.weather_code[i], 1, 0).i)
                hi.push(_cvtTemp(d.daily.temperature_2m_max[i]) + _unitSuffix())
                lo.push(_cvtTemp(d.daily.temperature_2m_min[i]) + _unitSuffix())
            }
            fcDays = dn; fcIcons = ic; fcHi = hi; fcLo = lo
        }

        if (d.hourly) {
            const now  = new Date()
            const nowH = now.getFullYear() + "-" +
                String(now.getMonth()+1).padStart(2,"0") + "-" +
                String(now.getDate()).padStart(2,"0") + "T" +
                String(now.getHours()).padStart(2,"0") + ":00"
            const times = d.hourly.time || []
            let startIdx = times.findIndex(t => t >= nowH)
            if (startIdx < 0) startIdx = 0
            const ht=[]; const hi2=[]; const htp=[]; const hpr=[]
            for (let i = startIdx; i < Math.min(startIdx + 12, times.length); i++) {
                const h = parseInt(times[i].slice(11, 13))
                ht.push(h === 0 ? "12am" : h < 12 ? h+"am" : h === 12 ? "12pm" : (h-12)+"pm")
                const isD = (d.hourly.is_day || [])[i] ?? 1
                hi2.push(_cond((d.hourly.weather_code || [])[i] || 0, isD, 0).i)
                htp.push(_cvtTemp((d.hourly.temperature_2m || [])[i] || 0) + _unitSuffix())
                hpr.push(((d.hourly.precipitation_probability || [])[i] || 0) + "%")
            }
            hrTimes = ht; hrIcons = hi2; hrTemps = htp; hrPrec = hpr
        }
    }

    // ── Public entry point — called by Weather.qml on each poll tick ──────
    function refresh() {
        if (!_unitReadProc.running) _unitReadProc.running = true
    }

    // ── Public unit toggle (called by popup button and bar scroll wheel) ──
    // Flips _metric immediately, then re-renders from the in-memory raw
    // response if available — no network round-trip, no disk read.
    // Falls back to a full refresh only on the very first toggle before
    // any data has been fetched.
    function toggleUnit() {
        _metric = !_metric
        _unitToggleProc._nextUnit = _metric ? "metric" : "imperial"
        if (!_unitToggleProc.running) _unitToggleProc.running = true
        if (_lastRaw) applyData(_lastRaw)
    }

    // ── Pipeline: unit → location → (ipinfo?) → fetch → (cache fallback) ─

    property var _unitReadProc: Process {
        id: _unitReadProc
        command: ["bash", "-c", "cat /tmp/waybar-weather-unit 2>/dev/null || echo metric"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root._metric = this.text.trim() !== "imperial"
                _locReadProc.running = true
            }
        }
    }

    property var _locReadProc: Process {
        id: _locReadProc
        command: ["bash", "-c",
            "P=\"$1\"; C=\"$2\"; " +
            "if [ -f \"$P\" ]; then source \"$P\" 2>/dev/null && printf '%s,%s,%s' \"$LAT\" \"$LON\" \"$NAME\" && echo; " +
            "elif [ -f \"$C\" ]; then jq -r '(.loc)+\",\"+(.city//\"Unknown\")' \"$C\" 2>/dev/null; " +
            "else echo FETCH; fi",
            "--", root._pinnedLocFile, root._locationCache]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                if (!t || t === "FETCH") { _ipinfoProc.running = true; return }
                const p   = t.split(",")
                const lat = parseFloat(p[0])
                const lon = parseFloat(p[1])
                if (p.length >= 2 && !isNaN(lat) && lat !== 0) {
                    root._lat = lat; root._lon = lon
                    root.city = p.slice(2).join(",") || "Unknown"
                    root._locReady = true
                    _fetchProc._doFetch()
                } else {
                    _ipinfoProc.running = true
                }
            }
        }
    }

    property var _ipinfoProc: Process {
        id: _ipinfoProc
        command: ["bash", "-c",
            "curl -sf --max-time 8 https://ipinfo.io/json | tee \"$1\"",
            "--", root._locationCache]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    const c = (d.loc || "0,0").split(",")
                    root._lat  = parseFloat(c[0]) || 0
                    root._lon  = parseFloat(c[1]) || 0
                    root.city  = d.city || "Unknown"
                    root._locReady = true
                    _fetchProc._doFetch()
                } catch(e) {}
            }
        }
    }

    property var _fetchProc: Process {
        id: _fetchProc
        property string _url: ""
        command: ["bash", "-c",
            "curl -sf --max-time 12 \"$1\" | tee \"$2\"",
            "--", _fetchProc._url, root._weatherCache]
        running: false
        function _doFetch() {
            if (!root._locReady) return
            _url = "https://api.open-meteo.com/v1/forecast" +
                "?latitude="  + root._lat + "&longitude=" + root._lon +
                "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,precipitation" +
                "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
                "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
                "&minutely_15=temperature_2m,weather_code,is_day" +
                "&forecast_days=7&timezone=auto&models=best_match"
            if (!running) running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d && d.current) { root.applyData(d); return }
                } catch(e) {}
                // Live fetch failed — fall back to disk cache
                _cacheReadProc.running = true
            }
        }
    }

    property var _cacheReadProc: Process {
        id: _cacheReadProc
        command: ["bash", "-c", "cat \"$1\" 2>/dev/null", "--", root._weatherCache]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d && d.current) root.applyData(d)
                } catch(e) {}
            }
        }
    }

    property var _unitToggleProc: Process {
        id: _unitToggleProc
        property string _nextUnit: "metric"
        command: ["bash", "-c",
            "echo \"$1\" > /tmp/waybar-weather-unit", "--", _unitToggleProc._nextUnit]
        running: false
        // Only kick a full pipeline refresh when there's no cached data yet;
        // otherwise toggleUnit() already re-rendered from _lastRaw instantly
        onExited: { if (root._lastRaw === null && !_unitReadProc.running) _unitReadProc.running = true }
    }
}
