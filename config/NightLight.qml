pragma Singleton
import QtQuick
import qs.services.core

// Reader for the NightLight section: warmer colors through hyprsunset or
// wlsunset, run by NightLightManager.
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.NightLight

  readonly property bool schedule: _c.schedule
  // "HH:MM", on from startAt until endAt (past midnight when it's earlier)
  readonly property string startAt: _c.startAt
  readonly property string endAt: _c.endAt
  // Kelvin
  readonly property int temperature: _c.temperature
  // Percent; 100 leaves it alone
  readonly property int gamma: _c.gamma

  // The ranges they may be set in (the schema's), for controls
  readonly property var _schema: ConfigManager.configSchema.properties.NightLight.properties
  readonly property int minTemperature: _schema.temperature.minimum
  readonly property int maxTemperature: _schema.temperature.maximum
  readonly property int minGamma: _schema.gamma.minimum
  readonly property int maxGamma: _schema.gamma.maximum
}
