import QtQuick

// Stand-in for Quickshell's SystemClock in the layout harness: a fixed date.
QtObject {
  enum Precision {
    Hours,
    Minutes,
    Seconds
  }

  property int precision: SystemClock.Hours
  readonly property date date: new Date(2026, 9, 5, 12, 0, 0)
}
