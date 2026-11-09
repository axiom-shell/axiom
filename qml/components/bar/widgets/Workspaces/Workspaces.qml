pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.components.bar.widgets.base

// The workspace switcher, laid out as the Workspaces section says: a row of
// 1..count (WorkspaceStrip), or the active row or column of this monitor's
// grid with the whole grid as a popout (WorkspaceGridStrip). On a strip
// monitor either one shows the active workspace's windows in strip order. It sits on a
// background in the bar's widget style like any other widget, its cells
// (WorkspaceCell, in the same style) inset by the inner spacing within a
// box (filled, tinted or outlined). With `showBackground` off the box takes
// the bar's color (it's left clear) and the cells fill it at the widgets'
// full size. Without a box the cells sit straight on the bar, each
// underlined itself for underline.
BarWidget {
  id: root

  // A box in its own color, else clear over the bar
  readonly property bool boxed: barConfig.widgetBoxed && properties.showBackground
  // Within a colored box
  readonly property real inset: boxed ? barConfig.innerGap : 0

  // Its cells stay put while the strip after them comes and goes
  pinStart: true
  hasBackground: true
  // Its cells fill on hover, each on its own
  fillsOnHover: false
  // Its box; an underline is each cell's own
  accentField: boxed ? "backgroundColor" : ""

  implicitWidth: loader.implicitWidth + (isVertical ? 0 : inset * 2)
  implicitHeight: loader.implicitHeight + (isVertical ? inset * 2 : 0)

  Loader {
    id: loader
    anchors.centerIn: parent
    sourceComponent: CompositorManager.workspaceGrid ? gridStrip : strip
  }

  // Where its active cell sits along the bar, for an Auto active color to
  // give way to the bar's gradient there (BarWidget.barSpotOf), else null.
  // Not in a merged run: that's a strip of the gradient itself, which the
  // cell would vanish into, so it keeps its own.
  readonly property var _activeSpotOf: root.autoColors.activeColor === "accent" && root.barLength > 0 && root.barConfig.widgetGrouping !== "merged" ? root.barSpotOf : null

  Component {
    id: strip
    WorkspaceStrip {
      screen: root.screen
      hitArea: root.hitArea
      barSpotOf: root._activeSpotOf
      barConfig: root.barConfig
      properties: root.properties
      inset: root.inset
    }
  }

  Component {
    id: gridStrip
    WorkspaceGridStrip {
      screen: root.screen
      hitArea: root.hitArea
      barSpotOf: root._activeSpotOf
      barConfig: root.barConfig
      properties: root.properties
      inset: root.inset
    }
  }
}
