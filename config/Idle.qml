pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Idle section: hypridle, run by HypridleManager. Timeouts
// are ms, 0 turning that step off.
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Idle
  // The whole section, so HypridleManager re-renders on any change
  readonly property string _json: JSON.stringify(_c)

  readonly property bool enabled: _c.enabled
  readonly property int dimTimeout: _c.dim.timeout
  // "to": down to dimLevel%; "by": dimBy% off each screen's brightness
  readonly property string dimMode: _c.dim.mode
  readonly property int dimLevel: _c.dim.level
  readonly property int dimBy: _c.dim.by
  readonly property int lockTimeout: _c.lock.timeout
  readonly property int screenOffTimeout: _c.screenOff.timeout
  readonly property int suspendTimeout: _c.suspend.timeout
  readonly property bool lockBeforeSleep: _c.lockBeforeSleep
  readonly property bool screenOnAfterSleep: _c.screenOnAfterSleep
  readonly property bool respectInhibitors: _c.respectInhibitors
  // [{ id, enabled, timeout (ms), onTimeout, onResume }]
  readonly property var listeners: _c.items
}
