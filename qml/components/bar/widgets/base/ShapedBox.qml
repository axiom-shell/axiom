pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs.components.methods

// A box in a bar's widget shape (BarShapes, drawn as BarOutlines), filling its parent: one fill
// and stroke between two caps, a Rectangle when both ends are alike and
// rounded (or square), else a path, as also for a slice of the bar's
// gradient (`fillSlice` or `strokeSlice`, BarGradient.gradientSlice); a
// stroke other than solid over it (OutlineStroke). A widget's background
// (WidgetBackground) and a Workspaces cell as a segment of the bar's run
// (CellBox) draw in it.
Item {
  id: box

  // The bar's config: its `vertical` and `radius`
  required property var bar
  required property string startCap
  required property string endCap
  property bool seamStart: false
  property bool seamEnd: false
  // Ends left open, where a merged run carries on (BarOutlines.path)
  property bool openStart: false
  property bool openEnd: false
  property color fillColor: "transparent"
  property color strokeColor: "transparent"
  property real strokeWidth: 0
  // A tab's shape (BarTabs.tab): its stroke is left open along the
  // edge it hangs from
  property var tab: null
  // solid, or the outline's own (OutlineStroke)
  property string stroke: "solid"
  property var fillSlice: null
  property var strokeSlice: null

  readonly property bool vertical: bar.vertical
  // Its stroke is a path of its own, left open somewhere (a tab's outer
  // edge, an open end)
  readonly property bool _openStroke: tab !== null || openStart || openEnd
  readonly property bool solid: stroke === "solid"
  // The fill's and a solid stroke's (one centred on the path)
  readonly property real _solidWidth: solid ? strokeWidth : 0
  readonly property real across: vertical ? width : height
  readonly property real length: vertical ? height : width
  // What it draws (BarShapes.outline)
  readonly property var _outline: BarShapes.outline({
    "length": box.length,
    "across": box.across,
    "radius": box.bar.radius,
    "startCap": box.startCap,
    "endCap": box.endCap,
    "vertical": box.vertical,
    "seamStart": box.seamStart,
    "seamEnd": box.seamEnd,
    "tab": box.tab,
    "openStart": box.openStart,
    "openEnd": box.openEnd
  })
  readonly property real rectRadius: {
    if (startCap !== endCap || seamStart || seamEnd || _openStroke || box.fillSlice !== null || box.strokeSlice !== null)
      return -1;
    switch (startCap) {
    case "round":
      return box.bar.radius;
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
    color: box.fillColor
    border.color: box.strokeColor
    border.width: box._solidWidth
  }

  Loader {
    anchors.fill: parent
    active: box.visible && box.rectRadius < 0 && box.width > 0 && box.height > 0
    sourceComponent: Shape {
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: box.fillColor
        fillGradient: box.fillSlice !== null ? fillPaint : null
        strokeColor: box._solidWidth > 0 && !box._openStroke ? box.strokeColor : "transparent"
        strokeGradient: box.strokeSlice !== null && box._solidWidth > 0 && !box._openStroke ? strokePaint : null
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
        strokeColor: box._solidWidth > 0 && box._openStroke ? box.strokeColor : "transparent"
        strokeGradient: box.strokeSlice !== null && box._solidWidth > 0 && box._openStroke ? strokePaint : null
        strokeWidth: box._solidWidth
        joinStyle: ShapePath.MiterJoin

        PathSvg {
          path: box._openStroke ? BarOutlines.path(box._outline, box._solidWidth / 2, true) : ""
        }
      }

      // Along the bar, the slices of its gradient
      ShapeSlice {
        id: fillPaint
        slice: box.fillSlice
        vertical: box.vertical
        length: box.length
      }
      ShapeSlice {
        id: strokePaint
        slice: box.strokeSlice
        vertical: box.vertical
        length: box.length
      }
    }
  }

  OutlineStroke {
    anchors.fill: parent
    visible: !box.solid && box.strokeWidth > 0 && box.strokeColor.a > 0
    stroke: box.stroke
    vertical: box.vertical
    radius: box.bar.radius
    startCap: box.startCap
    endCap: box.endCap
    seamStart: box.seamStart
    seamEnd: box.seamEnd
    openStart: box.openStart
    openEnd: box.openEnd
    tab: box.tab
    slice: box.strokeSlice
    color: box.strokeColor
    lineWidth: box.strokeWidth
  }
}
