pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods
import qs.components.reusable

// What the bar's look draws for a box in its colors, filling its parent:
// the box (`boxed`: a fill and the outline's stroke, a ShapedBox) and the
// look's line (StyleLine). A widget's background (WidgetBackground) and a
// Workspaces cell (WorkspaceCell, ActiveCellIndicator) both draw in it:
// only where the shape comes from differs (`outline`, and `reach`, how far
// the box reaches past its item: BarShapes.boxRect's). Its colors glide
// (`animated`).
Item {
  id: root

  required property var bar
  // Draws its box (the line is the look's: none where it has none)
  property bool boxed: true
  // ShapedBox's outline
  property var outline: ({})
  // { back, near, far } past its item (BarShapes.boxRect), or null: none
  property var reach: null
  property color fill: "transparent"
  property color stroke: "transparent"
  // The line's
  property color line: "transparent"
  property real strokeWidth: 0
  property string strokeStyle: "solid"
  // Slices of the bar's gradient (BarGradient.gradientSlice) for its
  // fill, stroke and line, else null
  property var fillSlice: null
  property var strokeSlice: null
  property var lineSlice: null
  property bool animated: true

  readonly property var _rect: BarShapes.boxRect({
    "x": 0,
    "y": 0,
    "width": root.width,
    "height": root.height
  }, root.reach?.back ?? 0, root.reach?.near ?? 0, root.reach?.far ?? 0, root.bar.vertical)

  anchors.fill: parent

  // State changes (mute, a warning level) recolour smoothly
  ColorGlide on fill {
    enabled: root.animated
  }
  ColorGlide on stroke {
    enabled: root.animated
  }
  ColorGlide on line {
    enabled: root.animated
  }

  ShapedBox {
    visible: root.boxed
    anchors.fill: undefined
    x: root._rect.x
    y: root._rect.y
    width: root._rect.width
    height: root._rect.height
    bar: root.bar
    outline: root.outline
    paint: ({
        "fill": root.fill,
        "stroke": root.stroke,
        "strokeWidth": root.strokeWidth,
        "strokeStyle": root.strokeStyle,
        "fillSlice": root.fillSlice,
        "strokeSlice": root.strokeSlice
      })
  }

  StyleLine {
    line: root.bar.look.line
    vertical: root.bar.vertical
    color: root.line
    slice: root.lineSlice
  }
}
