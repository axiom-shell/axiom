pragma ComponentBehavior: Bound
import QtQuick

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
  // The pointer is over it (an edge menu this opened stays open meanwhile)
  readonly property bool hovered: clickArea.containsMouse

  signal clicked(int button)
  signal scrolled(real steps)

  isVertical: barConfig.vertical
  crossSize: barConfig.widgetSize
  // Sized by the bar, not the Widget section (that's for panels)
  padding: barConfig.widgetPadding
  radius: barConfig.radius
  fontSize: barConfig.fontSize
  // The icon's gap to its label (6 px at the default inner spacing of 4)
  spacing: barConfig.widgetSpacing * 1.5
  // Its color for its state, and what it draws in on this bar
  property color accentColor: Theme.resolveColor(properties.backgroundColor)
  readonly property var colors: Bar.widgetColors(barConfig, accentColor, properties.foregroundColor)
  // Whether its WidgetGroup draws a background under it, and an outline
  // in its shape while it's hovered
  property bool hasBackground: !hidden
  property bool hoverOutline: false

  showBackground: false
  foregroundColor: colors.text
  iconColor: colors.icon
  opacity: (root.pressed ? 0.8 : 1) * root.dim

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
