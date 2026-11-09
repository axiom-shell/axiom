pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import qs.config

/**
 * Concave "inverted corner" piece: fills the corner (isLeft/isTop) of
 * its box with fillColor up to a quarter-circle, and strokes the two box
 * edges leading away from that corner joined by the arc.
 *
 * The stroke is centred half a stroke width inside the box, so its full
 * width is visible and lines up pixel-exactly with a Rectangle-drawn
 * stroke along the same edges (e.g. BorderPanel's inner line).
 */
Item {
  id: root
  property int borderRadius: Appearance.borderRadius
  property color fillColor: Theme.background
  property color strokeColor: Theme.foreground
  property int strokeWidth: Appearance.borderWidth

  property bool isLeft: true
  property bool isTop: true

  anchors.fill: parent

  // Corner-local coordinates: (0, 0) is the filled corner, u runs along
  // the horizontal edge, v along the vertical one.
  readonly property real half: strokeWidth / 2
  readonly property real arcRadius: Math.max(0, borderRadius - half)
  // Mirroring once (left/right or top/bottom) flips the arc's sweep
  readonly property int sweep: isTop === isLeft ? PathArc.Counterclockwise : PathArc.Clockwise

  function px(u) {
    return isLeft ? u : width - u;
  }
  function py(v) {
    return isTop ? v : height - v;
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    // --- FILL ---
    ShapePath {
      fillColor: Appearance.fill(root.fillColor)
      strokeColor: "transparent"
      strokeWidth: 0

      startX: root.px(0)
      startY: root.py(0)

      PathLine {
        x: root.px(root.half + root.arcRadius)
        y: root.py(0)
      }
      PathLine {
        x: root.px(root.half + root.arcRadius)
        y: root.py(root.half)
      }
      PathArc {
        x: root.px(root.half)
        y: root.py(root.half + root.arcRadius)
        radiusX: root.arcRadius
        radiusY: root.arcRadius
        direction: root.sweep
      }
      PathLine {
        x: root.px(0)
        y: root.py(root.half + root.arcRadius)
      }
      PathLine {
        x: root.px(0)
        y: root.py(0)
      }
    }

    // --- STROKE ---
    ShapePath {
      fillColor: "transparent"
      strokeColor: root.strokeColor
      strokeWidth: root.strokeWidth
      capStyle: ShapePath.FlatCap
      joinStyle: ShapePath.MiterJoin

      startX: root.px(root.width)
      startY: root.py(root.half)

      PathLine {
        x: root.px(root.half + root.arcRadius)
        y: root.py(root.half)
      }
      PathArc {
        x: root.px(root.half)
        y: root.py(root.half + root.arcRadius)
        radiusX: root.arcRadius
        radiusY: root.arcRadius
        direction: root.sweep
      }
      PathLine {
        x: root.px(root.half)
        y: root.py(root.height)
      }
    }
  }
}
