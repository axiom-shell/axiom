pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core

// Weather for every widget that shows it: axiom's `weather` topic, which
// fetches Open-Meteo's forecast for each place the widgets ask for (their
// coordinates, else their location, geocoded, else the machine's IP),
// every `interval` while some widget wants it. Each widget registers its
// own place and unit and reads its own state; one request carries every
// distinct place. A failed fetch keeps the last good data of that place
// (with none, its state's `error` says why), and so does stopping, so a
// widget created again (the overlay reopening) shows it at once while it
// refreshes.
//   WeatherManager.acquire(owner, { location, units })   // no request: the Weather settings' place and unit
//   WeatherManager.release(owner)
//   WeatherManager.stateFor({ location, units })  // { place, weather, error, units } or null
//   WeatherManager.conditionOf(weather) / detailsOf(weather) / dayLabel(daily, index)   // a state's weather, as text
QtObject {
  id: root

  // `request.location` '' is the Weather settings' place; `units`
  // "default" follows Weather › Units (WeatherConfig.unitsOf)
  function acquire(owner, request) {
    _registry.acquire(owner, {
      "location": request?.location ?? "",
      "units": request?.units ?? "default"
    });
  }

  function release(owner) {
    _registry.release(owner);
  }

  // The pushed state for `request` ({ location, units }), as
  // { place, weather, error, units }, or null while there is none (a
  // place or unit change shows nothing until it lands). An error state has
  // no place or weather (its zero Forecast marshals with null arrays).
  function stateFor(request) {
    const want = root._settingsOf(request);
    const s = root._states.find(x => x.location === want.location && x.latitude === want.latitude && x.longitude === want.longitude && x.units === want.units);
    if (!s)
      return null;
    return {
      "place": s.error ? null : s.place,
      "weather": s.error ? null : s.weather,
      "error": s.error,
      "units": s.units
    };
  }

  // A forecast day's short name: "Today", else its weekday. Parsed at
  // local noon: a bare "YYYY-MM-DD" is UTC midnight, the day before west
  // of UTC.
  function dayLabel(daily, index) {
    const date = daily?.time?.[index];
    if (!date)
      return "";
    return index === 0 ? I18n.tr("Today") : I18n.formatDate(new Date(date + "T12:00"), "ddd");
  }

  // Feels-like, humidity and wind of a forecast, as a line under the
  // temperature
  function detailsOf(weather) {
    const current = weather?.current;
    return current ? I18n.tr("Feels like {0}°  ·  {1}% humidity  ·  {2} {3}", Math.round(current.apparent_temperature), current.relative_humidity_2m, Math.round(current.wind_speed_10m), weather.current_units?.wind_speed_10m ?? "") : "";
  }

  // { icon, label } of a forecast's current weather, or null with none
  function conditionOf(weather) {
    const current = weather?.current;
    return current ? root.conditionFor(current.weather_code, current.is_day) : null;
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

  // The states last pushed, one per place asked for, each carrying its
  // request
  property var _states: []

  // `request` ({ location, units }) as the daemon's place: location ''
  // is the Weather settings' (its coordinates too), units resolved
  function _settingsOf(request) {
    const location = request?.location ?? "";
    const own = location === "";
    return {
      "location": own ? WeatherConfig.location : location,
      "latitude": own ? WeatherConfig.latitude : "",
      "longitude": own ? WeatherConfig.longitude : "",
      "units": WeatherConfig.unitsOf(request?.units ?? "default")
    };
  }

  // The request as one string, so axiom is asked again only when it
  // really changes: every distinct place registered
  readonly property string _requestKey: {
    if (!_registry.active)
      return "";
    const places = [];
    _registry.requests.forEach(r => {
      const p = JSON.stringify(root._settingsOf(r));
      if (!places.includes(p))
        places.push(p);
    });
    return JSON.stringify({
      "interval": WeatherConfig.interval,
      "places": places.map(p => JSON.parse(p))
    });
  }

  on_RequestKeyChanged: {
    if (root._requestKey !== "")
      BackendManager.acquire("weather", JSON.parse(root._requestKey));
    else
      BackendManager.release("weather");
  }

  Component.onCompleted: BackendManager.listen("weather.state", state => root._states = state)
}
