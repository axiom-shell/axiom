pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs.components.methods

// An outlined bar widget's or workspace cell's stroke in a style other than
// solid (the bar's outlineStroke), over the box it outlines (a Rectangle
// can only draw a solid one): dashed, dotted, double (two lines of `lineWidth`
// a `lineWidth` apart) or ends (a mark at each end in its shape:
// BarShapes.marks). It lies inside the box but at a powerline seam, where
// it lies on the shared edge, as a solid outline does (BarShapes.path).
Item {
  id: root

  // dashed, dotted, double or ends
  required property string stroke
  required property bool vertical
  property real radius: 0
  property string startCap: "round"
  property string endCap: "round"
  property bool seamStart: false
  property bool seamEnd: false
  // A tab's shape (BarShapes.tab): every stroke is open along the edge it
  // hangs from
  property var tab: null
  property color color: "transparent"
  property real lineWidth: 1

  readonly property real across: vertical ? width : height
  readonly property real length: vertical ? height : width
  readonly property real _half: lineWidth / 2
  // A line square to every edge `inset` in, the caps' at a seam on it
  function _offset(inset) {
    return BarShapes.offsetPath(root.length, root.across, root.radius, root.startCap, root.endCap, root.vertical, inset, root.seamStart ? inset - root._half : inset, root.seamEnd ? inset - root._half : inset, root.tab);
  }

  Loader {
    anchors.fill: parent
    active: root.visible && root.width > 0 && root.height > 0
    sourceComponent: Shape {
      preferredRendererType: Shape.CurveRenderer

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.color
        strokeWidth: root.lineWidth
        strokeStyle: root.stroke === "dashed" || root.stroke === "dotted" ? ShapePath.DashLine : ShapePath.SolidLine
        // In line widths: dashes three long two apart, dots square ones
        // one and a half apart (the curve renderer draws nothing for a
        // zero-length dash, so a dot can't be a round cap alone)
        dashPattern: root.stroke === "dotted" ? [1, 1.5] : [3, 2]
        capStyle: root.stroke === "ends" ? ShapePath.RoundCap : ShapePath.FlatCap
        joinStyle: root.stroke === "ends" ? ShapePath.RoundJoin : ShapePath.MiterJoin

        PathSvg {
          path: {
            switch (root.stroke) {
            case "ends":
              return BarShapes.marks(root.length, root.across, root.radius, root.startCap, root.endCap, root.vertical, root._half, root.seamStart, root.seamEnd, root.tab);
            case "double":
              return root._offset(root._half);
            default:
              return BarShapes.path(root.length, root.across, root.radius, root.startCap, root.endCap, root.vertical, root._half, root.seamStart, root.seamEnd, root.tab, true);
            }
          }
        }
      }

      // A double outline's inner line, a line's width in from the outer
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.stroke === "double" ? root.color : "transparent"
        strokeWidth: root.lineWidth
        joinStyle: ShapePath.MiterJoin

        PathSvg {
          path: root.stroke === "double" ? root._offset(root._half + root.lineWidth * 2) : ""
        }
      }
    }
  }
}
