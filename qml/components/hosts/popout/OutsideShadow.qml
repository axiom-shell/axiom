pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes

// The shadow (SurfaceShadow) a sibling `target` casts, kept only
// outside its shape, so none shows through a translucent fill. Declared
// before the target, so it's drawn under it. It captures the target with
// room for the shadow on every side, and the effect draws exactly that
// area: an effect padding its source itself (autoPaddingEnabled) stretches
// a texture it's handed, or redraws a layer it's handed, outline and all.
// A surface whose fill the blur window draws (BlurManager) has none of its
// own to cast from: its target is then a copy of its shape, filled, kept
// off screen (`hideTarget`).
Item {
  id: root

  required property Item target
  property bool active: true
  property alias look: shadow.look
  // Rects (in the target's coordinates) it isn't cast on either: where
  // surfaces joined to the target sit over it, whose translucent fill the
  // shadow would show (and blur) through
  property var holes: []
  // Fillets it isn't cast on either, each { x, y, radius, left, top }: the
  // square at x, y (the target's coordinates) filled from its `left`/`top`
  // corner to the quarter circle round the opposite one, as a surface's
  // fillet joined to the target fills it
  property var fillets: []
  // The target is drawn for the shadow alone: captured (and kept off
  // screen) whether or not the shadow shows, while `active` (a target
  // hides itself while it isn't)
  property bool hideTarget: false
  readonly property real reach: Math.ceil(shadow.look.shadowSize * 1.25)
  readonly property bool _holed: root.holes.length > 0 || root.fillets.length > 0

  x: target.x - reach
  y: target.y - reach
  width: target.width + reach * 2
  height: target.height + reach * 2
  visible: active && (target.visible || hideTarget) && shadow.shadowEnabled

  ShaderEffectSource {
    id: capture
    anchors.fill: parent
    visible: false
    sourceItem: root.active && (root.visible || root.hideTarget) ? root.target : null
    hideSource: root.hideTarget
    sourceRect: Qt.rect(-root.reach, -root.reach, root.width, root.height)
  }

  // The target and the holes, as the cut
  Item {
    id: cutMask
    anchors.fill: parent
    visible: false
    layer.enabled: root._holed

    ShaderEffectSource {
      anchors.fill: parent
      sourceItem: root._holed ? capture.sourceItem : null
      sourceRect: capture.sourceRect
    }

    Repeater {
      model: root.holes.length

      Rectangle {
        required property int index
        readonly property rect hole: root.holes[index] ?? Qt.rect(0, 0, 0, 0)
        x: root.reach + hole.x
        y: root.reach + hole.y
        width: hole.width
        height: hole.height
        color: "black"
      }
    }

    Repeater {
      model: root.fillets.length

      Shape {
        id: fillet
        required property int index
        readonly property var spec: root.fillets[index] ?? {
          "x": 0,
          "y": 0,
          "radius": 0,
          "left": true,
          "top": true
        }
        readonly property real r: spec.radius
        x: root.reach + spec.x
        y: root.reach + spec.y
        width: r
        height: r
        preferredRendererType: Shape.CurveRenderer

        function px(u) {
          return fillet.spec.left ? u : fillet.r - u;
        }
        function py(v) {
          return fillet.spec.top ? v : fillet.r - v;
        }

        ShapePath {
          fillColor: "black"
          strokeColor: "transparent"
          strokeWidth: 0
          startX: fillet.px(0)
          startY: fillet.py(0)

          PathLine {
            x: fillet.px(fillet.r)
            y: fillet.py(0)
          }
          // Mirroring once flips the arc's sweep (as CornerPiece's)
          PathArc {
            x: fillet.px(0)
            y: fillet.py(fillet.r)
            radiusX: fillet.r
            radiusY: fillet.r
            direction: fillet.spec.left === fillet.spec.top ? PathArc.Counterclockwise : PathArc.Clockwise
          }
          PathLine {
            x: fillet.px(0)
            y: fillet.py(0)
          }
        }
      }
    }
  }

  SurfaceShadow {
    id: shadow
    anchors.fill: parent
    source: capture
    cutSource: root._holed ? cutMask : capture
    autoPaddingEnabled: false
    cut: true
  }
}
