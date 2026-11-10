pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

import qs.config
import qs.components.methods

// How a Workspaces widget's cells draw on its bar, worked out once for a
// switcher (WorkspaceStrip, WorkspaceGridStrip) or a popout
// (WorkspacePopoutPanel) and handed to its rows, strips and cells (the
// cell's counterpart of WidgetLook): from the bar's look and the widget's
// options (`properties`), on the bar or not (`onBar`), and its place in
// the bar's run where its cells are segments of it (`run`). Its rules are
// BarCells' (cellLook, cellLength, cellShape, cellRoom); a popout's
// barConfig comes with its payload, null until then.
QtObject {
  id: root

  required property var barConfig
  // The widget's options: solidBoxes, labels, showAppIcons, spacing,
  // hoverColor
  property var properties: ({})
  // Drawn in its widget on the bar, not a popout: in a merged run on a
  // merged bar
  property bool onBar: false
  // The widget's place in the bar's run, its cells being segments of it
  // (Workspaces' `_run`), else null
  property var run: null
  // The bar's inner side, where its cells' tooltips show (as
  // BarIconWidget.innerEdges)
  readonly property int innerEdges: barConfig?.top ? Edges.Bottom : barConfig?.bottom ? Edges.Top : barConfig?.left ? Edges.Right : Edges.Left
  // Room kept to the widget's box across, and a cell's thickness inside it
  property real inset: 0
  property real thickness: barConfig ? barConfig.thickness - inset * 2 : 0

  // Every cell a filled box (`solidBoxes`)
  readonly property bool solid: properties?.solidBoxes ?? false
  readonly property var _look: barConfig?.look ?? null
  readonly property var _flags: BarCells.cellLook(_look, solid, onBar)
  // BarCells.cellLook's
  readonly property bool boxedInRun: _flags.boxedInRun
  readonly property bool opaque: _flags.opaque
  readonly property bool boxes: _flags.boxes
  readonly property bool boxed: _flags.boxed
  readonly property bool framed: _flags.framed
  readonly property bool slides: _flags.slides
  readonly property bool clearsActive: _flags.clearsActive

  // A cell's corners (BarsConfig.cellRadius; a popout's, from the bar's
  // payload) and its length at rest (BarCells.cellLength)
  property real radius: barConfig ? BarsConfig.cellRadius(barConfig, thickness, inset) : 0
  readonly property real length: _look ? BarCells.cellLength(_look, solid, properties?.labels, properties?.showAppIcons, thickness) : thickness
  // Between cells (BarsConfig.workspaceCellSpacing), chained in a
  // powerline as segments (BarCells.cellGap), and between a row and the
  // strip after it
  readonly property real spacing: barConfig ? BarsConfig.workspaceCellSpacing(barConfig, properties?.spacing) : 0
  readonly property real gap: run ? BarCells.cellGap(_look.grouping, spacing) : spacing
  readonly property real partGap: !barConfig ? 0 : run ? BarCells.cellGap(_look.grouping, barConfig.innerGap) : barConfig.innerGap
  // A cell's box while hovered (BarsConfig.cellHoverColor)
  readonly property color hoverColor: BarsConfig.cellHoverColor(properties)
  // The tallest a workspace cell shows across (its label, or an app
  // icon), and a strip window's (its app icon): the room it keeps clear
  // of its caps (WorkspaceCells)
  readonly property real content: barConfig ? WorkspaceCells.contentSize(thickness, barConfig.fontSize, properties?.showAppIcons ?? false) : 0
  readonly property real iconContent: WorkspaceCells.iconSize(thickness)

  // Cell `cell` of the widget's `cells` chained in its run, its content
  // `content` across: its shape as a segment (BarCells.cellShape; its
  // box `opaque` or not), and the room it keeps clear of its caps
  // (cellRoom); null off the run
  function shapeOf(cell, cells, opaque, content) {
    return root.run ? BarCells.cellShape(root.barConfig, root.run, root.boxedInRun, opaque, root.gap, cell, cells, content) : null;
  }
  function roomOf(cell, cells, content) {
    return root.run ? BarCells.cellRoom(root.barConfig, root.run, root.boxedInRun, cell, cells, content) : null;
  }

  // A cell's colors (BarsConfig.cellColors) in its state's `color`, `own`
  // reading on it filled, for `state`, with `cell`'s hovered and spot
  function colorsOf(color, own, state, cell) {
    return BarsConfig.cellColors(root.barConfig, color, own, state, Object.assign({}, cell, {
      "solid": root.solid,
      "onBar": root.onBar
    }));
  }
  // A workspace's cell colors by its state (BarsConfig.workspaceCellColors)
  // in the widget's `colors` ({ activeColor, occupiedColor, urgentColor,
  // emptyColor, textColor })
  function workspaceColorsOf(colors, active, occupied, urgent, cell) {
    return BarsConfig.workspaceCellColors(root.barConfig, {
      "activeColor": colors.activeColor,
      "occupiedColor": colors.occupiedColor,
      "urgentColor": colors.urgentColor,
      "emptyColor": colors.emptyColor,
      "textColor": colors.textColor,
      "solidBoxes": root.solid
    }, active, occupied, urgent, Object.assign({}, cell, {
      "onBar": root.onBar
    }));
  }
}
