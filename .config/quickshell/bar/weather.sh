#!/bin/bash

# Waybar Weather Module - Accurate Location Detection
# Uses Open-Meteo with local environmental overrides for high humidity

# --- CONFIGURATION ---
UNIT_STATE_FILE="/tmp/waybar-weather-unit"
WEATHER_CACHE_FILE="/tmp/astal-weather-cache.json"
LOCATION_CACHE_FILE="/tmp/waybar-weather-location"
IPINFO_CACHE_FILE="/tmp/waybar-weather-ipinfo.json"
CACHE_MAX_AGE=300  # 5 minutes
LOCATION_MAX_AGE=3600  # 1 hour

# Get current unit
CURRENT_UNIT=$(cat "$UNIT_STATE_FILE" 2>/dev/null || echo "metric")

PINNED_LOCATION_FILE="$HOME/.config/hyprcandy/weather-location.conf"

# ── Location resolution: pinned conf → ipinfo fallback ───────────────────────
if [ -f "$PINNED_LOCATION_FILE" ]; then
    # Written by the CC weather location search — contains LAT, LON, NAME
    source "$PINNED_LOCATION_FILE" 2>/dev/null
    DISPLAY_LOCATION="${NAME:-Pinned location}"
else
    # Fallback: IP geolocation (city-centroid, ~5–50 km accuracy)
    get_location() {
        if [ -f "$IPINFO_CACHE_FILE" ]; then
            CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$IPINFO_CACHE_FILE") ))
            if [ $CACHE_AGE -lt $LOCATION_MAX_AGE ]; then
                cat "$IPINFO_CACHE_FILE"
                return
            fi
        fi
        IPINFO_DATA=$(curl -sf --max-time 6 https://ipinfo.io/json)
        if [ -n "$IPINFO_DATA" ]; then
            echo "$IPINFO_DATA" > "$IPINFO_CACHE_FILE"
            echo "$IPINFO_DATA"
        elif [ -f "$IPINFO_CACHE_FILE" ]; then
            cat "$IPINFO_CACHE_FILE"
        else
            echo '{"loc":"0,0","city":"Unknown"}'
        fi
    }
    IPINFO=$(get_location)
    COORDINATES=$(echo "$IPINFO" | jq -r '.loc // "0,0"')
    LAT=$(echo "$COORDINATES" | cut -d',' -f1)
    LON=$(echo "$COORDINATES" | cut -d',' -f2)
    DISPLAY_LOCATION=$(echo "$IPINFO" | jq -r '.city // "Unknown"')
fi

# Open-Meteo API URL
WEATHER_URL="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&current=temperature_2m,relative_humidity_2m,apparent_temperature,is_day,weather_code,wind_speed_10m,precipitation&daily=weather_code,temperature_2m_max,temperature_2m_min&forecast_days=7&timezone=auto"

# Check cache freshness
if [ -f "$WEATHER_CACHE_FILE" ]; then
    CACHE_AGE=$(( $(date +%s) - $(stat -c %Y "$WEATHER_CACHE_FILE") ))
    if [ $CACHE_AGE -lt $CACHE_MAX_AGE ]; then
        WEATHER_DATA=$(cat "$WEATHER_CACHE_FILE")
    else
        WEATHER_DATA=$(curl -s "$WEATHER_URL")
        if [ -n "$WEATHER_DATA" ] && echo "$WEATHER_DATA" | jq -e '.current' >/dev/null 2>&1; then
            echo "$WEATHER_DATA" > "$WEATHER_CACHE_FILE"
        else
            WEATHER_DATA=$(cat "$WEATHER_CACHE_FILE" 2>/dev/null || echo '{}')
        fi
    fi
else
    WEATHER_DATA=$(curl -s "$WEATHER_URL")
    if [ -n "$WEATHER_DATA" ] && echo "$WEATHER_DATA" | jq -e '.current' >/dev/null 2>&1; then
        echo "$WEATHER_DATA" > "$WEATHER_CACHE_FILE"
    else
        echo '{"error":"Unable to fetch weather"}' >&2
        exit 1
    fi
fi

# Parse weather data with local override logic
jq --arg unit "$CURRENT_UNIT" \
   --arg display_loc "$DISPLAY_LOCATION" \
   -rc '
    def get_condition_info(code; is_day; humidity):
        # Clear sky
        if (code == 0) then {text: "Clear sky", icon: (if is_day == 1 then "󰖙" else "󰖔" end)}
        
        # Partly cloudy variants
        elif (code == 1) then {text: "Mainly clear", icon: (if is_day == 1 then "󰖕" else "󰼱" end)}
        elif (code == 2) then {text: "Partly cloudy", icon: (if is_day == 1 then "󰖕" else "󰼱" end)}
        
        # Overcast with humidity override
        elif (code == 3) then
            (if humidity >= 85 then {text: "Overcast (Rainy)", icon: (if is_day == 1 then "" else "" end)}
             else {text: "Overcast", icon: (if is_day == 1 then "󰼰" else "󰖑" end)} end)
        
        # Fog variants
        elif (code == 45) then {text: "Fog", icon: (if is_day == 1 then "" else "" end)}
        elif (code == 48) then {text: "Depositing Rime Fog", icon: (if is_day == 1 then "" else "" end)}
        
        # Drizzle variants
        elif (code == 51) then {text: "Light Drizzle", icon: "󰖗"}
        elif (code == 53) then {text: "Moderate Drizzle", icon: "󰖗"}
        elif (code == 55) then {text: "Dense Drizzle", icon: "󰖖"}
        elif (code == 56) then {text: "Light Freezing Drizzle", icon: "󰖒"}
        elif (code == 57) then {text: "Dense Freezing Drizzle", icon: "󰖒"}
        
        # Rain variants - distinct icons for intensity
        elif (code == 61) then {text: "Slight Rain", icon: "󰖗"}
        elif (code == 63) then {text: "Moderate Rain", icon: "󰖖"}
        elif (code == 65) then {text: "Heavy Rain", icon: "󰙾"}
        elif (code == 66) then {text: "Light Freezing Rain", icon: "󰙿"}
        elif (code == 67) then {text: "Heavy Freezing Rain", icon: "󰙿"}
        
        # Snow variants - distinct icons for intensity
        elif (code == 71) then {text: "Slight Snow", icon: "󰼶"}
        elif (code == 73) then {text: "Moderate Snow", icon: "󰜗"}
        elif (code == 75) then {text: "Heavy Snow", icon: "󰜘"}
        elif (code == 77) then {text: "Snow Grains", icon: "󰖘"}
        
        # Rain showers
        elif (code == 80) then {text: "Slight Rain Showers", icon: "󰖗"}
        elif (code == 81) then {text: "Moderate Rain Showers", icon: "󰖖"}
        elif (code == 82) then {text: "Violent Rain Showers", icon: "󰙾"}
        
        # Snow showers
        elif (code == 85) then {text: "Slight Snow Showers", icon: "󰼶"}
        elif (code == 86) then {text: "Heavy Snow Showers", icon: "󰜘"}
        
        # Thunderstorm variants
        elif (code == 95) then {text: "Thunderstorm", icon: "󰖓"}
        elif (code == 96) then {text: "Thunderstorm with Slight Hail", icon: "󰖓"}
        elif (code == 99) then {text: "Thunderstorm with Heavy Hail", icon: "󰖓"}
        
        else {text: "Unknown", icon: "󰖐"} end;

    .current as $current |
    get_condition_info($current.weather_code; $current.is_day; $current.relative_humidity_2m) as $condition |

    (if $unit == "metric" then
        { temp: $current.temperature_2m, feel: $current.apparent_temperature, unit: "°C", speed: "\($current.wind_speed_10m) km/h" }
    else
        { temp: ($current.temperature_2m * 9 / 5 + 32), feel: ($current.apparent_temperature * 9 / 5 + 32), unit: "°F", speed: "\($current.wind_speed_10m * 0.621371 | floor) mph" }
    end) as $data |

    {
        "text":    "\($data.temp | round)\($data.unit) \($condition.icon)",
        "icon":    $condition.icon,
        "value":   "\($data.temp | round)\($data.unit)",
        "tooltip": "Scroll-Up: °C\nScroll-Down: °F\n-------------------\nClick: Weather-Widget\nLocation: \($display_loc)\nCondition: \($condition.text)\nHumidity: \($current.relative_humidity_2m)%\nWind: \($data.speed)",
        "class":   "weather",
        "alt":     $condition.text
    }
' <<< "$WEATHER_DATA"
