pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core

// Weather shared by every widget that shows it, for the Weather settings:
// axiom's `weather` topic, which fetches Open-Meteo's forecast for their
// coordinates, else their location (geocoded), else the machine's IP,
// every `interval` while some widget wants it. A failed fetch keeps the
// last good data, and so does stopping, so a widget created again (the
// overlay reopening) shows it at once while it refreshes.
//   WeatherManager.acquire(owner)
//   WeatherManager.release(owner)
//   WeatherManager.weather .current .condition .place …
QtObject {
  id: root

  // { latitude, longitude, name }
  readonly property var place: _shown?.place ?? null
  // Open-Meteo's forecast: current, hourly (12h), daily (5 days)
  readonly property var weather: _shown?.weather ?? null
  readonly property var current: weather?.current ?? null
  readonly property var condition: current ? conditionFor(current.weather_code, current.is_day) : null
  readonly property string unitSymbol: WeatherConfig.units === "fahrenheit" ? "°F" : "°C"

  // Feels-like, humidity and wind, as a line under the temperature
  readonly property string details: current ? I18n.tr("Feels like {0}°  ·  {1}% humidity  ·  {2} {3}", Math.round(current.apparent_temperature), current.relative_humidity_2m, Math.round(current.wind_speed_10m), weather.current_units?.wind_speed_10m ?? "") : ""

  function acquire(owner) {
    _registry.acquire(owner, true);
  }

  function release(owner) {
    _registry.release(owner);
  }

  // A forecast day's short name: "Today", else its weekday. Parsed at
  // local noon: a bare "YYYY-MM-DD" is UTC midnight, the day before west
  // of UTC.
  function dayLabel(index) {
    const date = weather?.daily?.time?.[index];
    if (!date)
      return "";
    return index === 0 ? I18n.tr("Today") : I18n.formatDate(new Date(date + "T12:00"), "ddd");
  }

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

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}

  // The last state pushed, shown only while it answers the settings as
  // they are (a location or units change shows nothing until it lands)
  property var _state: null
  readonly property var _shown: {
    const s = root._state;
    return s && s.location === WeatherConfig.location && s.latitude === WeatherConfig.latitude && s.longitude === WeatherConfig.longitude && s.units === WeatherConfig.units ? s : null;
  }

  // The request as one string, so axiom is asked again only when it
  // really changes
  readonly property string _requestKey: _registry.active ? JSON.stringify({
    "location": WeatherConfig.location,
    "latitude": WeatherConfig.latitude,
    "longitude": WeatherConfig.longitude,
    "units": WeatherConfig.units,
    "interval": WeatherConfig.interval
  }) : ""

  on_RequestKeyChanged: {
    if (root._requestKey !== "")
      BackendManager.acquire("weather", JSON.parse(root._requestKey));
    else
      BackendManager.release("weather");
  }

  Component.onCompleted: BackendManager.listen("weather.state", state => root._state = state)
}
