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

  readonly property bool accentAuto: root.autoColors[root.accentField] === "accent"
  // Where its middle sits along the bar (0-1), or -1 without a gradient
  readonly property real barSpot: BarGradient.spot(0, root.length, root.barOffset, root.barLength)
  readonly property var colors: BarsConfig.widgetColors(root.barConfig, root.accentColor, root.properties?.foregroundColor, {
    "splits": root.splits,
    "hovered": root.hovered,
    "spot": root.barSpot,
    "auto": root.accentAuto
  })
}
