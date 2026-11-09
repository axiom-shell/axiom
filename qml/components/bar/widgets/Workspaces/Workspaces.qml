pragma ComponentBehavior: Bound
import QtQuick

import qs.services.compositor
import qs.components.bar.widgets.base
import qs.components.bar.look

// The workspace switcher, laid out as the Workspaces section says: a row of
// 1..count (WorkspaceStrip), or the active row or column of this monitor's
// grid with the whole grid as a popout (WorkspaceGridStrip). On a strip
// monitor either one shows the active workspace's windows in strip order. It sits on a
// background in the bar's widget style like any other widget, its cells
// (WorkspaceCell, in the same style) inset by the inner spacing within a
// box (filled, tinted or outlined). With `showBackground` off there's no
// box: its cells are segments of the bar's run at the widgets' full size
// (`segmented`), each in the bar's widget shape, chaining on in a powerline
// and sitting in a merged run as widgets do (BarCells.cellShape). Without
// a box the cells sit straight on the bar, each underlined itself for
// underline. A head (`lead`: an icon, or the active workspace's label as
// its cell shows it) before the cells, in their box, is its icon part on a
// split bar (SplitLead); with no box (`segmented`) it has none.
BarWidget {
  id: root

  // A box in its own color, else clear over the bar
  readonly property bool boxed: barConfig.look.traits.boxed && properties.showBackground
  // Within a colored box
  readonly property real inset: boxed ? barConfig.innerGap : 0

  // Its cells stay put while the strip after them comes and goes
  pinStart: true
  hasBackground: true
  // Its cells across the bar, in from its box by the inset, which its
  // background's caps keep clear of (a cell's thickness, CellLook's)
  contentAcross: barConfig.thickness - inset * 2
  // No box: its cells are the bar's segments
  segmented: barConfig.look.traits.boxed && !properties.showBackground
  // Its place in the bar's run for its cells (alone where it has none: a
  // preview), or null with a box
  readonly property var _run: segmented ? (runPlace ?? {
      "sized": null,
      "drawn": null,
      "reachStart": 0,
      "reachEnd": 0,
      "tabLimits": [null, null]
    }) : null
  // How its cells draw on this bar, handed to its switcher, its rows and
  // strips: inside its box, in its place in the bar's run
  readonly property CellLook _cellLook: CellLook {
    barConfig: root.barConfig
    properties: root.properties
    onBar: root.hitArea !== null
    run: root._run
    inset: root.inset
  }
  // Its cells fill on hover, each on its own
  fillsOnHover: false
  // Its box; an underline is each cell's own
  accentField: boxed ? "backgroundColor" : ""

  // The head's room before the cells: in from the box's edge by the bar's
  // padding, as an icon is, rather than the cells' inset
  readonly property real _leadRoom: lead.shown ? barConfig.innerPadding - inset + lead.length : 0
  readonly property real _cellsLength: isVertical ? loader.implicitHeight : loader.implicitWidth
  // Where the cells' room starts (the inset before them), centred in the
  // widget with the head's
  readonly property real _start: Math.round(((isVertical ? height : width) - _leadRoom - _cellsLength) / 2)

  implicitWidth: loader.implicitWidth + (isVertical ? 0 : inset * 2 + _leadRoom)
  implicitHeight: loader.implicitHeight + (isVertical ? inset * 2 + _leadRoom : 0)

  splits: lead.splits
  splitAt: lead.splitAt
  splitPart: lead.splitPart

  // The monitor's active workspace, as its cell shows it (no app icons):
  // a label's icon or text, the compositor's name, else its number
  readonly property var _monitor: CompositorManager.outputFor(root.screen)
  readonly property var _active: root.properties.lead === "active" ? activeContents.of(root._monitor?.activeWorkspaceId ?? -1, "", false) : null
  CellContents {
    id: activeContents
    barConfig: root.barConfig
    properties: root.properties
    base: CompositorManager.workspaceBase(root._monitor?.name ?? "")
    thickness: root.barConfig.thickness
    restLength: root.barConfig.thickness
  }

  SplitLead {
    id: lead
    barConfig: root.barConfig
    start: root._start - root.inset + root.barConfig.innerPadding
    icon: root.segmented ? "" : root.properties.lead === "icon" ? root.properties.leadIcon : root._active && root._active.kind === "text" && !root._active.plain ? root._active.text : ""
    text: root.segmented || !root._active || icon !== "" ? "" : root._active.kind === "labels" ? String(root._active.number) : root._active.text
    iconColor: root.colors.icon
  }

  Loader {
    id: loader
    x: root.isVertical ? Math.round((root.width - width) / 2) : root._start + root._leadRoom
    y: root.isVertical ? root._start + root._leadRoom : Math.round((root.height - height) / 2)
    sourceComponent: CompositorManager.workspaceGrid ? gridStrip : strip
  }

  // Where its active cell sits along the bar, for an Auto active color to
  // give way to the bar's gradient there (BarWidget.barSpotOf), else null.
  // Not in a merged run: that's a strip of the gradient itself, which the
  // cell would vanish into, so it keeps its own.
  readonly property var _activeSpotOf: root.autoColors.activeColor === "accent" && root.barLength > 0 && root.barConfig.look.grouping !== "merged" ? root.barSpotOf : null

  Component {
    id: strip
    WorkspaceStrip {
      screen: root.screen
      hitArea: root.hitArea
      barSpotOf: root._activeSpotOf
      barConfig: root.barConfig
      properties: root.properties
      cellLook: root._cellLook
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
      cellLook: root._cellLook
    }
  }
}
