pragma Singleton
import QtQuick

import qs.config
import qs.services.core

// Weather shared by every widget that shows it: one WeatherSource for the
// Weather settings' location and units, fetching while some widget wants
// it. Stopped, it keeps its last data, so a widget created again (the
// overlay reopening) shows it at once while it refreshes.
//   WeatherManager.acquire(owner)
//   WeatherManager.release(owner)
//   WeatherManager.source   // .weather .current .condition .place …
QtObject {
  id: root

  readonly property WeatherSource source: WeatherSource {
    latitude: WeatherConfig.latitude
    longitude: WeatherConfig.longitude
    location: WeatherConfig.location
    units: WeatherConfig.units
    interval: WeatherConfig.interval
    active: root._registry.active
  }

  function acquire(owner) {
    _registry.acquire(owner, true);
  }

  function release(owner) {
    _registry.release(owner);
  }

  // -- Private --
  property ConsumerRegistry _registry: ConsumerRegistry {}
}
