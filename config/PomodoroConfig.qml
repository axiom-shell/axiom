pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Pomodoro section: the session and break lengths every
// pomodoro widget and module runs (see PomodoroManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Pomodoro

  // Lengths (ms)
  readonly property int work: _c.work
  readonly property int shortBreak: _c.shortBreak
  readonly property int longBreak: _c.longBreak
  // Focus sessions before a long break
  readonly property int longBreakEvery: _c.longBreakEvery
  readonly property bool autoStartBreaks: _c.autoStartBreaks
  readonly property bool autoStartWork: _c.autoStartWork
  readonly property bool notify: _c.notify
  // The lengths as PomodoroCycle takes them
  readonly property var settings: ({
      "work": root.work,
      "shortBreak": root.shortBreak,
      "longBreak": root.longBreak,
      "longBreakEvery": root.longBreakEvery
    })
}
