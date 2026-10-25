pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Battery section. Named BatteryConfig because `Battery` is
// a bar widget and module type.
QtObject {
  readonly property var _c: ConfigManager.config.Battery

  // Notify on reaching the low, then the critical level
  readonly property bool notify: _c.notify
  // Percentages at or below which the battery is low / critical
  readonly property int lowThreshold: _c.lowThreshold
  readonly property int criticalThreshold: _c.criticalThreshold
}
