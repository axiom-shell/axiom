pragma ComponentBehavior: Bound
import QtQuick

// A FloatingPopout box's shadow (SurfaceShadow), cast by a copy of its
// shape, so the content isn't drawn through a layer. Only what falls
// outside the box is kept, so none shows through a translucent one. Not
// OutsideShadow: its capture drops the target's own transform, and this
// copy scales with the box as it opens. Drawn in the box's own window, or
// in one over it, with the stroke, where the blur would frost it
// (BlurManager.shadowsApart).
Rectangle {
  id: root

  required property Rectangle target
  property bool shown: false

  visible: root.shown
  x: root.target.x
  y: root.target.y
  width: root.target.width
  height: root.target.height
  radius: root.target.radius
  color: "black"
  opacity: root.target.opacity
  scale: root.target.scale
  transformOrigin: root.target.transformOrigin
  layer.enabled: root.shown
  layer.effect: SurfaceShadow {
    cut: true
  }
}
