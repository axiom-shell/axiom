pragma ComponentBehavior: Bound
import QtQuick

// The shadow (SurfaceShadow) a sibling `target` casts, kept only
// outside its shape, so none shows through a translucent fill. Declared
// before the target, so it's drawn under it. It captures the target with
// room for the shadow on every side, and the effect draws exactly that
// area: an effect padding its source itself (autoPaddingEnabled) stretches
// a texture it's handed, or redraws a layer it's handed, outline and all.
// A surface whose fill the blur window draws (BlurManager) has none of its
// own to cast from: its target is then a copy of its shape, filled, kept
// off screen.
Item {
  id: root

  required property Item target
  property bool active: true
  property alias look: shadow.look
  // The shadow's colour, when a caller wants its own (the overlay page's
  // soft shadow); else the shell's, from `look`
  property alias shadowColor: shadow.shadowColor
  readonly property real reach: Math.ceil(shadow.look.shadowSize * 1.25)

  x: target.x - reach
  y: target.y - reach
  width: target.width + reach * 2
  height: target.height + reach * 2
  visible: active && shadow.shadowEnabled

  ShaderEffectSource {
    id: capture
    anchors.fill: parent
    visible: false
    sourceItem: root.active ? root.target : null
    hideSource: true
    sourceRect: Qt.rect(-root.reach, -root.reach, root.width, root.height)
  }

  SurfaceShadow {
    id: shadow
    anchors.fill: parent
    source: capture
    autoPaddingEnabled: false
    cut: true
  }
}
