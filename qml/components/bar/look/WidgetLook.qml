pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.components.methods

// What a bar widget draws in on its bar (BarsConfig.widgetColors): its
// color for its state, whether that's its Auto own color, and where it
// sits along the bar for the bar's gradient. BarWidget's and
// BarIconWidget's, which pass its inputs through as their own.
QtObject {
  id: root

  required property var barConfig
  property var properties
  // Its widget's length along the bar
  property real length: 0
  // The color field its accentColor shows for its state ("" for none or a
  // color of its own), and that color. Only its Auto own color
  // (`accentAuto`) gives way to the bar's gradient.
  property string accentField: ""
  property color accentColor: Theme.resolveColor(root.properties?.[root.accentField] ?? "")
  // Its Auto fields' roles (BarsConfig.withAutoColors), and where it sits
  // along its bar as laid out, for the bar's gradient (set by its host)
  property var autoColors: ({})
  property real barOffset: 0
  property real barLength: 0
  // It shows an icon part and a label apart (split), and the pointer is
  // over it (Fill on hover)
  property bool splits: false
  property bool hovered: false
  // It draws a pill level (its background filled to its value)
  property bool level: false
  // "Colour the text by state" (BarWidgetStyle.stateContent): the display
  // `appearance` ({ colorText }) or null for none, the color of its state
  // and whether it has one now
  property var appearance: null
  // (the colour of its state as drawn: colors.accent)
  property color stateColor: root.colors.accent
  property bool hasState: true
  // Its text color's name: a widget with no field for it (the tray,
  // Workspaces: their heads, SplitLead) the field's default
  readonly property string _foreground: root.properties?.foregroundColor ?? "base00"

  readonly property bool accentAuto: root._gradedRoles.includes(root.autoColors[root.accentField])
  // Where its middle sits along the bar (0-1), or -1 without a gradient
  readonly property real barSpot: BarGradient.spot(0, root.length, root.barOffset, root.barLength)
  readonly property var colors: BarsConfig.widgetColors(root.barConfig, root.accentColor, root._foreground, {
    "splits": root.splits,
    "hovered": root.hovered,
    "spot": root.barSpot,
    "auto": root.accentAuto,
    "level": root.level
  })
  // What its text and its icon draw in: its colors', or its state's
  // where its appearance colours by state
  readonly property var content: BarWidgetStyle.stateContent(root.colors, root.appearance, root.stateColor, root.hasState)

  // A color of the widget's own on its content, nudged to read where
  // `part` ("text" | "icon") sits
  function contentColor(color, part) {
    return BarWidgetStyle.content(root.colors, color, part);
  }

  // The Auto field roles that give way to the bar's gradient: a widget's
  // own color and its usual resting state
  readonly property var _gradedRoles: ["accent", "rest"]

  // `field`'s color as this widget draws it here: the gradient's where it
  // sits when the field is Auto in a role that gives way, else its own
  function drawnColor(field) {
    const own = Theme.resolveColor(root.properties?.[field] ?? "");
    if (root.barSpot < 0 || !root._gradedRoles.includes(root.autoColors[field]))
      return own;
    const stops = root.barConfig.palette.gradientStops;
    return stops ? BarGradient.gradientAt(stops, root.barSpot) : own;
  }
}
