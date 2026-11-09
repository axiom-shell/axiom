pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

import qs.components.methods

// An outlined bar widget's or workspace cell's stroke in a style other than
// solid (the look's outline stroke), over the box it outlines (ShapedBox: a
// Rectangle can only draw a solid one): dashed, dotted, double (two lines
// of `lineWidth` a `lineWidth` apart) or ends (a mark at each end in its
// shape: BarOutlines.marks). Dashes and dots run along
// BarOutlines.dashPath, halves from the middle of each side out, a dash
// centred where they start, so both ends match; a flared tab's fillets are
// solid (BarOutlines.fillets). It lies inside the box but at a powerline
// seam, where it lies on the shared edge, as a solid outline does
// (BarOutlines.path).
Item {
  id: root

  // dashed, dotted, double or ends
  required property string stroke
  // What it outlines, at its own size (BarShapes.outline): on a tab, every
  // stroke is open along the edge it hangs from
  required property var outline
  property color color: "transparent"
  // Its slice of the bar's gradient in place of `color`
  // (BarGradient.gradientSlice), or null
  property var slice: null
  property real lineWidth: 1

  readonly property bool _vertical: outline.vertical
  readonly property real _length: outline.length
  readonly property var _tab: outline.tab
  readonly property real _half: lineWidth / 2
  readonly property bool _dashed: stroke === "dashed" || stroke === "dotted"
  // A line square to every edge `inset` in, the caps' at a seam on it
  function _offset(inset) {
    return BarOutlines.offsetPath(root.outline, inset, root.outline.seamStart ? inset - root._half : inset, root.outline.seamEnd ? inset - root._half : inset);
  }

  Loader {
    anchors.fill: parent
    active: root.visible && root.width > 0 && root.height > 0
    sourceComponent: Shape {
      preferredRendererType: Shape.CurveRenderer

      ShapeSlice {
        id: strokePaint
        slice: root.slice
        vertical: root._vertical
        length: root._length
      }

      ShapePath {
        fillColor: "transparent"
        strokeColor: root.color
        strokeGradient: root.slice !== null ? strokePaint : null
        strokeWidth: root.lineWidth
        strokeStyle: root._dashed ? ShapePath.DashLine : ShapePath.SolidLine
        // In line widths: dashes three long two apart, dots square ones
        // one and a half apart (the curve renderer draws nothing for a
        // zero-length dash, so a dot can't be a round cap alone). Each
        // part of dashPath starts half a dash in, so two halves meeting
        // at their start make one dash centred there.
        dashPattern: root.stroke === "dotted" ? [1, 1.5] : [3, 2]
        dashOffset: root.stroke === "dotted" ? 0.5 : 1.5
        capStyle: root.stroke === "ends" ? ShapePath.RoundCap : ShapePath.FlatCap
        joinStyle: root.stroke === "ends" ? ShapePath.RoundJoin : ShapePath.MiterJoin

        PathSvg {
          path: {
            switch (root.stroke) {
            case "ends":
              return BarOutlines.marks(root.outline, root._half);
            case "double":
              return root._offset(root._half);
            default:
              return BarOutlines.dashPath(root.outline, root._half);
            }
          }
        }
      }

      // A dashed or dotted flared tab's fillets, solid
      ShapePath {
        fillColor: "transparent"
        strokeColor: root._dashed && root._tab ? root.color : "transparent"
        strokeGradient: root.slice !== null && root._dashed && root._tab ? strokePaint : null
        strokeWidth: root.lineWidth
        capStyle: ShapePath.FlatCap

        PathSvg {
          path: root._dashed && root._tab ? BarOutlines.fillets(root.outline, root._half) : ""
        }
      }

      // A double outline's inner line, a line's width in from the outer
      ShapePath {
        fillColor: "transparent"
        strokeColor: root.stroke === "double" ? root.color : "transparent"
        strokeGradient: root.slice !== null && root.stroke === "double" ? strokePaint : null
        strokeWidth: root.lineWidth
        joinStyle: ShapePath.MiterJoin

        PathSvg {
          path: root.stroke === "double" ? root._offset(root._half + root.lineWidth * 2) : ""
        }
      }
    }
  }
}
