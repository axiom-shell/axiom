pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// Base for bar widgets that draw their own content (icon + label widgets
// extend BarIconWidget instead): the inputs every widget gets from
// BarWidgetHost, and its orientation from the bar. One that wants a
// background (drawn under it by its WidgetGroup, in the bar's widget style)
// sets hasBackground and its accentColor, and draws in `colors`.
Item {
  property var barConfig
  property var panel
  property var screen
  property var properties
  // Where its pointer areas go, in its background's shape (set by its
  // BarWidgetHost; null: its own bounds)
  property var hitArea: null

  readonly property bool isVertical: barConfig.vertical

  // Kept at the start of its drawn size while that catches up with a new
  // one, rather than centred in it: for a widget that grows and shrinks at
  // its end, whose start shouldn't drift meanwhile (Workspaces' strip)
  property bool pinStart: false

  property bool hasBackground: false
  property color accentColor: "transparent"
  // A level (0-1) its WidgetGroup fills its background's shape to, along
  // the bar (up a vertical one), in fillShareColor; -1 for none (a custom
  // widget's pill style)
  property real fillShare: -1
  property color fillShareColor: "transparent"
  readonly property var colors: BarsConfig.widgetColors(barConfig, accentColor, properties.foregroundColor)
}
