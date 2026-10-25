pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// Weather for one location from Open-Meteo (no API key). Location comes
// from latitude/longitude, else `location` (geocoded), else the machine's
// IP. Refreshes every `interval` (ms) while `active`; a failed refresh
// keeps the last good data. Not a singleton: WeatherManager owns the one
// for the Weather settings.
QtObject {
  id: root

  // -- Settings --
  property var latitude: ""
  property var longitude: ""
  property string location: ""
  // "celsius" | "fahrenheit"
  property string units: "celsius"
  property int interval: 1800000
  // Off while no widget wants weather: keeps its data, never fetches
  property bool active: true

  // -- Data --
  // { latitude, longitude, name }, resolved once per location setting
  property var place: null
  // Open-Meteo forecast response: current, hourly (12h), daily (5 days)
  property var weather: null
  readonly property var current: weather?.current ?? null
  readonly property var condition: current ? conditionFor(current.weather_code, current.is_day) : null
  readonly property string unitSymbol: units === "fahrenheit" ? "°F" : "°C"

  // Feels-like, humidity and wind, as a line under the temperature
  readonly property string details: current ? I18n.tr("Feels like {0}°  ·  {1}% humidity  ·  {2} {3}", Math.round(current.apparent_temperature), current.relative_humidity_2m, Math.round(current.wind_speed_10m), weather.current_units?.wind_speed_10m ?? "") : ""

  // A forecast day's short name: "Today", else its weekday. Parsed at
  // local noon: a bare "YYYY-MM-DD" is UTC midnight, the day before west
  // of UTC.
  function dayLabel(index) {
    const date = weather?.daily?.time?.[index];
    if (!date)
      return "";
    return index === 0 ? I18n.tr("Today") : I18n.formatDate(new Date(date + "T12:00"), "ddd");
  }

  property bool _failing: false
  property bool _alive: true
  Component.onDestruction: _alive = false
  readonly property string _locationKey: [latitude, longitude, location].join("|")

  // WMO weather interpretation codes
  function conditionFor(code, isDay) {
    const day = isDay !== 0;
    if (code === 0)
      return {
        "icon": day ? "sunny" : "clear_night",
        "label": I18n.tr("Clear")
      };
    if (code <= 2)
      return {
        "icon": day ? "partly_cloudy_day" : "partly_cloudy_night",
        "label": I18n.tr("Partly cloudy")
      };
    if (code === 3)
      return {
        "icon": "cloud",
        "label": I18n.tr("Overcast")
      };
    if (code === 45 || code === 48)
      return {
        "icon": "foggy",
        "label": I18n.tr("Fog")
      };
    if (code >= 51 && code <= 57)
      return {
        "icon": "rainy",
        "label": I18n.tr("Drizzle")
      };
    if ([65, 67, 82].includes(code))
      return {
        "icon": "rainy_heavy",
        "label": I18n.tr("Heavy rain")
      };
    if ((code >= 61 && code <= 67) || (code >= 80 && code <= 82))
      return {
        "icon": "rainy",
        "label": I18n.tr("Rain")
      };
    if ((code >= 71 && code <= 77) || code === 85 || code === 86)
      return {
        "icon": "weather_snowy",
        "label": I18n.tr("Snow")
      };
    if (code >= 95)
      return {
        "icon": "thunderstorm",
        "label": I18n.tr("Thunderstorm")
      };
    return {
      "icon": "cloud",
      "label": I18n.tr("Unknown")
    };
  }

  // onFail (optional) replaces the warning, for requests with a fallback
  function getJson(url, onResult, onFail) {
    const xhr = new XMLHttpRequest();
    xhr.open("GET", url);
    xhr.onreadystatechange = () => {
      // A reply can land after this instance was destroyed (config reload)
      if (xhr.readyState !== XMLHttpRequest.DONE || !root || !root._alive)
        return;
      let result = null;
      if (xhr.status === 200) {
        try {
          result = JSON.parse(xhr.responseText);
        } catch (e) {}
      }
      if (!result) {
        if (onFail) {
          onFail();
          return;
        }
        // Warn once per outage, not on every retry
        if (!root._failing)
          console.warn(`[WeatherSource] Request failed (${xhr.status}): ${url}`);
        root._failing = true;
        return;
      }
      root._failing = false;
      onResult(result);
    };
    xhr.send();
  }

  function resolvePlace(then) {
    const p = root;
    const lat = parseFloat(p.latitude);
    const lon = parseFloat(p.longitude);
    if (!isNaN(lat) && !isNaN(lon)) {
      place = {
        "latitude": lat,
        "longitude": lon,
        "name": p.location || `${lat.toFixed(2)}, ${lon.toFixed(2)}`
      };
      then();
    } else if (p.location) {
      getJson(`https://geocoding-api.open-meteo.com/v1/search?count=1&name=${encodeURIComponent(p.location)}`, data => {
        const r = data.results?.[0];
        if (!r) {
          console.warn(`[WeatherSource] Unknown location: ${p.location}`);
          return;
        }
        root.place = {
          "latitude": r.latitude,
          "longitude": r.longitude,
          "name": [r.name, r.admin1, r.country_code].filter(Boolean).join(", ")
        };
        then();
      });
    } else {
      // Two free IP geolocation services, as either may rate-limit
      const fromIpapi = () => getJson("https://ipapi.co/json/", data => {
          if (data.latitude === undefined)
            return;
          root.place = {
            "latitude": data.latitude,
            "longitude": data.longitude,
            "name": [data.city, data.region_code].filter(Boolean).join(", ")
          };
          then();
        });
      getJson("https://ipinfo.io/json", data => {
        const [lat, lon] = (data.loc ?? "").split(",").map(Number);
        if (isNaN(lat) || isNaN(lon)) {
          fromIpapi();
          return;
        }
        root.place = {
          "latitude": lat,
          "longitude": lon,
          "name": [data.city, data.region].filter(Boolean).join(", ")
        };
        then();
      }, fromIpapi);
    }
  }

  function refresh() {
    if (!place) {
      resolvePlace(refresh);
      return;
    }
    const params = ["latitude=" + place.latitude, "longitude=" + place.longitude, "current=temperature_2m,apparent_temperature,weather_code,is_day,wind_speed_10m,relative_humidity_2m", "hourly=temperature_2m,weather_code,is_day", "forecast_hours=12", "daily=weather_code,temperature_2m_max,temperature_2m_min", "timezone=auto", "forecast_days=5", "temperature_unit=" + root.units, "wind_speed_unit=" + (root.units === "fahrenheit" ? "mph" : "kmh")];
    getJson("https://api.open-meteo.com/v1/forecast?" + params.join("&"), data => root.weather = data);
  }

  on_LocationKeyChanged: {
    place = null;
    weather = null;
    if (active)
      refreshSoon.restart();
  }
  onUnitsChanged: {
    weather = null;
    if (active)
      refreshSoon.restart();
  }

  // Coalesces setting changes into one refresh. A Timer rather than
  // Qt.callLater, so it dies with this instance on a config reload.
  property Timer _refreshSoon: Timer {
    id: refreshSoon
    interval: 250
    onTriggered: root.refresh()
  }

  property Timer _refreshTimer: Timer {
    interval: Math.max(60000, root.interval)
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }
}
