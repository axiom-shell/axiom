pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs.components.methods

// A box in a bar's widget shape, filling its parent: its `outline` (what
// BarShapes.outline takes beyond its size: caps, seams, open ends, a tab's
// shape, and a radius, the bar's where it leaves one out: a free-standing
// cell's own) in its `paint`. One fill and stroke between two caps: a
// Rectangle when both ends are alike and rounded (or square) and nothing
// takes a slice of the bar's gradient, else a path (BarOutlines); a stroke
// taking a gradient slice is drawn through SliceMasked; a stroke other
// than solid over it (OutlineStroke). LookBox, SplitPart, LevelFill
// and ShapeOverlay draw in it.
Item {
  id: box

  // The bar's config: its `vertical` and `radius`
  required property var bar
  // { startCap, endCap, seamStart, seamEnd, openStart, openEnd, tab,
  // radius }: what it leaves out is flat, false, null, the bar's radius
  property var outline: ({})
  // { fill, stroke, strokeWidth, strokeStyle (solid, or OutlineStroke's),
  // fillSlice, strokeSlice (BarGradient.gradientSlice) }: what it leaves
  // out is clear, 0, solid, none
  property var paint: ({})

  readonly property bool vertical: bar.vertical
  readonly property real across: vertical ? width : height
  readonly property real length: vertical ? height : width
  readonly property color _fill: paint.fill ?? "transparent"
  readonly property color _stroke: paint.stroke ?? "transparent"
  readonly property real _strokeWidth: paint.strokeWidth ?? 0
  readonly property string _strokeStyle: paint.strokeStyle ?? "solid"
  readonly property var _fillSlice: paint.fillSlice ?? null
  readonly property var _strokeSlice: paint.strokeSlice ?? null
  // What it draws (BarShapes.outline)
  readonly property var _outline: BarShapes.outline(Object.assign({}, box.outline, {
    "length": box.length,
    "across": box.across,
    "vertical": box.vertical,
    "radius": box.outline.radius ?? box.bar.radius
  }))
  // Its stroke is a path of its own, left open somewhere (a tab's outer
  // edge, an open end)
  readonly property bool _openStroke: _outline.tab !== null || _outline.openStart || _outline.openEnd
  readonly property bool solid: _strokeStyle === "solid"
  // The fill's and a solid stroke's (one centred on the path)
  readonly property real _solidWidth: solid ? _strokeWidth : 0
  readonly property real rectRadius: {
    const o = box._outline;
    if (o.startCap !== o.endCap || o.seamStart || o.seamEnd || box._openStroke || box._fillSlice !== null || box._strokeSlice !== null)
      return -1;
    switch (o.startCap) {
    case "round":
      return o.radius;
    case "capsule":
      return across / 2;
    case "flat":
      return 0;
    default:
      return -1;
    }
  }

  anchors.fill: parent

  Rectangle {
    anchors.fill: parent
    visible: box.rectRadius >= 0
    radius: Math.max(0, box.rectRadius)
    color: box._fill
    border.color: box._stroke
    border.width: box._solidWidth
  }

  Loader {
    anchors.fill: parent
    active: box.visible && box.rectRadius < 0 && box.width > 0 && box.height > 0
    sourceComponent: Shape {
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: box._fill
        fillGradient: box._fillSlice !== null ? fillPaint : null
        strokeColor: box._solidWidth > 0 && !box._openStroke && box._strokeSlice === null ? box._stroke : "transparent"
        strokeWidth: box._solidWidth
        joinStyle: ShapePath.MiterJoin

        // Inset by half the stroke, which is centred on the path
        PathSvg {
          path: BarOutlines.path(box._outline, box._solidWidth / 2, false)
        }
      }

      // A stroke left open: a tab's along its outer edge, and at an
      // open end
      ShapePath {
        fillColor: "transparent"
        strokeColor: box._solidWidth > 0 && box._openStroke && box._strokeSlice === null ? box._stroke : "transparent"
        strokeWidth: box._solidWidth
        joinStyle: ShapePath.MiterJoin

        PathSvg {
          path: box._openStroke ? BarOutlines.path(box._outline, box._solidWidth / 2, true) : ""
        }
      }

      // Along the bar, the slices of its gradient
      ShapeSlice {
        id: fillPaint
        slice: box._fillSlice
        vertical: box.vertical
        length: box.length
      }
    }
  }

  // A stroke taking a slice of the bar's gradient
  Loader {
    anchors.fill: parent
    active: box.visible && box.rectRadius < 0 && box._strokeSlice !== null && box._solidWidth > 0 && box.width > 0 && box.height > 0
    sourceComponent: SliceMasked {
      slice: box._strokeSlice
      vertical: box.vertical
      length: box.length

      Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
          fillColor: "transparent"
          strokeColor: box._solidWidth > 0 && !box._openStroke ? "white" : "transparent"
          strokeWidth: box._solidWidth
          joinStyle: ShapePath.MiterJoin

          PathSvg {
            path: BarOutlines.path(box._outline, box._solidWidth / 2, false)
          }
        }

        ShapePath {
          fillColor: "transparent"
          strokeColor: box._solidWidth > 0 && box._openStroke ? "white" : "transparent"
          strokeWidth: box._solidWidth
          joinStyle: ShapePath.MiterJoin

          PathSvg {
            path: box._openStroke ? BarOutlines.path(box._outline, box._solidWidth / 2, true) : ""
          }
        }
      }
    }
  }

  OutlineStroke {
    anchors.fill: parent
    visible: !box.solid && box._strokeWidth > 0 && box._stroke.a > 0
    stroke: box._strokeStyle
    outline: box._outline
    slice: box._strokeSlice
    color: box._stroke
    lineWidth: box._strokeWidth
  }
}
