pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config

// Base for icon + label bar modules: the inputs every module gets from
// BarWidgetHost, orientation from the bar, and the configured colors.
// Modules override accentColor for their states; how it shows (a
// background, tint, outline, line or the icon's color) is the bar's widget
// style, and the background is drawn under the module by its WidgetGroup.
//
// Clicks: set `clickable` (and `acceptedButtons` beyond the left one) and
// handle clicked(button); a clickable widget shows a pointer and dims while
// pressed, and does nothing while `hidden`. Set `scrollable` to get
// scrolled(steps), +1 per wheel notch up. `dim` fades the widget (e.g. stale
// data, a pulse) on top of the press.
IconTextWidget {
  id: root

  property var barConfig
  property var panel
  property var screen
  property var properties
  // Where its pointer areas go, in its background's shape (set by its
  // BarWidgetHost; null: its own bounds)
  property var hitArea: null

  property bool clickable: false
  property int acceptedButtons: Qt.LeftButton
  property bool scrollable: false
  property real dim: 1
  readonly property bool pressed: clickArea.pressed
  // The pointer is over it (an edge menu this opened stays open
  // meanwhile). One taking no clicks or scrolls has no click area: its
  // hit area's hover, else its own bounds'
  readonly property bool hovered: clickArea.enabled ? clickArea.containsMouse : root.hitArea ? root.hitArea.hovered : hover.hovered
  // The bar's inner side, where its tooltip opens
  readonly property int innerEdges: barConfig.top ? Edges.Bottom : barConfig.bottom ? Edges.Top : barConfig.left ? Edges.Right : Edges.Left

  signal clicked(int button)
  signal scrolled(real steps)

  isVertical: barConfig.vertical
  crossSize: barConfig.thickness
  // Sized by the bar, not the Widget section (that's for panels)
  padding: barConfig.innerPadding
  fontSize: barConfig.fontSize
  // The icon's gap to its label (6 px at the default inner spacing of 4)
  spacing: barConfig.innerGap * 1.5
  iconSpacing: barConfig.innerGap
  // The color field its accentColor shows for its state ("" for a color
  // of its own: a failure's error), and that color. Only its Auto own
  // color (`accentAuto`) gives way to the bar's gradient.
  property string accentField: "backgroundColor"
  property color accentColor: Theme.resolveColor(properties[accentField] ?? "")
  // Its Auto fields' roles (BarsConfig.withAutoColors), and where it sits
  // along its bar as laid out, for the bar's gradient (set by its host)
  property var autoColors: ({})
  property real barOffset: 0
  property real barLength: 0
  readonly property bool accentAuto: root.autoColors[root.accentField] === "accent"
  // Where its middle sits along the bar (0-1), or -1 without a gradient
  readonly property real barSpot: root.barLength > 0 ? (root.barOffset + (root.isVertical ? root.height : root.width) / 2) / root.barLength : -1
  // On a split bar, its icon part and label set apart (BarShapes.splitRoom)
  splitRoom: barConfig.splitRoom
  // What it draws in on this bar (filled while its hit area is hovered,
  // with the bar's "Fill on hover")
  readonly property var colors: BarsConfig.widgetColors(barConfig, accentColor, properties.foregroundColor, {
    "splits": root.splits,
    "hovered": root.hitArea?.hovered ?? false,
    "spot": root.barSpot,
    "auto": root.accentAuto
  })
  // Whether its WidgetGroup draws a background under it, and an outline
  // in its shape while it's hovered
  property bool hasBackground: !hidden
  property bool hoverOutline: false
  // A level (0-1) its WidgetGroup fills its background's shape to, along
  // the bar (up a vertical one), in backgroundLevelColor; -1 for none (a custom
  // widget's pill style)
  property real backgroundLevel: -1
  property color backgroundLevelColor: "transparent"

  foregroundColor: colors.text
  iconColor: colors.icon
  opacity: (root.pressed ? 0.8 : 1) * root.dim

  HoverHandler {
    id: hover
    enabled: !clickArea.enabled && !root.hitArea
  }

  MouseArea {
    id: clickArea
    parent: root.hitArea ?? root
    anchors.fill: parent
    containmentMask: root.hitArea?.mask ?? null
    enabled: (root.clickable || root.scrollable) && !root.hidden
    hoverEnabled: true
    cursorShape: root.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: root.clickable ? root.acceptedButtons : Qt.NoButton
    onClicked: mouse => root.clicked(mouse.button)
    onWheel: wheel => {
      if (root.scrollable)
        root.scrolled(wheel.angleDelta.y / 120);
      else
        wheel.accepted = false;
    }
  }
}
