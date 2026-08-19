pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

ShellRoot {
    id: root

    // ── Matugen colors ──────────────────────────────────────────────────────
    property string _m3sourceColor:	     ""
    property string _m3primary:              ""
    property string _m3primaryContainer:     ""
    property string _m3onPrimary:            ""
    property string _m3background:           ""
    property string _m3inversePrimary:       ""
    property string _m3surfaceContainerHigh: ""
    property string _m3onSurface:            ""
    property string _m3onSurfaceVariant:     ""
    property string _m3outlineVariant:       ""
    property string _m3error:                ""
    property string _m3primaryFixedDim:      ""
    property string _m3secondary:            ""
    property string _m3secondaryContainer:   ""
    property string _m3onSecondary:          ""
    property string _m3tertiary:             ""
    property string _m3onTertiary:           ""
    property string _m3secondaryFixedDim:    ""
    property string _m3tertiaryFixedDim:     ""
    property string _m3scrim:                ""

    readonly property color cSourceColor:	Qt.color(_m3sourceColor)
    readonly property color cPrimary:           Qt.color(_m3primary)
    readonly property color cOnPrimary:         Qt.color(_m3onPrimary)
    readonly property color cPrimaryContainer:  Qt.color(_m3primaryContainer)
    readonly property color cOnSurf:            Qt.color(_m3onSurface)
    readonly property color cOnSurfVar:         Qt.color(_m3onSurfaceVariant)
    readonly property color cBg:                Qt.color(_m3background)
    readonly property color cInvPrimary:        Qt.color(_m3inversePrimary)
    readonly property color cSurfHi:            Qt.color(_m3surfaceContainerHigh)
    readonly property color cOutVar:            Qt.color(_m3outlineVariant)
    readonly property color cErr:               Qt.color(_m3error)
    readonly property color cPrimFixedDim:      Qt.color(_m3primaryFixedDim)
    readonly property color cSecondary:         Qt.color(_m3secondary)
    readonly property color cSecondaryContainer:Qt.color(_m3secondaryContainer)
    readonly property color cOnSecondary:       Qt.color(_m3onSecondary)
    readonly property color cTertiary:          Qt.color(_m3tertiary)
    readonly property color cSecondaryFixedDim: Qt.color(_m3secondaryFixedDim)
    readonly property color cTertiaryFixedDim:  Qt.color(_m3tertiaryFixedDim)
    readonly property color cScrim:             Qt.color(_m3scrim)

    // Outer panel tint
    readonly property color cPanel: Qt.rgba(
        Qt.color(_m3inversePrimary).r, Qt.color(_m3inversePrimary).g,
        Qt.color(_m3inversePrimary).b, 0.55)
    // Sub-card backgrounds
    readonly property color cCardDark: Qt.rgba(
        Qt.color(_m3background).r, Qt.color(_m3background).g,
        Qt.color(_m3background).b, 0.6)
    readonly property color cCardWarm: Qt.rgba(
        Qt.color(_m3onSecondary).r, Qt.color(_m3onSecondary).g,
        Qt.color(_m3onSecondary).b, 0.65)

    function parseColors(t) {
        const re=/property color (\w+): "(#[0-9a-fA-F]+)"/g; let m
        while((m=re.exec(t))!==null) switch(m[1]) {
            case "m3sourceColor":   	   root._m3sourceColor=m[2]; break
            case "m3primary":              root._m3primary=m[2]; break
            case "m3primaryContainer":     root._m3primaryContainer=m[2]; break
            case "m3onPrimary":            root._m3onPrimary=m[2]; break
            case "m3background":           root._m3background=m[2]; break
            case "m3inversePrimary":       root._m3inversePrimary=m[2]; break
            case "m3surfaceContainerHigh": root._m3surfaceContainerHigh=m[2]; break
            case "m3onSurface":            root._m3onSurface=m[2]; break
            case "m3onSurfaceVariant":     root._m3onSurfaceVariant=m[2]; break
            case "m3outlineVariant":       root._m3outlineVariant=m[2]; break
            case "m3error":                root._m3error=m[2]; break
            case "m3primaryFixedDim":      root._m3primaryFixedDim=m[2]; break
            case "m3secondary":            root._m3secondary=m[2]; break
            case "m3secondaryContainer":   root._m3secondaryContainer=m[2]; break
            case "m3onSecondary":          root._m3onSecondary=m[2]; break
            case "m3tertiary":             root._m3tertiary=m[2]; break
            case "m3onTertiary":           root._m3onTertiary=m[2]; break
            case "m3secondaryFixedDim":    root._m3secondaryFixedDim=m[2]; break
            case "m3tertiaryFixedDim":     root._m3tertiaryFixedDim=m[2]; break
            case "m3scrim":                root._m3scrim=m[2]; break
        }
    }
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME")||(Quickshell.env("HOME")+"/.cache"))+"/quickshell/wallpaper/MatugenColors.qml"
        watchChanges:true; onFileChanged:reload(); onLoaded:root.parseColors(text())
    }

    // ── Wallust colors ──────────────────────────────────────────────────────
    property string _wc0:  ""
    property string _wc1:  ""
    property string _wc2:  ""
    property string _wc3:  ""
    property string _wc4:  ""
    property string _wc5:  ""
    property string _wc6:  ""
    property string _wc7:  ""
    property string _wc8:  ""
    property string _wc9:  ""
    property string _wc10: ""
    property string _wc11: ""
    property string _wc12: ""
    property string _wc13: ""
    property string _wc14: ""
    property string _wc15: ""

    readonly property color cWc0:  Qt.color(_wc0)
    readonly property color cWc1:  Qt.color(_wc1)
    readonly property color cWc2:  Qt.color(_wc2)
    readonly property color cWc3:  Qt.color(_wc3)
    readonly property color cWc4:  Qt.color(_wc4)
    readonly property color cWc5:  Qt.color(_wc5)
    readonly property color cWc6:  Qt.color(_wc6)
    readonly property color cWc7:  Qt.color(_wc7)
    readonly property color cWc8:  Qt.color(_wc8)
    readonly property color cWc9:  Qt.color(_wc9)
    readonly property color cWc10: Qt.color(_wc10)
    readonly property color cWc11: Qt.color(_wc11)
    readonly property color cWc12: Qt.color(_wc12)
    readonly property color cWc13: Qt.color(_wc13)
    readonly property color cWc14: Qt.color(_wc14)
    readonly property color cWc15: Qt.color(_wc15)

    function parseWallustColors(t) {
        if (!t || t.length === 0) return
        const re = /property color m3color(\d+):\s*"(#[0-9a-fA-F]{6,8})"/g
        let m
        while ((m = re.exec(t)) !== null) {
            const n = parseInt(m[1])
            const hex = m[2]
            switch (n) {
                case 0:  root._wc0  = hex; break
                case 1:  root._wc1  = hex; break
                case 2:  root._wc2  = hex; break
                case 3:  root._wc3  = hex; break
                case 4:  root._wc4  = hex; break
                case 5:  root._wc5  = hex; break
                case 6:  root._wc6  = hex; break
                case 7:  root._wc7  = hex; break
                case 8:  root._wc8  = hex; break
                case 9:  root._wc9  = hex; break
                case 10: root._wc10 = hex; break
                case 11: root._wc11 = hex; break
                case 12: root._wc12 = hex; break
                case 13: root._wc13 = hex; break
                case 14: root._wc14 = hex; break
                case 15: root._wc15 = hex; break
            }
        }
    }
    FileView {
        path: (Quickshell.env("XDG_CACHE_HOME")||(Quickshell.env("HOME")+"/.cache"))+"/quickshell/wallpaper/WallustColors.qml"
        watchChanges:true; onFileChanged:reload(); onLoaded:root.parseWallustColors(text())
    }

    // ── Wallpaper ────────────────────────────────────────────────────────────
    property string wallpaperPath: Quickshell.env("CANDYLOCK_WALLPAPER") || ""
    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME")||(Quickshell.env("HOME")+"/.config"))+"/wallpaper/wallpaper.ini"
        watchChanges:true; onFileChanged:reload()
        onLoaded: { const m=text().match(/^wallpaper\s*=\s*(.+)$/m); if(m) root.wallpaperPath=m[1].trim().replace(/^~/,Quickshell.env("HOME")) }
    }

    // ── Auth ─────────────────────────────────────────────────────────────────
    property string pinEntry:""; property bool authFailed:false; property bool authChecking:false; property bool pinVisible:false
    property string _pendingPin:""; property bool focusPinRequest:false
    property bool   dialsVisible: false
    function submitPin() {
        if(authChecking||root.pinEntry.length===0) return
        root._pendingPin=root.pinEntry; root.pinEntry=""; root.authChecking=true; root.authFailed=false
        authProc.running=true
    }
    Timer { id:failTimer; interval:2500; onTriggered:{ root.authFailed=false; root.focusPinRequest=!root.focusPinRequest } }
    Process {
        id: notifReleaseProc
        command: ["rm", "-f", "/tmp/candylock-notif.lock"]
        running: false
    }

    Process {
        id:authProc; stdinEnabled:true
        command:[Quickshell.env("HOME")+"/.config/quickshell/candylock/pam_auth"]
        onRunningChanged: if(running){ write(root._pendingPin+"\n"); root._pendingPin="" }
        onExited: function(code){
            root.authChecking=false
            if(code===0){
                notifReleaseProc.running=true
                sessionLock.locked=false
                Qt.quit()
            } else {
                root.authFailed=true
                failTimer.restart()
            }
        }
    }

    // ── Clock ────────────────────────────────────────────────────────────────
    property string clockHour:     Qt.formatTime(new Date(),"hh")
    property string clockMin:      Qt.formatTime(new Date(),"mm")
    property string clockDate:     Qt.formatDate(new Date(),"dddd, d MMMM")
    property string clockDayName:  Qt.formatDate(new Date(),"dddd")
    property string clockDateNum:  Qt.formatDate(new Date(),"d")
    property string clockMonthName:Qt.formatDate(new Date(),"MMMM")
    Timer { interval:5000; repeat:true; running:true; onTriggered:{
        root.clockHour      = Qt.formatTime(new Date(),"hh")
        root.clockMin       = Qt.formatTime(new Date(),"mm")
        root.clockDate      = Qt.formatDate(new Date(),"dddd, d MMMM")
        root.clockDayName   = Qt.formatDate(new Date(),"dddd")
        root.clockDateNum   = Qt.formatDate(new Date(),"d")
        root.clockMonthName = Qt.formatDate(new Date(),"MMMM")
    }}

    // ── Weather ───────────────────────────────────────────────────────────────
    // Logic mirrors WeatherPopupState exactly:
    //   • same _pinnedLocFile (~/.config/hyprcandy/weather-location.conf)
    //   • same cache files (/tmp/astal-weather-cache.json, waybar-weather-unit)
    //   • same _cond() icon map (WMO codes → Nerd Font glyphs)
    //   • same open-meteo URL parameters
    //   • same 300 s poll interval (Config.weatherInterval)
    // Pipeline: unit → pinned loc → ipinfo fallback → open-meteo → cache fallback
    property string weatherUnit: "metric"
    property string weatherIcon: "󰖐"
    property string weatherTemp: "--°"
    property string weatherCondStr: "Loading…"
    property string weatherFeels: "--"
    property string weatherWind: "--"
    property string weatherHum: "--"
    property string weatherPrec: "--"
    property real   _wxTempC: 0; property real _wxFeelsC: 0; property real _wxWindKmh: 0
    property real   _wxHumidity: 0; property real _wxPrec: 0
    property int    _wxCode: 0;  property int  _wxIsDay: 1
    readonly property string _pinnedLocFile: Quickshell.env("HOME") + "/.config/hyprcandy/weather-location.conf"
    readonly property string _weatherCache:  Quickshell.env("HOME") + "/.config/hyprcandy/astal-weather-cache.json"
    readonly property string _locationCache: Quickshell.env("HOME") + "/.config/hyprcandy/waybar-weather-ipinfo.json"

    // Watch unit file for live changes (same source as bar/WeatherPopupState)
    FileView {
        path: "/tmp/waybar-weather-unit"
        watchChanges: true; onFileChanged: reload()
        onLoaded: {
            const u = text().trim()
            if (u === "imperial" || u === "metric") root.weatherUnit = u
            root._updateWeatherDisplay()
        }
    }

    // Identical icon mapping to WeatherPopupState._cond()
    function _wxCond(code, isDay, h) {
        if (code===0)             return isDay ? "☀️" : "🌙"
        if (code===1)             return isDay ? "☀️" : "🌙"
        if (code===2)             return isDay ? "⛅" : "☁️"
        if (code===3)             return h >= 85
            ? (isDay ? "⛅" : "☁️")
            : (isDay ? "⛅" : "☁️")
        if (code===45||code===48) return "🌫"
        if (code>=51&&code<=55)   return isDay ? "🌦️" : "🌧️"
        if (code===56||code===57) return isDay ? "🌦️" : "🌧️"
        if (code===61)            return isDay ? "🌦️" : "🌧️"
        if (code===63)            return isDay ? "🌦️" : "🌧️"
        if (code===65)            return "⛈️"
        if (code===66||code===67) return "⛈️"
        if (code>=71&&code<=75)   return "❄️"
        if (code===77)            return "🌨️"
        if (code>=80&&code<=82)   return "🌨️"
        if (code===85||code===86) return "🌨️"
        if (code===95)            return "⚡"
        if (code===96||code===99) return isDay ? "⛈":"⛈"
        return "󰖐"
    }

    function _wxCondStr(code, isDay, h) {
        if (code===0)             return "Clear Sky"
        if (code===1)             return "Mainly Clear"
        if (code===2)             return "Partly Cloudy"
        if (code===3)             return h >= 85 ? "Mostly Cloudy" : "Cloudy"
        if (code===45||code===48) return "Fog"
        if (code>=51&&code<=55)   return code===51 ? "Light Drizzle" : code===53 ? "Moderate Drizzle" : "Dense Drizzle"
        if (code===56||code===57) return code===56 ? "Light Freezing Rain" : "Dense Freezing Drizzle"
        if (code===61)            return "Slight Rain"
        if (code===63)            return "Moderate Rain"
        if (code===65)            return "Heavy Rain"
        if (code===66||code===67) return "Freezing Rain"
        if (code>=71&&code<=75)   return code===71 ? "Light Snow" : code===73 ? "Moderate Snow" : "Heavy Snow"
        if (code===77)            return "Snow Grains"
        if (code>=80&&code<=82)   return "Rain Showers"
        if (code===85||code===86) return "Snow Showers"
        if (code===95)            return "Thunderstorm"
        if (code===96||code===99) return "Thunderstorm + Hail"
        return "Unknown"
    }

    function _updateWeatherDisplay() {
        root.weatherIcon = root._wxCond(root._wxCode, root._wxIsDay, root._wxHumidity)
        root.weatherCondStr = root._wxCondStr(root._wxCode, root._wxIsDay, root._wxHumidity)
        if (root._wxTempC === 0 && root._wxCode === 0 && root._wxHumidity === 0) {
            root.weatherTemp = "--°"
            root.weatherFeels = "--"
            root.weatherWind = "--"
            root.weatherHum = "--"
            root.weatherPrec = "--"
            return
        }
        const suffix = root.weatherUnit === "imperial" ? "°F" : "°C"
        const cvt = (c) => root.weatherUnit === "imperial"
            ? Math.round(c * 9/5 + 32) : Math.round(c)
        root.weatherTemp  = cvt(root._wxTempC)  + suffix
        root.weatherFeels = cvt(root._wxFeelsC) + suffix
        root.weatherWind  = root.weatherUnit === "imperial"
            ? Math.round(root._wxWindKmh * 0.621371) + " mph"
            : Math.round(root._wxWindKmh) + " km/h"
        root.weatherHum   = Math.round(root._wxHumidity) + "%"
        root.weatherPrec  = (root._wxPrec || 0) + " mm"
    }

    // Step 1 — read unit preference
    Process {
        id: wxUnitProc
        command: ["bash", "-c", "cat /tmp/waybar-weather-unit 2>/dev/null || echo metric"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.weatherUnit = this.text.trim() !== "imperial" ? "metric" : "imperial"
                wxLocProc.running = true
            }
        }
    }

    // Step 2 — resolve location: pinned file → ipinfo cache → live ipinfo
    Process {
        id: wxLocProc
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
                if (!t || t === "FETCH") { wxIpinfoProc.running = true; return }
                const p   = t.split(",")
                const lat = parseFloat(p[0])
                const lon = parseFloat(p[1])
                if (p.length >= 2 && !isNaN(lat) && lat !== 0) {
                    wxFetchProc._lat = lat
                    wxFetchProc._lon = lon
                    wxFetchProc._doFetch()
                } else {
                    wxIpinfoProc.running = true
                }
            }
        }
    }

    // Step 3a — live ipinfo fallback (no pinned loc, no cache)
    Process {
        id: wxIpinfoProc
        command: ["bash", "-c",
            "curl -sf --max-time 8 https://ipinfo.io/json | tee \"$1\"",
            "--", root._locationCache]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    const c = (d.loc || "0,0").split(",")
                    wxFetchProc._lat = parseFloat(c[0]) || 0
                    wxFetchProc._lon = parseFloat(c[1]) || 0
                    wxFetchProc._doFetch()
                } catch(e) {}
            }
        }
    }

    // Step 3b — open-meteo fetch (same URL params as WeatherPopupState._fetchProc)
    Process {
        id: wxFetchProc
        property real _lat: 0
        property real _lon: 0
        running: false
        function _buildUrl() {
            return "https://api.open-meteo.com/v1/forecast" +
                "?latitude="  + _lat + "&longitude=" + _lon +
                "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,precipitation" +
                "&hourly=temperature_2m,weather_code,precipitation_probability,is_day" +
                "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
                "&minutely_15=temperature_2m,weather_code,is_day" +
                "&forecast_days=7&timezone=auto&models=best_match"
        }
        function _doFetch() {
            if (_lat === 0 && _lon === 0) { wxCacheProc.running = true; return }
            command = ["bash", "-c",
                "curl -sf --max-time 12 \"$1\" | tee \"$2\"",
                "--", _buildUrl(), root._weatherCache]
            if (!running) running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d && d.current) { root._applyWeather(d); return }
                } catch(e) {}
                wxCacheProc.running = true
            }
        }
    }

    // Step 3c — disk cache fallback
    Process {
        id: wxCacheProc
        command: ["bash", "-c", "cat \"$1\" 2>/dev/null", "--", root._weatherCache]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d && d.current) root._applyWeather(d)
                } catch(e) {}
            }
        }
    }

    // Apply parsed open-meteo response — mirrors WeatherPopupState.applyData()
    function _applyWeather(d) {
        let c = d.current
        if (d.minutely_15) {
            const now = new Date().toISOString().slice(0, 16)
            let idx = d.minutely_15.time.findIndex(t => t >= now)
            if (idx === -1) idx = d.minutely_15.time.length - 1
            if (idx <= 0) {
                c = Object.assign({}, c)
                c.temperature_2m = d.minutely_15.temperature_2m[idx]
                c.weather_code   = d.minutely_15.weather_code[idx]
            }
        }
        root._wxTempC    = c.temperature_2m       || 0
        root._wxFeelsC   = c.apparent_temperature || 0
        root._wxWindKmh  = c.wind_speed_10m       || 0
        root._wxCode     = c.weather_code          || 0
        root._wxIsDay    = (c.is_day !== undefined ? c.is_day : 1)
        root._wxHumidity = c.relative_humidity_2m || 0
        root._wxPrec     = c.precipitation        || 0
        root._updateWeatherDisplay()
    }

    // Kick the pipeline on startup and every 300 s (matches Config.weatherInterval)
    Component.onCompleted: wxUnitProc.running = true
    Timer { interval: 300000; repeat: true; running: true; onTriggered: if (!wxUnitProc.running) wxUnitProc.running = true }

    // ── System monitor ────────────────────────────────────────────────────────
    property real cpuUsage:0; property real memUsage:0; property real tempC:0; property bool tempOk:false
    Behavior on cpuUsage { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    Behavior on memUsage { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    Behavior on tempC    { NumberAnimation { duration:900; easing.type:Easing.OutCubic } }
    property var _prevCpu: null
    Process {
        id:sysProc; property var _b:[]
        command:["bash","-c",
            "head -1 /proc/stat; " +
            "grep -E '^(MemTotal|MemAvailable):' /proc/meminfo; " +
            "for z in /sys/class/thermal/thermal_zone*/; do " +
            "  t=$(cat \"$z/temp\" 2>/dev/null); y=$(cat \"$z/type\" 2>/dev/null); " +
            "  [ -n \"$t\" ]&&echo \"$y:$t\"; done"]
        stdout: SplitParser { splitMarker:"\n"; onRead: function(l){sysProc._b.push(l.trim())} }
        onRunningChanged: if(running) _b=[]
        onExited: function(){
            const lines=_b.slice(); _b=[]
            const cm=lines[0]?lines[0].match(/cpu\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)/):null
            if(cm){ const u=+cm[1],n=+cm[2],s=+cm[3],i=+cm[4],cur={total:u+n+s+i,idle:i}
                if(root._prevCpu){ const dt=cur.total-root._prevCpu.total,di=cur.idle-root._prevCpu.idle; if(dt>0) root.cpuUsage=(dt-di)/dt }
                root._prevCpu=cur }
            let mi={}; for(const l of lines){ const mm=l.match(/^(\w+):\s*(\d+)\s*kB/); if(mm) mi[mm[1]]=parseInt(mm[2])*1024 }
            if(mi.MemTotal&&mi.MemAvailable) root.memUsage=(mi.MemTotal-mi.MemAvailable)/mi.MemTotal
            let found=false
            for(const l of lines){
                const tm=l.match(/^([^:]+):(\d+)$/)
                if(!tm) continue
                const v=parseInt(tm[2])/1000, type=tm[1].toLowerCase()
                if(v>0&&v<120&&(type.includes("x86")||type.includes("pkg"))){
                    root.tempC=v; root.tempOk=true; found=true; break }
            }
            if(!found) for(const l of lines){
                const tm=l.match(/^([^:]+):(\d+)$/)
                if(!tm) continue
                const v=parseInt(tm[2])/1000
                if(v>20&&v<120){ root.tempC=v; root.tempOk=true; break }
            }
        }
    }
    Timer { interval:1500; repeat:true; running:true; onTriggered:if(!sysProc.running) sysProc.running=true
        Component.onCompleted: sysProc.running=true
    }

    // ── Output volume (lockscreen mini slider) ───────────────────────────────
    property int  _volumePct: 50
    property bool _volumeMuted: false

    Process {
        id: volReadProc
        command: ["bash", "-c",
            "VOL=$(pactl get-sink-volume @DEFAULT_SINK@ | grep -Po '\\d+(?=%)' | head -1); " +
            "MUTE=$(pactl get-sink-mute @DEFAULT_SINK@ | grep -q yes && echo 1 || echo 0); " +
            "echo \"${VOL:-50} ${MUTE}\""]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const p = l.trim().split(/\s+/)
                if (p.length >= 1 && !isNaN(parseInt(p[0]))) root._volumePct = parseInt(p[0])
                if (p.length >= 2) root._volumeMuted = p[1] === "1"
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { if (!volReadProc.running) volReadProc.running = true }
    }

    Process {
        id: volSetProc
        property string _cmd: "true"
        command: ["bash", "-c", volSetProc._cmd]
        running: false
        onExited: running = false
    }

    function setLockVolume(pct) {
        const v = Math.max(0, Math.min(100, Math.round(pct)))
        root._volumePct = v
        root._volumeMuted = false
        volSetProc._cmd = "pactl set-sink-volume @DEFAULT_SINK@ " + v + "% && pactl set-sink-mute @DEFAULT_SINK@ 0"
        if (!volSetProc.running) volSetProc.running = true
    }

    function toggleLockMute() {
        root._volumeMuted = !root._volumeMuted
        volSetProc._cmd = "pactl set-sink-mute @DEFAULT_SINK@ " + (root._volumeMuted ? "1" : "0")
        if (!volSetProc.running) volSetProc.running = true
    }

    // ── Battery (laptop only) ────────────────────────────────────────────────
    property bool _hasBattery: false
    property int  _batCapacity: 100
    property bool _batCharging: false

    Process {
        id: batProc
        command: ["bash", "-c",
            "if ! ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then echo '0'; exit 0; fi; " +
            "CAP=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1); " +
            "STA=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1); " +
            "echo \"1 ${CAP:-100} ${STA:-Unknown}\""]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(l) {
                const p = l.trim().split(/\s+/)
                root._hasBattery = p.length >= 1 && p[0] === "1"
                if (p.length >= 2) root._batCapacity = parseInt(p[1]) || 100
                if (p.length >= 3) root._batCharging = p[2] === "Charging" || p[2] === "Full"
            }
        }
    }
    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: { if (!batProc.running) batProc.running = true }
    }

    // ── Media ─────────────────────────────────────────────────────────────────
    property var  mediaPlayers:       []
    property int  activePlayerIndex:  0
    readonly property var activePlayer: (mediaPlayers.length > 0 && activePlayerIndex < mediaPlayers.length)
        ? mediaPlayers[activePlayerIndex]
        : null

    property string mediaSource:        activePlayer ? activePlayer.name   : ""
    property string mediaStatus:        activePlayer ? activePlayer.status : "Stopped"
    property string mediaTitle:         activePlayer ? (activePlayer.title || "No media") : "No media"
    property string mediaArtist:        activePlayer ? activePlayer.artist : ""
    property string mediaArtUrl:        activePlayer ? activePlayer.artUrl : ""
    property string _circularArtPath:   activePlayer ? (activePlayer.circularArtPath || "") : ""
    property string mediaShuffleStatus: activePlayer ? activePlayer.shuffle : "off"
    property string mediaLoopStatus:    activePlayer ? activePlayer.loop : "none"
    property real   mediaPosition:      activePlayer ? activePlayer.position : 0
    property real   mediaDuration:      activePlayer ? activePlayer.duration : 0
    property real   _posTimestamp:      activePlayer ? activePlayer._posTimestamp : 0

    readonly property bool _playing: mediaStatus === "Playing"
    readonly property bool _anyPlaying: _playing || mediaPlayers.some(p => p.status === "Playing")

    onMediaSourceChanged: {
        if (!posProc.running) posProc.running = true
    }

    Process {
        id:mediaProc
        command: ["playerctl", "-F", "-a", "metadata", "--format", "{{playerName}}\t{{status}}\t{{mpris:artUrl}}\t{{xesam:title}}\t{{xesam:artist}}\t{{shuffle}}\t{{loop}}"]
        stdout: SplitParser {
            splitMarker:"\n"
            onRead: function(l){
                const p = l.split("\t")
                if(p.length >= 1){
                    const name      = p[0].trim()
                    if (!name) return
                    const status    = (p.length > 1 ? p[1].trim() : "") || "Stopped"
                    const url       = p.length > 2 ? p[2].trim() : ""
                    const title     = p.length > 3 ? p[3].trim() : ""
                    const artist    = p.length > 4 ? p[4].trim() : ""
                    const shuffle   = (p.length > 5 ? p[5].trim() : "off").toLowerCase()
                    const loop      = (p.length > 6 ? p[6].trim() : "none").toLowerCase()

                    let list = root.mediaPlayers.slice()
                    let idx = list.findIndex(item => item.name === name)

                    if (status === "Stopped" && !title && !artist) {
                        if (idx >= 0 && list.length > 1) {
                            list.splice(idx, 1)
                            root.mediaPlayers = list
                            if (root.activePlayerIndex >= root.mediaPlayers.length) {
                                root.activePlayerIndex = Math.max(0, root.mediaPlayers.length - 1)
                            }
                        }
                        return
                    }

                    let item = idx >= 0 ? Object.assign({}, list[idx]) : {
                        name: name,
                        status: "Stopped",
                        artUrl: "",
                        title: "",
                        artist: "",
                        shuffle: "off",
                        loop: "none",
                        position: 0,
                        duration: 0,
                        _posTimestamp: 0,
                        circularArtPath: ""
                    }

                    const titleChanged = item.title !== title
                    const urlChanged   = item.artUrl !== url

                    item.status  = status
                    item.artUrl  = url
                    item.title   = title
                    item.artist  = artist
                    item.shuffle = shuffle
                    item.loop    = loop

                    if (titleChanged || urlChanged) {
                        item.position = 0
                        item.duration = 0
                        item._posTimestamp = 0
                        item.circularArtPath = ""
                        if (url) artConvProc.launchForPlayer(name, url)
                    }

                    if (idx >= 0) {
                        list[idx] = item
                    } else {
                        list.push(item)
                    }

                    root.mediaPlayers = list
                    if (root.activePlayerIndex >= root.mediaPlayers.length) {
                        root.activePlayerIndex = Math.max(0, root.mediaPlayers.length - 1)
                    }
                }
            }
        }
        onExited: mediaProcRestartTimer.restart()
        Component.onCompleted: running=true
    }
    Timer { id: mediaProcRestartTimer; interval: 3000; repeat: false
        onTriggered: if (!mediaProc.running) mediaProc.running = true }

    // ── Position/duration ──────────────────────────────────────────────────
    Process {
        id: posProc
        property string _line: ""
        command: ["bash", "-c",
            "P='" + (root.mediaSource ? root.mediaSource.replace(/'/g, "'\\''") : "") + "'; " +
            "if [ -n \"$P\" ]; then " +
            "  printf '%s|%s\\n' \"$(playerctl -p \"$P\" position 2>/dev/null)\" \"$(playerctl -p \"$P\" metadata mpris:length 2>/dev/null)\"; " +
            "else " +
            "  printf '%s|%s\\n' \"$(playerctl position 2>/dev/null)\" \"$(playerctl metadata mpris:length 2>/dev/null)\"; " +
            "fi"]
        stdout: SplitParser { splitMarker: "\n"; onRead: function(l){ if(l.trim()) posProc._line = l.trim() } }
        onRunningChanged: if(running) _line = ""
        onExited: function() {
            const parts = _line.split("|")
            if (parts.length >= 2 && root.activePlayer) {
                const pos = parseFloat(parts[0])
                const dur = parseFloat(parts[1]) / 1000000.0
                let list = root.mediaPlayers.slice()
                let idx = root.activePlayerIndex
                if (idx >= 0 && idx < list.length) {
                    let item = Object.assign({}, list[idx])
                    if (!isNaN(pos) && pos >= 0) {
                        item.position = pos
                        item._posTimestamp = Date.now()
                    }
                    if (!isNaN(dur) && dur > 0) item.duration = dur
                    list[idx] = item
                    root.mediaPlayers = list
                }
            }
            _line = ""
        }
    }
    // Poll every second while any source is Playing
    Timer {
        interval: 1000; repeat: true
        running: root._playing
        onTriggered: if (!posProc.running) posProc.running = true
        Component.onCompleted: posProc.running = true
    }
    // Smooth interpolation between polls — advance position by wall-clock elapsed time
    Timer {
        interval: 200; repeat: true
        running: root._playing && root.mediaDuration > 0 && root._posTimestamp > 0
        onTriggered: {
            const now = Date.now()
            const elapsed = (now - root._posTimestamp) / 1000.0
            let list = root.mediaPlayers.slice()
            let idx  = root.activePlayerIndex
            if (idx >= 0 && idx < list.length) {
                let item = Object.assign({}, list[idx])
                item._posTimestamp = now
                item.position = Math.min(item.position + elapsed, item.duration)
                list[idx] = item
                root.mediaPlayers = list
            }
        }
    }

    // ── Seek ─────────────────────────────────────────────────────────────────
    Process {
        id: seekProc
        property string _cmd: "true"
        command: ["bash", "-c", seekProc._cmd]
        function seek(secs) {
            const target = root.mediaSource ? ("-p '" + root.mediaSource.replace(/'/g, "'\\''") + "' ") : ""
            _cmd = "playerctl " + target + "position " + secs.toFixed(1)
            if (running) running = false
            running = true
        }
    }

    // ── Cava bridge: root-level string updated by lockCavaProc ───────────────
    // Because pragma ComponentBehavior: Bound prevents the process (root scope)
    // from directly accessing Canvas IDs inside the WlSessionLockSurface delegate.
    property string _cavaRaw: ""

    // Radial cava — 64 bars
    Process {
        id: lockCavaProc
        command: {
            const bars = 64
            const maxR = 7
            const cfgPath = "/tmp/qs-lock-cava.ini"
            const lines = [
                "[general]",
                "bars = " + bars,
                "framerate = 60",
                "",
                "[output]",
                "method = raw",
                "raw_target = /dev/stdout",
                "data_format = ascii",
                "ascii_max_range = " + maxR,
                "channels = mono"
            ]
            const quoted = lines.map(l => JSON.stringify(l)).join(" ")
            return ["bash","-c","printf '%s\\n' " + quoted + " > " + cfgPath + " && cava -p " + cfgPath]
        }
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) {
                const t = line.trim()
                if(!t || t.startsWith("[")) return
                root._cavaRaw = t        // bridge into the UI via root property
            }
        }
        onExited: cavRestartTimer.restart()
    }
    Timer { id:cavRestartTimer; interval:2000; repeat:false
        onTriggered: if(root._anyPlaying && !lockCavaProc.running) lockCavaProc.running = true }

    Connections {
        target: root
        function on_AnyPlayingChanged() {
            if (root._anyPlaying) {
                if (!lockCavaProc.running) lockCavaProc.running = true
            } else {
                lockCavaProc.running = false
                root._cavaRaw = ""
            }
        }
        function onMediaStatusChanged() {
            if (root._playing && !posProc.running) posProc.running = true
        }
    }

    // ── Art conversion ───────────────────────────────────────────────────────
    Process {
        id:artConvProc
        property string _dst: "/tmp/qs_art_circle.png"
        property string _cmd: "true"
        property string _targetPlayer: ""
        command:["bash","-c", artConvProc._cmd]
        function launchForPlayer(playerName, url) {
            const src = url.startsWith("file://") ? url.substring(7) : url
            const hash = Math.abs((playerName + url).split('').reduce(
                (a,b)=>{a=((a<<5)-a)+b.charCodeAt(0);return a&a},0)).toString(16)
            _targetPlayer = playerName
            _dst = "/tmp/qs_art_circle_" + hash + ".png"
            _cmd = "SRC='" + src.replace(/'/g,"'\\''") + "'; " +
                   "DST='" + _dst + "'; " +
                   "[ -f \"$SRC\" ] || { curl -sf --max-time 10 \"$SRC\" -o /tmp/qs_art_raw.png 2>/dev/null && SRC=/tmp/qs_art_raw.png; }; " +
                   "magick \"$SRC\" " +
                   "  -resize 192x192^ -gravity center -extent 192x192 " +
                   "  \\( +clone -alpha extract " +
                   "     -fill black -colorize 100 " +
                   "     -fill white -draw 'circle 96,96 96,0' \\) " +
                   "  -alpha off -compose CopyOpacity -composite " +
                   "  -strip \"$DST\""
            if (running) running = false
            running = true
        }
        onExited: function(code){
            if(code === 0 && artConvProc._targetPlayer !== "") {
                const ver = _dst + "?" + Date.now()
                let list = root.mediaPlayers.slice()
                let idx = list.findIndex(p => p.name === artConvProc._targetPlayer)
                if (idx >= 0) {
                    let item = Object.assign({}, list[idx])
                    item.circularArtPath = ver
                    list[idx] = item
                    root.mediaPlayers = list
                }
            }
        }
    }

    // ── User icon ─────────────────────────────────────────────────────────────
    property string _userIconPath: ""
    Process {
        id:iconConvProc
        property string _dst: "/tmp/qs_user_circle.png"
        property string _src: Quickshell.env("HOME")+"/.config/hyprcandy/user-icon.png"
        command:["bash","-c",
            "SRC='" + iconConvProc._src + "'; " +
            "DST='" + iconConvProc._dst + "'; " +
            "[ -f \"$SRC\" ] || exit 1; " +
            "magick \"$SRC\" " +
            "  -resize 384x384^ -gravity center -extent 384x384 " +
            "  \\( +clone -alpha extract " +
            "     -fill black -colorize 100 " +
            "     -fill white -draw 'circle 192,192 192,0' \\) " +
            "  -alpha off -compose CopyOpacity -composite " +
            "  -strip \"$DST\""]
        onExited: function(code){
            if(code===0) root._userIconPath = iconConvProc._dst + "?" + Date.now()
        }
        Component.onCompleted: running=true
    }

    // ── Player controls ───────────────────────────────────────────────────────
    // Fix: set command directly on each call instead of relying on a bound property.
    Process { id:ctlProc; running:false; onExited: running=false }
    Process { id:pwrProc;  running:false; onExited: running=false }
    property bool _hibernateAvailable: false
    Process {
        id: _hibCheckProc
        // systemd exposes hibernate as a sleep state only when swap/hibernation is configured
        command: ["bash","-c","grep -qw hibernate /sys/power/state 2>/dev/null && echo yes || echo no"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(line) { root._hibernateAvailable = line.trim() === "yes" }
        }
        onExited: running = false
    }
    Process {
        id: suspendIfFlagged
        command: ["/bin/bash", "-c",
            "f=/tmp/.qs-candylock-sleep; [ -f \"$f\" ] && rm -f \"$f\" && systemctl suspend"]
        running: false
        onExited: running = false
    }
    function playerAction(cmd) {
        let argv
        const target = root.mediaSource ? ["-p", root.mediaSource] : []
        if(cmd === "shuffle") {
            argv = ["playerctl"].concat(target).concat(["shuffle", "toggle"])
        } else if(cmd === "loop") {
            const order = ["none","track","playlist"]
            const names = ["None","Track","Playlist"]
            const cur   = Math.max(0, order.indexOf(root.mediaLoopStatus))
            argv = ["playerctl"].concat(target).concat(["loop", names[(cur + 1) % 3]])
        } else {
            argv = ["playerctl"].concat(target).concat([cmd])
        }

        if (cmd === "play-pause" && root.activePlayer) {
            let list = root.mediaPlayers.slice()
            let idx = root.activePlayerIndex
            if (idx >= 0 && idx < list.length) {
                let item = Object.assign({}, list[idx])
                item.status = item.status === "Playing" ? "Paused" : "Playing"
                list[idx] = item
                root.mediaPlayers = list
            }
        }

        ctlProc.command = argv
        if (ctlProc.running) ctlProc.running = false
        ctlProc.running = true
    }

    // ── Session lock ──────────────────────────────────────────────────────────
    WlSessionLock { id:sessionLock
        locked: true
        onLockedChanged: if (locked) suspendIfFlagged.running = true
        WlSessionLockSurface {
            Rectangle {
                id:mainRect; anchors.fill:parent; color:root.cBg; focus:true
                Keys.onPressed: function(ev){ if(!ev.isAutoRepeat) pinInput.forceActiveFocus() }

                // Wallpaper
                AnimatedImage {
                    id:wallImg
                    anchors.fill:parent
                    source: root.wallpaperPath?"file://"+root.wallpaperPath:""
                    fillMode:Image.PreserveAspectCrop; smooth:true; cache:true; playing:true; asynchronous:false
                    visible: root.wallpaperPath!==""
                }

                LockNotificationsOverlay {
                    id: lockNotif
                    anchors.fill: parent
                    wallpaperPath: root.wallpaperPath
                    cOnSecondary: root.cOnSecondary
                    cInvPrimary:  root.cInvPrimary
                    cPrimary:     root.cPrimary
                    cOnSurf:      root.cOnSurf
                    cOnSurfVar:   root.cOnSurfVar
                    cOutVar:      root.cOutVar
                    cErr:         root.cErr

                    cWc0:  root.cWc0
                    cWc1:  root.cWc1
                    cWc2:  root.cWc2
                    cWc3:  root.cWc3
                    cWc4:  root.cWc4
                    cWc5:  root.cWc5
                    cWc6:  root.cWc6
                    cWc7:  root.cWc7
                    cWc8:  root.cWc8
                    cWc9:  root.cWc9
                    cWc10: root.cWc10
                    cWc11: root.cWc11
                    cWc12: root.cWc12
                    cWc13: root.cWc13
                    cWc14: root.cWc14
                    cWc15: root.cWc15
                }

                Item {
                    id:centerPanel
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter:   parent.verticalCenter
                    anchors.verticalCenterOffset: -36
                    width:520
                    height:panelCol.implicitHeight+45

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled:      true
                        maskSource:       roundMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin:  1.0
                    }

                    Rectangle {
                        id: roundMask
                        anchors.fill: parent
                        radius: 32; color: "white"; opacity: 0
                        layer.enabled: true
                    }

                    Item {
                        anchors.fill:parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect { blurEnabled:true; blur:1.0; blurMax:64 }
                        AnimatedImage {
                            x: -centerPanel.x; y: -centerPanel.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath?"file://"+root.wallpaperPath:""
                            fillMode:Image.PreserveAspectCrop; smooth:true; playing:true; cache:true
                            visible: root.wallpaperPath!==""
                        }
                    }

                    Rectangle {
                        anchors.fill:parent; radius:32; color:root.cPanel
                        border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.1)
                    }

                    ColumnLayout {
                        id:panelCol
                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:24 }
                        spacing:10

                        // ══════ MAIN GRID: (clock + dials) | (info + weather/media) ══
                        RowLayout {
                            Layout.fillWidth:true; spacing:14; Layout.bottomMargin:4



                            // ── RIGHT COLUMN: info + weather/media ──────────────
                            ColumnLayout {
                                id:rightCol
                                Layout.fillWidth:true; spacing:10

                                // ── TOP ROW: Unified Card (Clock | User & PIN | Date) ──
                                Rectangle {
                                    id: userTopCard
                                    Layout.fillWidth: true
                                    height: userTopRow.implicitHeight
                                    radius: 20
                                    color: root.cCardWarm
                                    border.width: 1
                                    border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.1)

                                    RowLayout {
                                        id: userTopRow
                                        anchors.fill: parent
                                        anchors.leftMargin: 14
                                        anchors.rightMargin: 14
                                        anchors.topMargin: 0
                                        anchors.bottomMargin: 10
                                        spacing: 12

                                        // ── LEFT: Clock ──────────────────────────────────
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 0
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.clockHour; color: root.cWc3
                                                font.family: "C059"; font.pixelSize: 86
                                                font.italic: true; font.weight: Font.Bold
                                                lineHeight: 0.88
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: "󰫢  󰫢"; color: root.cWc9
                                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 14
                                                topPadding: 6; bottomPadding: 6
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.clockMin; color: root.cWc10
                                                font.family: "C059"; font.pixelSize: 86
                                                font.italic: true; font.weight: Font.Bold
                                                lineHeight: 0.88
                                            }
                                        }

                                        // ── SEPARATOR 1 ───────────────────────────────────
                                        Rectangle {
                                            Layout.preferredWidth: 1
                                            Layout.fillHeight: true
                                            Layout.topMargin: 35
                                            Layout.bottomMargin: 35
                                            color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.0)
                                        }

                                        // ── CENTER: User icon + PIN Entry ─────────────────
                                        ColumnLayout {
                                            id: userPinCol
                                            Layout.alignment: Qt.AlignHCenter | Qt.AlignVCenter
                                            spacing: 12

                                            Item {
                                                width: 130; height: 130
                                                Layout.preferredWidth: 130
                                                Layout.preferredHeight: 130
                                                Layout.alignment: Qt.AlignHCenter

                                                Image {
                                                    id: userImg
                                                    anchors.fill: parent
                                                    source: root._userIconPath !== "" ? ("file://" + root._userIconPath.split("?")[0] + "?v=" + root._userIconPath.split("?")[1]) : ""
                                                    fillMode: Image.PreserveAspectFit
                                                    smooth: true; cache: false; mipmap: true
                                                    visible: status === Image.Ready
                                                }

                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: root.cSurfHi
                                                    visible: userImg.status !== Image.Ready
                                                    Text {
                                                        anchors.centerIn: parent
                                                        text: "󰀄"
                                                        font.pixelSize: 52
                                                        font.family: "Symbols Nerd Font Mono"
                                                        color: root.cOnSurfVar
                                                    }
                                                    border.width: 2
                                                    border.color: Qt.rgba(root.cScrim.r, root.cScrim.g, root.cScrim.b, 1.0)
                                                }

                                                // Clean subtle border ring around avatar
                                                Rectangle {
                                                    anchors.fill: parent
                                                    radius: width / 2
                                                    color: "transparent"
                                                    border.width: 2
                                                    border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.25)
                                                }
                                            }

                                            // PIN ENTRY
                                            Item {
                                                Layout.alignment: Qt.AlignHCenter; width: 190; height: 42
                                                Rectangle {
                                                    anchors.fill: parent; radius: 21
                                                    color: Qt.rgba(root.cInvPrimary.r, root.cInvPrimary.g, root.cInvPrimary.b, 0.25)
                                                    border.width: 2
                                                    border.color: root.authFailed ? root.cErr
                                                        : (root.authChecking
                                                            ? root.cWc5
                                                            : root.cWc10)
                                                    Behavior on border.color { ColorAnimation { duration: 250 } }
                                                }
                                                RowLayout {
                                                    anchors.centerIn: parent; spacing: 6
                                                    visible: root.pinEntry.length === 0 && !root.authChecking
                                                    Text { text: "󰀄"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 13; color: root.cWc12 }
                                                    Text { text: Quickshell.env("USER"); font.family: "C059"; font.pixelSize: 13; font.italic: true; color: root.cWc2; opacity: 1.00 }
                                                }
                                                Text {
                                                    anchors.centerIn: parent; visible: root.authChecking
                                                    text: "󰶘"; font.family: "Symbols Nerd Font Mono"; font.pixelSize: 18; color: root.cWc12
                                                    RotationAnimator on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: root.authChecking }
                                                }
                                                Row {
                                                    anchors.centerIn: parent; spacing: 5
                                                    visible: root.pinEntry.length > 0 && !root.authChecking && !root.pinVisible
                                                    Repeater { model: root.pinEntry.length; delegate: Rectangle { width: 8; height: 8; radius: 99; color: root.cSecondary; opacity: 0.90 } }
                                                }
                                                Text {
                                                    anchors.centerIn: parent; width: parent.width - 24
                                                    visible: root.pinEntry.length > 0 && !root.authChecking && root.pinVisible
                                                    text: root.pinEntry; color: root.cSecondary
                                                    font.family: "C059"; font.pixelSize: 15
                                                    horizontalAlignment: Text.AlignHCenter
                                                    elide: Text.ElideMiddle
                                                }

                                                // PIN VISIBILITY TOGGLE — only shown once typing begins
                                                Text {
                                                    anchors.right: parent.right; anchors.rightMargin: 12
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    visible: root.pinEntry.length > 0 && !root.authChecking
                                                    text: root.pinVisible ? "󰛐" : "󰛑"
                                                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: 13
                                                    color: root.cWc12; opacity: 0.85
                                                    MouseArea {
                                                        anchors.fill: parent; anchors.margins: -8
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: root.pinVisible = !root.pinVisible
                                                    }
                                                }
                                            }

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.authFailed ? "Wrong password" : ""
                                                color: root.cErr; font.pixelSize: 11; font.italic: true
                                                opacity: root.authFailed ? 1 : 0
                                                Behavior on opacity { NumberAnimation { duration: 200 } }
                                            }
                                        }

                                        // ── RIGHT: Date ───────────────────────────────────
                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredWidth: 1
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 14
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.clockDayName; color: root.cWc3
                                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 22
                                                font.italic: true; font.weight: Font.Bold
                                                lineHeight: 0.88
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.clockDateNum; color: root.cWc9
                                                font.family: "C059"; font.pixelSize: 86
                                                font.italic: true; font.weight: Font.DemiBold
                                                lineHeight: 0.88
                                                topPadding: 8; bottomPadding: 8
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.clockMonthName; color: root.cWc10
                                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 22
                                                font.italic: true; font.weight: Font.Bold
                                                lineHeight: 0.88
                                            }
                                        }
                                    }
                                }

                            ColumnLayout {
                                id: rightBottomCol
                                Layout.fillWidth: true
                                spacing: 10

                                // ── WEATHER CARD — horizontal current conditions ──
                                Rectangle {
                                    id: weatherCard
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    Layout.minimumHeight: 100
                                    radius: 20
                                    color: root.cCardWarm
                                    border.width: 1
                                    border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.1)

                                    RowLayout {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.margins: 12
                                        spacing: 10

                                        ColumnLayout {
                                            Layout.preferredWidth: 76
                                            Layout.maximumWidth: 76
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 2

                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.weatherIcon
                                                color: root.cWc6
                                                font.pixelSize: 34
                                                font.family: "Symbols Nerd Font Mono"
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            Text {
                                                Layout.alignment: Qt.AlignHCenter
                                                text: root.weatherTemp
                                                color: root.cWc5
                                                font.pixelSize: 18
                                                font.weight: Font.Bold
                                                font.family: "C059"
                                                font.italic: true
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: root.weatherCondStr
                                                color: root.cOnSurfVar
                                                font.pixelSize: 9
                                                font.family: "monospace"
                                                horizontalAlignment: Text.AlignHCenter
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }
                                        }

                                        Rectangle {
                                            Layout.preferredWidth: 1
                                            Layout.fillHeight: true
                                            Layout.topMargin: 6
                                            Layout.bottomMargin: 6
                                            color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.16)
                                        }

                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.alignment: Qt.AlignVCenter
                                            spacing: 6

                                            Repeater {
                                                model: [
                                                    { glyph: "󰔐", label: "Feels",    val: root.weatherFeels },
                                                    { glyph: "󰖌", label: "Humidity", val: root.weatherHum   },
                                                    { glyph: "󰖝", label: "Wind",     val: root.weatherWind  },
                                                    { glyph: "󰖗", label: "Precip",   val: root.weatherPrec  }
                                                ]
                                                delegate: RowLayout {
                                                    required property var modelData
                                                    spacing: 3
                                                    Layout.fillWidth: true

                                                    Text {
                                                        text: modelData.glyph
                                                        color: root.cWc6
                                                        font.pixelSize: 14
                                                        font.family: "Symbols Nerd Font Mono"
                                                    }
                                                    ColumnLayout {
                                                        spacing: 0
                                                        Layout.fillWidth: true
                                                        Text {
                                                            text: modelData.label
                                                            color: root.cOnSurfVar
                                                            font.pixelSize: 9
                                                            font.family: "monospace"
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                        }
                                                        Text {
                                                            text: modelData.val
                                                            color: root.cPrimary
                                                            font.pixelSize: 12
                                                            font.weight: Font.Medium
                                                            font.family: "monospace"
                                                            elide: Text.ElideRight
                                                            Layout.fillWidth: true
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                            // ── MEDIA CARD — compact horizontal layout ────────────
                            Rectangle {
                                Layout.fillWidth:true
                                height: mediaCardRow.implicitHeight + 28
                                radius:20; color:root.cCardWarm
                                border.width:1; border.color:Qt.rgba(root.cOutVar.r,root.cOutVar.g,root.cOutVar.b,0.22)

                                // ── LEFT: info + progress + controls ───────────────
                                RowLayout {
                                    id: mediaCardRow
                                    anchors { left:parent.left; right:parent.right; top:parent.top; margins:14 }
                                    spacing: 12

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 6

                                        // Title
                                        Text {
                                            Layout.fillWidth:true
                                            text: root.mediaTitle; color: root.cOnSurf
                                            font.pixelSize:13; font.weight:Font.DemiBold
                                            elide:Text.ElideRight
                                        }
                                        // Artist
                                        Text {
                                            Layout.fillWidth:true
                                            text: root.mediaArtist; color: root.cOnSurfVar
                                            font.pixelSize:11; elide:Text.ElideRight
                                            visible: text !== ""
                                        }

                                        // ── Progress / seek bar ───────────────────────
                                        Item {
                                            id: seekBarItem
                                            Layout.fillWidth: true
                                            height: 28
                                            visible: root.mediaDuration > 0

                                            property bool  _drag:     false
                                            property real  _dragNorm: 0
                                            readonly property real _norm: root.mediaDuration > 0
                                                ? (_drag ? _dragNorm
                                                         : Math.max(0, Math.min(1, root.mediaPosition / root.mediaDuration)))
                                                : 0

                                            function _fmt(s) {
                                                const m = Math.floor(s / 60)
                                                const ss = Math.floor(s % 60)
                                                return m + ":" + (ss < 10 ? "0" : "") + ss
                                            }

                                            // Time labels
                                            Text {
                                                anchors.left: parent.left; anchors.top: parent.top
                                                text: seekBarItem._fmt(seekBarItem._drag ? seekBarItem._dragNorm * root.mediaDuration : root.mediaPosition)
                                                color: root.cOnSurfVar; font.pixelSize: 9
                                            }
                                            Text {
                                                anchors.right: parent.right; anchors.top: parent.top
                                                text: seekBarItem._fmt(root.mediaDuration)
                                                color: root.cOnSurfVar; font.pixelSize: 9
                                            }

                                            // Trough
                                            Item {
                                                id: trough
                                                anchors.bottom: parent.bottom
                                                anchors.left: parent.left; anchors.right: parent.right
                                                height: 14

                                                Rectangle {
                                                    anchors.fill: parent; radius: 7
                                                    color: Qt.rgba(root.cScrim.r,root.cScrim.g,root.cScrim.b,0.15)
                                                    border.width: 1
                                                    border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.45)
                                                }

                                                // Gradient fill
                                                Item {
                                                    x: 3; y: 3
                                                    width:  Math.max(0, (trough.width - 6) * seekBarItem._norm)
                                                    height: 8
                                                    clip: true
                                                    Rectangle {
                                                        width:  trough.width - 6
                                                        height: 8; radius: 4
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop { position: 0.0; color: root.cInvPrimary }
                                                            GradientStop { position: 1.0; color: root.cOnSecondary }
                                                        }
                                                    }
                                                }

                                                // Thumb
                                                Text {
                                                    text: "󰟃"
                                                    font.family: "Symbols Nerd Font Mono"; font.pixelSize: 10
                                                    color: root.cWc4
                                                    style: Text.Outline; styleColor: Qt.rgba(0,0,0,0.25)
                                                    x: {
                                                        const tw = trough.width - 6
                                                        const cx = 3 + tw * seekBarItem._norm - implicitWidth / 2
                                                        return Math.max(1, Math.min(trough.width - implicitWidth - 1, cx))
                                                    }
                                                    y: (trough.height - implicitHeight) / 2
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                                    preventStealing: true
                                                    function _n(mx) { return Math.max(0, Math.min(1, mx / trough.width)) }
                                                    onPressed:         function(m) { seekBarItem._drag = true;  seekBarItem._dragNorm = _n(m.x) }
                                                    onPositionChanged: function(m) { if(pressed) seekBarItem._dragNorm = _n(m.x) }
                                                    onReleased:        function(m) {
                                                        seekBarItem._dragNorm = _n(m.x)
                                                        seekBarItem._drag = false
                                                        seekProc.seek(_n(m.x) * root.mediaDuration)
                                                    }
                                                    onWheel: function(e) {
                                                        const d = (e.angleDelta.y > 0 ? 1 : -1) * 5
                                                        seekProc.seek(Math.max(0, Math.min(root.mediaDuration, root.mediaPosition + d)))
                                                    }
                                                }
                                            }
                                        }

                                        // ── Volume ────────────────────────────────────
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: 8
                                            Text {
                                                text: root._volumeMuted ? "󰝟" : "󰕾"
                                                font.family: "Symbols Nerd Font Mono"
                                                font.pixelSize: 14
                                                color: root.cWc2
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: root.toggleLockMute()
                                                }
                                            }
                                            Item {
                                                id: volBarItem
                                                Layout.fillWidth: true
                                                height: 14
                                                readonly property real _norm: root._volumePct / 100.0

                                                Rectangle {
                                                    anchors.fill: parent; radius: 7
                                                    color: Qt.rgba(root.cScrim.r,root.cScrim.g,root.cScrim.b,0.15)
                                                    border.width: 1
                                                    border.color: Qt.rgba(root.cPrimary.r, root.cPrimary.g, root.cPrimary.b, 0.45)
                                                }

                                                Item {
                                                    x: 3; y: 3
                                                    width: Math.max(0, (volBarItem.width - 6) * volBarItem._norm)
                                                    height: 8
                                                    clip: true
                                                    Rectangle {
                                                        width: volBarItem.width - 6
                                                        height: 8; radius: 4
                                                        gradient: Gradient {
                                                            orientation: Gradient.Horizontal
                                                            GradientStop { position: 0.0; color: root.cInvPrimary }
                                                            GradientStop { position: 1.0; color: root.cOnSecondary }
                                                        }
                                                    }
                                                }

                                                Text {
                                                    text: "󰟃"
                                                    font.family: "Symbols Nerd Font Mono"
                                                    font.pixelSize: 10
                                                    color: root.cWc4
                                                    style: Text.Outline
                                                    styleColor: Qt.rgba(0, 0, 0, 0.25)
                                                    x: {
                                                        const tw = volBarItem.width - 6
                                                        const cx = 3 + tw * volBarItem._norm - implicitWidth / 2
                                                        return Math.max(1, Math.min(volBarItem.width - implicitWidth - 1, cx))
                                                    }
                                                    y: (volBarItem.height - implicitHeight) / 2
                                                }

                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    preventStealing: true
                                                    function _n(mx) {
                                                        return Math.max(0, Math.min(100, (mx / volBarItem.width) * 100))
                                                    }
                                                    onClicked: function(m) { root.setLockVolume(_n(m.x)) }
                                                    onPositionChanged: function(m) {
                                                        if (pressed) root.setLockVolume(_n(m.x))
                                                    }
                                                    onWheel: function(e) {
                                                        const step = e.angleDelta.y > 0 ? 5 : -5
                                                        root.setLockVolume(root._volumePct + step)
                                                        e.accepted = true
                                                    }
                                                }
                                            }
                                        }

                                        // ── Controls ──────────────────────────────────
                                        RowLayout {
                                            spacing: 6

                                            Repeater {
                                                model: [
                                                    // shuffle — 󰒞 icon; active when shuffling
                                                    { i:"󰒞",  c:"shuffle",    a: root.mediaShuffleStatus === "on" },
                                                    { i:"󰒮",  c:"previous",   a: false },
                                                    { i: root.mediaStatus === "Playing" ? "󰏤" : "󰐊", c:"play-pause", a: false },
                                                    { i:"󰒭",  c:"next",       a: false },
                                                    // loop: none→󰑗  track→󰑘  playlist→󰑖
                                                    { i: root.mediaLoopStatus === "track" ? "󰑘"
                                                           : (root.mediaLoopStatus === "playlist" ? "󰑖" : "󰑗"),
                                                      c:"loop",
                                                      a: root.mediaLoopStatus !== "none" }
                                                ]
                                                delegate: Rectangle {
                                                    required property var modelData
                                                    required property int index
                                                    width:30; height:30; radius:6
                                                    readonly property bool isCenter: index === 2
                                                    readonly property bool isActive: modelData.a
                                                    color: bma.containsMouse
                                                        ? (isActive
                                                            ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.25)
                                                            : (isCenter
                                                                ? Qt.rgba(root.cOnSurf.r,root.cOnSurf.g,root.cOnSurf.b,0.22)
                                                                : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.18)))
                                                        : (isActive
                                                            ? Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.15)
                                                            : "transparent")
                                                    border.width: isActive ? 2 : 1
                                                    border.color: isActive
                                                        ? root.cPrimary
                                                        : (isCenter
                                                            ? Qt.rgba(root.cOnSurf.r,root.cOnSurf.g,root.cOnSurf.b,0.65)
                                                            : Qt.rgba(root.cPrimary.r,root.cPrimary.g,root.cPrimary.b,0.50))
                                                    Behavior on color { ColorAnimation{duration:100} }
                                                    Text {
                                                        anchors.centerIn:parent
                                                        text: modelData.i; font.pixelSize:14; font.family:"Symbols Nerd Font Mono"
                                                        color: bma.containsMouse || parent.isActive
                                                            ? (isCenter ? root.cOnSurf : root.cPrimary)
                                                            : root.cOnSurfVar
                                                        Behavior on color { ColorAnimation{duration:100} }
                                                    }
                                                    MouseArea { id:bma; anchors.fill:parent; hoverEnabled:true; onClicked: root.playerAction(modelData.c) }
                                                }
                                            }
                                        }
                                    }

                                    // ── RIGHT: spinning disc + radial cava ─────────
                                    Item {
                                        width: 170; height: 170
                                        Layout.alignment: Qt.AlignVCenter

                                        // Radial cava canvas — reacts to root._cavaRaw
                                        Canvas {
                                            id: radialCava
                                            anchors.fill: parent
                                            visible: root._anyPlaying
                                            property var _bars: []
                                            property int _barCount: 64

                                            // Watch the root bridge property
                                            Connections {
                                                target: root
                                                function on_CavaRawChanged() {
                                                    if(!root._cavaRaw || !radialCava.visible) return
                                                    const vals = root._cavaRaw.split(";")
                                                    radialCava._bars = []
                                                    for(let i = 0; i < radialCava._barCount; i++) {
                                                        const v = parseInt(vals[i % vals.length])
                                                        radialCava._bars.push(isNaN(v) ? 0 : v / 7.0)
                                                    }
                                                    radialCava.requestPaint()
                                                }
                                            }

                                            onPaint: {
                                                const ctx = getContext("2d")
                                                ctx.reset()
                                                const cx = width / 2, cy = height / 2
                                                const innerR = 52   // 92/2 + 2px gap
                                                const maxBarH = 28  // slim + long like media.js

                                                for(let i = 0; i < _barCount; i++) {
                                                    const amp = _bars[i] || 0
                                                    if(amp < 0.01) continue
                                                    const angle = (i / _barCount) * Math.PI * 2 - Math.PI / 2
                                                    const barH  = 2 + amp * (maxBarH - 2)   // 2px baseline above disc
                                                    ctx.beginPath()
                                                    ctx.strokeStyle = Qt.rgba(root.cWc6.r, root.cWc6.g, root.cWc6.b, 0.40 + amp * 1.00)
                                                    ctx.lineWidth = 1.5
                                                    ctx.lineCap   = "round"
                                                    ctx.moveTo(cx + Math.cos(angle) * innerR,            cy + Math.sin(angle) * innerR)
                                                    ctx.lineTo(cx + Math.cos(angle) * (innerR + barH),   cy + Math.sin(angle) * (innerR + barH))
                                                    ctx.stroke()
                                                }
                                            }
                                        }

                                        // Spinning disc — 92px, centered inside 140px item
                                        Rectangle {
                                            id: artDisc
                                            anchors.centerIn: parent
                                            width: 92; height: 92
                                            radius: 46; color: root.cSurfHi
                                            antialiasing: true
                                            layer.enabled: true
                                            layer.smooth: true

                                            Image {
                                                id: artImg
                                                anchors.fill: parent
                                                source: root._circularArtPath !== ""
                                                    ? ("file://" + root._circularArtPath.split("?")[0] + "?v=" + root._circularArtPath.split("?")[1])
                                                    : ""
                                                fillMode: Image.PreserveAspectCrop
                                                smooth: true; cache: false
                                                visible: root._circularArtPath !== "" && status === Image.Ready
                                            }
                                            Text {
                                                anchors.centerIn: parent; visible: !artImg.visible
                                                text: "󰽲"; font.pixelSize:32; font.family:"Symbols Nerd Font Mono"
                                                color: root.cOnSurfVar; opacity: 0.35
                                            }
                                            RotationAnimator on rotation {
                                                from:0; to:360; duration:16000
                                                loops:Animation.Infinite
                                                running: root.mediaStatus === "Playing"
                                            }
                                        }
                                    }
                                }
                            }
                            } // rightBottomCol
                            } // rightCol
                        } // main grid RowLayout
                    }
                }

                // ── Top-left: notifications toggle (blur circle) ─────────────────
                Item {
                    id: notifToggle
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.margins: 24
                    width: 48; height: 48
                    z: 20

                    Rectangle {
                        id: notifMask
                        anchors.fill: parent
                        radius: width / 2
                        color: "white"
                        visible: false
                        layer.enabled: true
                    }

                    Item {
                        anchors.fill: parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
                        AnimatedImage {
                            x: -notifToggle.x; y: -notifToggle.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true; playing: true; cache: true
                            visible: root.wallpaperPath !== ""
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.65)
                        border.width: lockNotif.dndEnabled ? 3 : 3
                        border.color: lockNotif.dndEnabled
                            ? Qt.rgba(root.cInvPrimary.r, root.cInvPrimary.g, root.cInvPrimary.b, 0.65)
                            : Qt.rgba(root.cInvPrimary.r, root.cInvPrimary.g, root.cInvPrimary.b, 0.65)
                    }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: notifMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Text {
                        anchors.centerIn: parent
                        // nf-md-notifications / nf-md-notifications_off
                        text: lockNotif.dndEnabled ? "󰂠" : "󰂚"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 20
                        color: lockNotif.dndEnabled ? root.cSecondary : root.cPrimary
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: function(e) {
                            if (e.button === Qt.RightButton) lockNotif.toggleDnd()
                            else lockNotif.toggleHistory()
                        }
                    }
                }

                // ── Top-right: dials toggle (battery icon on laptops, gauge on desktops) ─
                Item {
                    id: batToggle
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: 24
                    width: 48; height: 48
                    z: 20

                    Rectangle {
                        id: batMask
                        anchors.fill: parent
                        radius: width / 2
                        color: "white"
                        visible: false
                        layer.enabled: true
                    }

                    Item {
                        anchors.fill: parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
                        AnimatedImage {
                            x: -batToggle.x; y: -batToggle.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
                            fillMode: Image.PreserveAspectCrop
                            smooth: true; playing: true; cache: true
                            visible: root.wallpaperPath !== ""
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.65)
                        border.width: 3
                        border.color: Qt.rgba(root.cInvPrimary.r, root.cInvPrimary.g, root.cInvPrimary.b, 0.65)
                    }

                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: batMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Text {
                        anchors.centerIn: parent
                        text: root._hasBattery
                            ? (root._batCharging ? "󱐋" : "󰻠")
                            : "󰕯"
                        font.family: "Symbols Nerd Font Mono"
                        font.pixelSize: 20
                        color: root.dialsVisible ? root.cSecondary : root.cPrimary
                        Behavior on color { ColorAnimation { duration: 180 } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.dialsVisible = !root.dialsVisible
                    }
                }

                // ── Dials popup — blurred card toggled from top-right button ─
                Item {
                    id: dialsPopup
                    anchors.top:         batToggle.bottom
                    anchors.topMargin:   8
                    anchors.right:       parent.right
                    anchors.rightMargin: 24
                    width:  148
                    height: dialsPopupInner.implicitHeight + 32
                    z:      30

                    opacity: root.dialsVisible ? 1.0 : 0.0
                    scale:   root.dialsVisible ? 1.0 : 0.92
                    enabled: root.dialsVisible
                    transformOrigin: Item.TopRight
                    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
                    Behavior on scale   { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                    // Rounded mask for clipping
                    Rectangle {
                        id: dialsMask
                        anchors.fill: parent; radius: 20
                        color: "white"; visible: false; layer.enabled: true
                    }

                    // Blurred wallpaper slice (same technique as centerPanel)
                    Item {
                        anchors.fill: parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
                        AnimatedImage {
                            x: -dialsPopup.x; y: -dialsPopup.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
                            fillMode: Image.PreserveAspectCrop; smooth: true; playing: true; cache: true
                            visible: root.wallpaperPath !== ""
                        }
                    }

                    // Card tint + border
                    Rectangle {
                        anchors.fill: parent; radius: 20
                        color: root.cPanel
                        border.width: 1
                        border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.22)
                    }

                    // Clip to rounded rect
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled:      true
                        maskSource:       dialsMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin:  1.0
                    }

                    ColumnLayout {
                        id: dialsPopupInner
                        anchors { left:parent.left; right:parent.right; top:parent.top; margins:14 }
                        spacing: 8

                        // ── CPU / RAM / Temp dials ────────────────────────────
                        Repeater {
                            model: 3
                            delegate: Item {
                                required property int index
                                readonly property real arcVal: index===0 ? root.cpuUsage
                                    : (index===1 ? root.memUsage
                                    : (root.tempOk ? Math.min(root.tempC/100,1) : 0))
                                readonly property string arcText: index===0 ? Math.round(root.cpuUsage*100)+"%"
                                    : (index===1 ? Math.round(root.memUsage*100)+"%"
                                    : (root.tempOk ? Math.round(root.tempC)+"°" : "N/A"))
                                readonly property string arcGlyph: index===0?"󰻠":(index===1?"󰍛":"󰔏")
                                readonly property string arcLabel: index===0?"CPU":(index===1?"RAM":"Temp")
                                readonly property color arcColor: index===0 ? root.cWc5
                                    : (index===1 ? root.cWc10 : root.cWc3)

                                Layout.fillWidth:true; Layout.fillHeight:true; Layout.minimumHeight:88

                                Canvas {
                                    id: popArcC
                                    anchors.horizontalCenter:parent.horizontalCenter
                                    anchors.top:parent.top
                                    anchors.topMargin: Math.max(0,(parent.height-72-14)/2)
                                    width:72; height:72
                                    property color dialCol: parent.arcColor
                                    property color onS:     root.cOnSurf
                                    property real  cv:      parent.arcVal
                                    property string gt:     parent.arcText
                                    property string gl:     parent.arcGlyph
                                    onDialColChanged: requestPaint(); onOnSChanged: requestPaint()
                                    onCvChanged: requestPaint(); onGtChanged: requestPaint()
                                    Component.onCompleted: requestPaint()
                                    onPaint: {
                                        const ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                                        const cx=width/2,cy=height/2,r=27,lw=5
                                        const s=0.75*Math.PI,e=2.25*Math.PI
                                        ctx.lineWidth=lw; ctx.lineCap="round"
                                        ctx.beginPath(); ctx.arc(cx,cy,r,s,e)
                                        ctx.strokeStyle=Qt.rgba(root.cScrim.r,root.cScrim.g,root.cScrim.b,0.15).toString(); ctx.stroke()
                                        if(cv>0.005){
                                            ctx.beginPath(); ctx.arc(cx,cy,r,s,s+cv*(e-s))
                                            ctx.strokeStyle=dialCol.toString(); ctx.stroke()
                                        }
                                        ctx.fillStyle=Qt.rgba(dialCol.r,dialCol.g,dialCol.b,0.92).toString()
                                        ctx.font="15px 'Symbols Nerd Font Mono'"
                                        ctx.textAlign="center"; ctx.textBaseline="alphabetic"
                                        ctx.fillText(gl,cx,cy+2)
                                        ctx.fillStyle=Qt.rgba(onS.r,onS.g,onS.b,0.88).toString()
                                        ctx.font="bold 9px monospace"
                                        ctx.textBaseline="top"; ctx.fillText(gt,cx,cy+5)
                                    }
                                }
                                Text {
                                    anchors.horizontalCenter:parent.horizontalCenter
                                    anchors.bottom:parent.bottom
                                    text:parent.arcLabel; color:root.cOnSurfVar; font.pixelSize:9
                                }
                            }
                        }

                        // ── Battery dial (laptop only) ────────────────────────
                        Item {
                            visible: root._hasBattery
                            Layout.fillWidth: true; Layout.minimumHeight: 88

                            Canvas {
                                id: batDialArc
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.top
                                anchors.topMargin: Math.max(0,(parent.height-72-14)/2)
                                width: 72; height: 72
                                property color dialCol: root._batCapacity <= 10 ? Qt.rgba(1.0, 0.3, 0.3, 1)
                                    : (root._batCharging ? Qt.rgba(0.3, 0.9, 0.5, 1) : root.cWc6)
                                property real  cv:  Math.max(0, Math.min(100, root._batCapacity)) / 100
                                property string gt: root._batCapacity + "%"
                                property string gl: root._batCharging ? "󱐋" : "󰁹"
                                property color onS: root.cOnSurf
                                onDialColChanged: requestPaint(); onCvChanged: requestPaint(); onOnSChanged: requestPaint()
                                Connections {
                                    target: root
                                    function on_BatCapacityChanged() { batDialArc.requestPaint() }
                                    function on_BatChargingChanged() { batDialArc.requestPaint() }
                                }
                                Component.onCompleted: requestPaint()
                                onPaint: {
                                    const ctx=getContext("2d"); ctx.clearRect(0,0,width,height)
                                    const cx=width/2,cy=height/2,r=27,lw=5
                                    const s=0.75*Math.PI,e=2.25*Math.PI
                                    ctx.lineWidth=lw; ctx.lineCap="round"
                                    ctx.beginPath(); ctx.arc(cx,cy,r,s,e)
                                    ctx.strokeStyle=Qt.rgba(root.cScrim.r,root.cScrim.g,root.cScrim.b,0.15).toString(); ctx.stroke()
                                    if(cv>0.005){
                                        ctx.beginPath(); ctx.arc(cx,cy,r,s,s+cv*(e-s))
                                        ctx.strokeStyle=dialCol.toString(); ctx.stroke()
                                    }
                                    ctx.fillStyle=Qt.rgba(dialCol.r,dialCol.g,dialCol.b,0.92).toString()
                                    ctx.font="15px 'Symbols Nerd Font Mono'"
                                    ctx.textAlign="center"; ctx.textBaseline="alphabetic"
                                    ctx.fillText(gl,cx,cy+2)
                                    ctx.fillStyle=Qt.rgba(onS.r,onS.g,onS.b,0.88).toString()
                                    ctx.font="bold 9px monospace"
                                    ctx.textBaseline="top"; ctx.fillText(gt,cx,cy+5)
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                text: "Battery"; color: root.cOnSurfVar; font.pixelSize: 9
                            }
                        }
                    }
                }

                // ── Power buttons row — floats centered below main panel ────────
                Item {
                    id: powerRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top:             centerPanel.bottom
                    anchors.topMargin:       10
                    width:  pwrRowInner.implicitWidth  + 32
                    height: pwrRowInner.implicitHeight + 20

                    // Frosted pill backdrop
                    // Pill mask for clipping blur + tint
                    Rectangle {
                        id: pwrMask
                        anchors.fill: parent; radius: height / 2
                        color: "white"; visible: false; layer.enabled: true
                    }

                    // Blurred wallpaper slice (same technique as centerPanel)
                    Item {
                        anchors.fill: parent
                        layer.enabled: wallImg.visible
                        layer.effect: MultiEffect { blurEnabled: true; blur: 1.0; blurMax: 64 }
                        layer.smooth: true
                        AnimatedImage {
                            x: -powerRow.x; y: -powerRow.y
                            width: mainRect.width; height: mainRect.height
                            source: root.wallpaperPath ? "file://" + root.wallpaperPath : ""
                            fillMode: Image.PreserveAspectCrop; smooth: true; playing: true; cache: true
                            visible: root.wallpaperPath !== ""
                        }
                    }

                    // inversePrimary tint overlay
                    Rectangle {
                        anchors.fill: parent; radius: height / 2
                        color: Qt.rgba(root.cInvPrimary.r, root.cInvPrimary.g, root.cInvPrimary.b, 0.55)
                        border.width: 1
                        border.color: Qt.rgba(root.cOutVar.r, root.cOutVar.g, root.cOutVar.b, 0.18)
                    }

                    // Clip pill so blur doesn't leak outside rounded corners
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        maskEnabled:      true
                        maskSource:       pwrMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin:  1.0
                    }

                    Row {
                        id: pwrRowInner
                        anchors.centerIn: parent
                        spacing: 4
                        // ── Suspend ──────────────────────────────────────────
                        Item {
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maSusp.containsMouse ? Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.85) : Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.65)
                                border.width: 1
                                border.color: _maSusp.containsMouse ? Qt.rgba(root.cWc6.r, root.cWc6.g, root.cWc6.b,0.65) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰒲"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: root.cWc6; opacity: _maSusp.containsMouse ? 1.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maSusp; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","suspend"]; pwrProc.running = true }
                            }
                        }

                        // ── Reboot ───────────────────────────────────────────
                        Item {
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maRebt.containsMouse ? Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.85) : Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.65)
                                border.width: 1
                                border.color: _maRebt.containsMouse ? Qt.rgba(root.cWc3.r, root.cWc3.g, root.cWc3.b,0.65) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰑙"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: root.cWc3; opacity: _maRebt.containsMouse ? 1.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maRebt; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","reboot"]; pwrProc.running = true }
                            }
                        }

                        // ── Hibernate (only shown when available on this OS) ──
                        Item {
                            width: 44; height: 44
                            visible: root._hibernateAvailable
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maHib.containsMouse ? Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.85) : Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.65)
                                border.width: 1
                                border.color: _maHib.containsMouse ? Qt.rgba(root.cWc2.r, root.cWc2.g, root.cWc2.b,0.65) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰈉"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: root.cWc2; opacity: _maHib.containsMouse ? 1.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maHib; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","hibernate"]; pwrProc.running = true }
                            }
                        }

                        // ── Shutdown ─────────────────────────────────────────
                        Item {
                            width: 44; height: 44
                            Rectangle {
                                anchors.fill: parent; radius: 22
                                color:        _maShut.containsMouse ? Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.85) : Qt.rgba(root.cOnSecondary.r, root.cOnSecondary.g, root.cOnSecondary.b, 0.65)
                                border.width: 1
                                border.color: _maShut.containsMouse ? Qt.rgba(root.cWc4.r, root.cWc4.g, root.cWc4.b,0.65) : "transparent"
                                Behavior on color       { ColorAnimation { duration: 130 } }
                                Behavior on border.color{ ColorAnimation { duration: 130 } }
                            }
                            Text {
                                anchors.centerIn: parent; text: "󰐥"
                                font.family: "Symbols Nerd Font Mono"; font.pixelSize: 17
                                color: root.cWc4; opacity: _maShut.containsMouse ? 1.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 130 } }
                            }
                            MouseArea {
                                id: _maShut; anchors.fill: parent
                                hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                onClicked: { pwrProc.command = ["systemctl","poweroff"]; pwrProc.running = true }
                            }
                        }
                    }
                }

                // Hidden TextInput for PIN
                TextInput {
                    id:pinInput; visible:false; focus:true; echoMode:TextInput.Password
                    onTextChanged: root.pinEntry=text
                    Connections {
                        target:root
                        function onPinEntryChanged(){ if(root.pinEntry===""&&pinInput.text!=="") pinInput.clear() }
                        function onFocusPinRequestChanged(){ pinInput.forceActiveFocus() }
                    }
                    Keys.onReturnPressed: root.submitPin()
                    Keys.onEnterPressed:  root.submitPin()
                    Keys.onEscapePressed: { pinInput.clear(); root.pinEntry="" }
                    Component.onCompleted: forceActiveFocus()
                }
            }
        }
    }
}
