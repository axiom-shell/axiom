pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Weather section: the one location and units every
// weather widget and module shows (see WeatherManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Weather

  readonly property string location: _c.location
  readonly property string latitude: _c.latitude
  readonly property string longitude: _c.longitude
  // "celsius" | "fahrenheit"
  readonly property string units: _c.units
  // How often it's fetched (ms)
  readonly property int interval: _c.interval
}
