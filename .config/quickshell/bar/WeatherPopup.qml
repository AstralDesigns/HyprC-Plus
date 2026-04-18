pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io

PanelWindow {
    id: wxWin

    readonly property bool _barAtBottom: Config.barPosition === "bottom"
    readonly property real _barGap:    Config.outerMarginTop    + Config.barHeight + 6
    readonly property real _barGapBot: Config.outerMarginBottom + Config.barHeight + 6

    anchors { top: !_barAtBottom; bottom: _barAtBottom; left: true; right: true }
    margins {
        top:    _barAtBottom ? 0 : _barGap
        bottom: _barAtBottom ? _barGapBot : 0
    }

    implicitWidth:  560
    implicitHeight: wxPanel.implicitHeight

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer:     WlrLayer.Top
    WlrLayershell.namespace: "quickshell:weather-popup"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    color: "transparent"
    visible: WeatherPopupState.visible

    // ── Dismiss on focus change ───────────────────────────────────────────
    Connections {
        target: HyprlandFocusedClient
        ignoreUnknownSignals: true
        function onAddressChanged() {
            if (HyprlandFocusedClient.address !== "")
                WeatherPopupState.close()
        }
    }

    MouseArea { anchors.fill: parent; z: -1; onClicked: WeatherPopupState.close() }

    // ── State ─────────────────────────────────────────────────────────────
    readonly property string _pinnedLocFile: Quickshell.env("HOME") + "/.config/hyprcandy/weather-location.conf"
    readonly property string _locationCache: "/tmp/waybar-weather-ipinfo.json"
    readonly property string _weatherCache:  "/tmp/astal-weather-cache.json"

    property bool   _metric:   true
    property string _city:     ""
    property real   _lat:      0
    property real   _lon:      0
    property bool   _locReady: false

    property string _icon:    "󰖐"
    property string _condStr: "Loading…"
    property string _temp:    "--"
    property string _feels:   "--"
    property string _wind:    "--"
    property string _hum:     "--"
    property string _prec:    "--"

    property var _fcDays:  []
    property var _fcIcons: []
    property var _fcHi:    []
    property var _fcLo:    []

    // ── Helpers ───────────────────────────────────────────────────────────
    function _unitSuffix() { return _metric ? "°C" : "°F" }
    function _cvtTemp(c)   { return _metric ? Math.round(c) : Math.round(c * 9/5 + 32) }
    function _cvtWind(kmh) { return _metric ? Math.round(kmh) + " km/h" : Math.round(kmh * 0.621371) + " mph" }

    function _cond(code, isDay, hum) {
        const d = isDay !== 0
        if (code===0) return {t:'Clear Sky', i:isDay?'󰖙':'󰖔'};
    	if (code===1) return {t:'Mainly Clear', i:isDay?'󰖕':'󰼱'};
    	if (code===2) return {t:'Partly Cloudy', i:isDay?'󰖕':'󰼱'};
    	if (code===3) return hum>=85?{t:'Overcast (Rainy)',i:isDay?'':''}:{t:'Overcast',i:isDay?'󰼰':'󰖑'};
    	if (code===45||code===48) return {t:'Fog',i:isDay?'':''};
    	if (code>=51) return {t:'Light Drizzle',i:'󰖗'};
    	if (code>=53) return {t:'Moderate Drizzle',i:'󰖗'};
    	if (code>=55) return {t:'Dense Drizzle',i:'󰖖'};
    	if (code===56) return {t:'Light Freezing Drizzle',i:'󰖒'};
    	if (code===57) return {t:'Dense Freezing Drizzle',i:'󰖒'};
    	if (code===61) return {t:'Slight Rain',i:'󰖗'};
    	if (code===63) return {t:'Moderate Rain',i:'󰖖'};
    	if (code===65) return {t:'Heavy Rain',i:'󰙾'};
    	if (code===66||code===67) return {t:'Freezing Rain',i:'󰙿'};
    	if (code>=71&&code<=75) return {t:code===71?'Light Snow':code===73?'Moderate Snow':'Heavy Snow',i:'󰜗'};
    	if (code===77) return {t:'Snow Grains',i:'󰖘'};
    	if (code>=80&&code<=82) return {t:'Rain Showers',i:'󰙾'};
    	if (code===85||code===86) return {t:'Snow Showers',i:'󰼶'};
    	if (code===95) return {t:'Thunderstorm',i:'󰖓'};
    	if (code===96||code===99) return {t:'Thunderstorm + Hail',i:'󰖓'};
    	return {t:'Unknown',i:'󰖐'}
    }

    function _applyData(d) {
        const c = d.current
        const info = _cond(c.weather_code, c.is_day, c.relative_humidity_2m)
        _icon    = info.i
        _condStr = info.t
        _temp    = _cvtTemp(c.temperature_2m)       + _unitSuffix()
        _feels   = _cvtTemp(c.apparent_temperature) + _unitSuffix()
        _wind    = _cvtWind(c.wind_speed_10m)
        _hum     = c.relative_humidity_2m + "%"
        _prec    = (c.precipitation || 0) + " mm"
        if (d.daily) {
            const DAYS = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"]
            const dates = d.daily.time || []
            const dn=[]; const ic=[]; const hi=[]; const lo=[]
            for (let i = 0; i < Math.min(7, dates.length); i++) {
                const dt = new Date(dates[i] + "T12:00:00")
                dn.push(i === 0 ? "Today" : DAYS[dt.getDay()])
                ic.push(_cond(d.daily.weather_code[i], 1, 0).i)
                hi.push(_cvtTemp(d.daily.temperature_2m_max[i]) + _unitSuffix())
                lo.push(_cvtTemp(d.daily.temperature_2m_min[i]) + _unitSuffix())
            }
            _fcDays = dn; _fcIcons = ic; _fcHi = hi; _fcLo = lo
        }
    }

    function _startLoad() {
        unitReadProc.running = true
    }

    // ── Processes ─────────────────────────────────────────────────────────

    Process {
        id: unitReadProc
        command: ["bash", "-c", "cat /tmp/waybar-weather-unit 2>/dev/null || echo metric"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                wxWin._metric = this.text.trim() !== "imperial"
                locReadProc.running = true
            }
        }
    }

    Process {
        id: locReadProc
        property string _pinnedFile: wxWin._pinnedLocFile
        property string _cacheFile:  wxWin._locationCache
        command: ["bash", "-c",
            "P=\"$1\"; C=\"$2\"; " +
            "if [ -f \"$P\" ]; then source \"$P\" 2>/dev/null && printf '%s,%s,%s' \"$LAT\" \"$LON\" \"$NAME\" && echo; " +
            "elif [ -f \"$C\" ]; then jq -r '(.loc)+\",\"+(.city//\"Unknown\")' \"$C\" 2>/dev/null; " +
            "else echo FETCH; fi",
            "--", locReadProc._pinnedFile, locReadProc._cacheFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const t = this.text.trim()
                if (!t || t === "FETCH") { ipinfoProc.running = true; return }
                const p = t.split(",")
                const lat = parseFloat(p[0])
                const lon = parseFloat(p[1])
                if (p.length >= 2 && !isNaN(lat) && lat !== 0) {
                    wxWin._lat = lat; wxWin._lon = lon
                    wxWin._city = p.slice(2).join(",") || "Unknown"
                    wxWin._locReady = true
                    fetchProc._doFetch()
                } else {
                    ipinfoProc.running = true
                }
            }
        }
    }

    Process {
        id: ipinfoProc
        property string _cacheFile: wxWin._locationCache
        command: ["bash", "-c",
            "curl -sf --max-time 8 https://ipinfo.io/json | tee \"$1\"",
            "--", ipinfoProc._cacheFile]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    const c = (d.loc || "0,0").split(",")
                    wxWin._lat = parseFloat(c[0]) || 0
                    wxWin._lon = parseFloat(c[1]) || 0
                    wxWin._city = d.city || "Unknown"
                    wxWin._locReady = true
                    fetchProc._doFetch()
                } catch(e) {}
            }
        }
    }

    // Weather fetch — URL injected via argv to avoid command-binding issues
    Process {
        id: fetchProc
        property string _url: ""
        property string _cache: wxWin._weatherCache
        command: ["bash", "-c",
            "curl -sf --max-time 12 \"$1\" | tee \"$2\"",
            "--", fetchProc._url, fetchProc._cache]
        running: false
        function _doFetch() {
            if (!wxWin._locReady) return
            _url = "https://api.open-meteo.com/v1/forecast" +
                "?latitude=" + wxWin._lat + "&longitude=" + wxWin._lon +
                "&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,precipitation" +
                "&daily=weather_code,temperature_2m_max,temperature_2m_min" +
                "&forecast_days=7&timezone=auto"
            if (!running) running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d && d.current) { wxWin._applyData(d); return }
                } catch(e) {}
                cacheReadProc.running = true
            }
        }
    }

    Process {
        id: cacheReadProc
        property string _cache: wxWin._weatherCache
        command: ["bash", "-c", "cat \"$1\" 2>/dev/null", "--", cacheReadProc._cache]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text)
                    if (d && d.current) wxWin._applyData(d)
                } catch(e) {}
            }
        }
    }

    Process {
        id: unitToggleProc
        property string _nextUnit: "metric"
        command: ["bash", "-c", "echo \"$1\" > /tmp/waybar-weather-unit", "--", unitToggleProc._nextUnit]
        running: false
        onExited: { unitReadProc.running = true }
    }

    // ── Kick on open / refresh ────────────────────────────────────────────
    Connections {
        target: WeatherPopupState
        function onVisibleChanged() {
            if (WeatherPopupState.visible) wxWin._startLoad()
        }
    }
    Component.onCompleted: { if (WeatherPopupState.visible) wxWin._startLoad() }

    Timer {
        interval: 300000; repeat: true
        running: WeatherPopupState.visible
        onTriggered: fetchProc._doFetch()
    }

    // ── Panel ─────────────────────────────────────────────────────────────
    Rectangle {
        id: wxPanel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: 560
        implicitHeight: wxCol.implicitHeight + 32

        radius: Config.barMode === "island" ? Config.islandRadius : Config.barRadius
        color:  Qt.rgba(Theme.cOnSecondary.r, Theme.cOnSecondary.g, Theme.cOnSecondary.b, 0.42)
        border.width: 1
        border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.40)

        scale: WeatherPopupState.visible ? 1.0 : 0.94
        transformOrigin: wxWin._barAtBottom ? Item.Bottom : Item.Top
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            id: wxCol
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16 }
            spacing: 10

            // Header
            RowLayout {
                Layout.fillWidth: true; spacing: 6
                Text {
                    text: "󰖐  Weather"; color: Theme.cPrimary
                    font.pixelSize: 13; font.weight: Font.Medium; font.family: Config.fontFamily
                }
                Item { Layout.fillWidth: true }
                Text {
                    text: wxWin._city ? "󰍎  " + wxWin._city : ""
                    color: Theme.cOnSurfVar; font.pixelSize: 11; font.family: Config.labelFont
                    elide: Text.ElideRight; Layout.maximumWidth: 180
                }
                Rectangle {
                    width: 56; height: 24; radius: 99
                    color: unitHov.containsMouse
                        ? Qt.rgba(Theme.cPrimary.r, Theme.cPrimary.g, Theme.cPrimary.b, 0.22)
                        : Qt.rgba(Theme.cSurfHi.r,  Theme.cSurfHi.g,  Theme.cSurfHi.b,  0.55)
                    border.color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.35)
                    border.width: 1
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Text {
                        anchors.centerIn: parent
                        text: wxWin._metric ? "°C / °F" : "°F / °C"
                        color: Theme.cPrimary; font.pixelSize: 10; font.weight: Font.Medium
                    }
                    MouseArea {
                        id: unitHov
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            unitToggleProc._nextUnit = wxWin._metric ? "imperial" : "metric"
                            if (!unitToggleProc.running) unitToggleProc.running = true
                        }
                    }
                }
                Rectangle {
                    width: 24; height: 24; radius: 99; color: "transparent"
                    MouseArea {
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        onClicked: WeatherPopupState.close()
                        Text {
                            anchors.centerIn: parent; text: "󰅙"
                            color: parent.containsMouse ? Theme.cOnSurf : Theme.cOnSurfVar
                            font.pixelSize: 14; font.family: Config.fontFamily
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28) }

            // Current conditions
            RowLayout {
                Layout.fillWidth: true; spacing: 18
                Column {
                    spacing: 2; Layout.alignment: Qt.AlignVCenter
                    Text {
                        text: wxWin._icon; color: Theme.cPrimary
                        font.pixelSize: 52; font.family: Config.fontFamily
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: wxWin._temp; color: Theme.cOnSurf
                        font.pixelSize: 26; font.weight: Font.Bold; font.family: Config.labelFont
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                    Text {
                        text: wxWin._condStr; color: Theme.cOnSurfVar
                        font.pixelSize: 11; font.family: Config.labelFont
                        horizontalAlignment: Text.AlignHCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
                Grid {
                    columns: 2; rowSpacing: 6; columnSpacing: 20
                    Layout.alignment: Qt.AlignVCenter
                    Repeater {
                        model: [
                            { glyph: "󰔐", label: "Feels",    val: wxWin._feels },
                            { glyph: "󰖌", label: "Humidity", val: wxWin._hum   },
                            { glyph: "󰖝", label: "Wind",     val: wxWin._wind  },
                            { glyph: "󰖗", label: "Precip",   val: wxWin._prec  }
                        ]
                        delegate: Row {
                            required property var modelData
                            spacing: 6
                            Text {
                                text: modelData.glyph; color: Theme.cPrimary
                                font.pixelSize: 14; font.family: Config.fontFamily
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                spacing: 0
                                Text { text: modelData.label; color: Theme.cOnSurfVar; font.pixelSize: 9;  font.family: Config.labelFont }
                                Text { text: modelData.val;   color: Theme.cOnSurf;    font.pixelSize: 12; font.weight: Font.Medium; font.family: Config.labelFont }
                            }
                        }
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; height: 1; color: Qt.rgba(Theme.cOutVar.r, Theme.cOutVar.g, Theme.cOutVar.b, 0.28) }

            // 7-day forecast
            RowLayout {
                Layout.fillWidth: true; spacing: 0
                Repeater {
                    model: wxWin._fcDays.length
                    delegate: Item {
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: fcCol.implicitHeight
                        Column {
                            id: fcCol
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            Text {
                                text: wxWin._fcDays[index] || "--"
                                color: index === 0 ? Theme.cPrimary : Theme.cOnSurfVar
                                font.pixelSize: 9; font.weight: index === 0 ? Font.Medium : Font.Normal
                                font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: wxWin._fcIcons[index] || "󰖐"
                                color: Theme.cPrimary; font.pixelSize: 18; font.family: Config.fontFamily
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: wxWin._fcHi[index] || "--"
                                color: Theme.cOnSurf; font.pixelSize: 10; font.weight: Font.Medium; font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                            Text {
                                text: wxWin._fcLo[index] || "--"
                                color: Theme.cOnSurfVar; font.pixelSize: 9; font.family: Config.labelFont
                                horizontalAlignment: Text.AlignHCenter
                                anchors.horizontalCenter: parent.horizontalCenter
                            }
                        }
                    }
                }
            }

            Item { height: 4 }
        }
    }
}
