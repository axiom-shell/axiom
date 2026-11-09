pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// Base for bar widgets that draw their own content (icon + label widgets
// extend BarIconWidget instead): the inputs every widget gets from
// BarWidgetHost, and its orientation from the bar. One that wants a
// background (drawn under it by its WidgetGroup, in the bar's widget style)
// sets hasBackground and its accentField (or accentColor), and draws in
// `colors`.
Item {
  id: root

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
  // The color field its accentColor shows for its state ("" for none or a
  // color of its own), and that color. Only its Auto own color
  // (`accentAuto`) gives way to the bar's gradient.
  property string accentField: ""
  property color accentColor: Theme.resolveColor(properties[accentField] ?? "")
  // Its Auto fields' roles (BarsConfig.withAutoColors), and where it sits
  // along its bar as laid out, for the bar's gradient (set by its host)
  property var autoColors: ({})
  property real barOffset: 0
  property real barLength: 0
  readonly property bool accentAuto: root.autoColors[root.accentField] === "accent"
  // Where its middle sits along the bar (0-1), or -1 without a gradient
  readonly property real barSpot: root.barLength > 0 ? (root.barOffset + (root.isVertical ? root.height : root.width) / 2) / root.barLength : -1
  // Where a point `along` the bar from `item`'s start (an item inside it)
  // sits along the bar (0-1), or -1 without a gradient. Read when what
  // places the point changes: mapping isn't a binding.
  function barSpotOf(item: Item, along: real): real {
    if (root.barLength <= 0)
      return -1;
    const point = item.mapToItem(root, root.isVertical ? 0 : along, root.isVertical ? along : 0);
    return (root.barOffset + (root.isVertical ? point.y : point.x)) / root.barLength;
  }
  // Filled while its hit area is hovered, with the bar's "Fill on hover"
  // (off for a widget whose parts fill instead: Workspaces' cells)
  property bool fillsOnHover: true
  // A level (0-1) its WidgetGroup fills its background's shape to, along
  // the bar (up a vertical one), in backgroundLevelColor; -1 for none (a custom
  // widget's pill style)
  property real backgroundLevel: -1
  property color backgroundLevelColor: "transparent"
  readonly property var colors: BarsConfig.widgetColors(barConfig, accentColor, properties.foregroundColor, {
    "hovered": fillsOnHover && (hitArea?.hovered ?? false),
    "spot": barSpot,
    "auto": accentAuto
  })
}
