pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Stopwatch section: the one-off timer's presets and
// whether its end notifies (see StopwatchManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Stopwatch

  // Durations as typed ("5m", "10m tea"), for StopwatchClock.parse
  readonly property var presets: _c.presets
  readonly property bool notify: _c.notify
}
