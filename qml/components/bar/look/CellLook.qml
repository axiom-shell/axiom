pragma ComponentBehavior: Bound
import QtQuick

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
  // The widget's options: solidBoxes, labels, showAppIcons, spacing
  property var properties: ({})
  // Drawn in its widget on the bar, not a popout: in a merged run on a
  // merged bar
  property bool onBar: false
  // The widget's place in the bar's run, its cells being segments of it
  // (Workspaces' `_run`), else null
  property var run: null
  // The bar's inner side, where its cells' tooltips show
  readonly property int innerEdges: BarCells.innerEdges(barConfig)
  // What the widget's text sits on (its colors' `textBack`), which a
  // cell's content reads on; null: the bar (a popout's)
  property var under: null
  // Room kept to the widget's box across, and a cell's thickness inside it
  property real inset: 0
  property real thickness: barConfig ? barConfig.thickness - inset * 2 : 0

  // Every cell a filled box (`solidBoxes`)
  readonly property bool solid: properties?.solidBoxes ?? false
  // The widget's colors resolved (BarsConfig.workspaceColors): activeColor,
  // occupiedColor, urgentColor, emptyColor, textColor, hoverColor (null: Auto)
  readonly property var colors: BarsConfig.workspaceColors(properties)
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

  // A workspace's cell colors by its state (BarsConfig.workspaceCellColors)
  // in the widget's `colors`, with `cell`'s hovered, spot, pulse (as
  // BarsConfig.cellColors takes them)
  function workspaceColorsOf(active, occupied, urgent, cell) {
    return BarsConfig.workspaceCellColors(root.barConfig, Object.assign({}, root.colors, {
      "solidBoxes": root.solid
    }), active, occupied, urgent, Object.assign({}, cell, {
      "onBar": root.onBar,
      "under": root.under,
      "hover": root.colors.hoverColor,
      // a spot is handed only where the active color is Auto and gives way
      // (CellLook.spotOf, Workspaces._activeSpotOf)
      "auto": (cell?.spot ?? -1) >= 0
    }));
  }

  // Where a point of an item of the widget sits along the bar (its
  // BarWidget.barSpotOf), set only where its active color is Auto and gives
  // way to the bar's gradient (Workspaces._activeSpotOf); null: none (a popout)
  property var spotOf: null

  // Where `along` of `item` sits along the bar, or -1. `moved` is unused:
  // callers pass their place so a binding re-reads when they move (mapping
  // isn't a binding)
  function spotAt(item, along, moved) {
    return root.spotOf ? root.spotOf(item, along) : -1;
  }

  // A cell's slice of the bar's gradient from `from` to `to` along `item`,
  // for the part `look.gradient` names: in the bar's run any part, else only
  // a line (an underline follows the gradient as a widget's does); else null
  function sliceOf(look, item, from, to, moved) {
    const part = look?.gradient ?? null;
    if (part === null || !root.spotOf || !(root.run || part.part === "indicator"))
      return null;
    return BarGradient.gradientSlice(root.barConfig.palette.gradientStops, root.spotOf(item, from), root.spotOf(item, to), part.alpha);
  }

  // `look` with its box, outline and line cleared (the active cell's box at
  // rest under the sliding indicator), each its own color at no alpha so it
  // fades from it
  function cleared(look) {
    return Object.assign({}, look, {
      "fill": BarWidgetStyle.faded(look.fill, 0),
      "stroke": BarWidgetStyle.faded(look.stroke, 0),
      "indicator": BarWidgetStyle.faded(look.indicator, 0)
    });
  }

  // The active color as a line at `along` of `item` (the one strip box's
  // focus mark): the gradient's there where it gives way, else its own; a
  // line, never nudged or overridden
  function activeAt(item, along, moved) {
    return BarWidgetStyle.fieldColor(root.barConfig.palette, root.spotAt(item, along), root.colors.activeColor, true, "");
  }
}
