pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The hover, press and drag tint over a control's base, under its content:
// declare it before the content. Fills its parent and rounds as its parent
// (an inset use sets `radius`; a parent with no radius gets Style.radiusInner).
// A settings row's `bleed` extends it past the parent's sides: the parent must
// not clip.
Rectangle {
  id: root

  // -- Public API --
  property bool hovered: false
  property bool pressed: false
  property bool dragged: false
  // On an accent or other solid fill: the on-fill tints
  property bool onAccent: false
  // How far it reaches past the parent on the left and right
  property real bleed: 0

  // -- Implementation --
  anchors.fill: parent
  anchors.leftMargin: -root.bleed
  anchors.rightMargin: -root.bleed
  readonly property var _host: root.parent
  radius: root._host && root._host.radius !== undefined ? root._host.radius : Style.radiusInner
  // The rest colour is the hover colour at alpha 0, so the glide never passes
  // through transparent black
  color: {
    if (root.onAccent)
      return root.pressed ? Style.stateOnAccentPressed : root.hovered ? Style.stateOnAccentHover : Style.stateOnAccentRest;
    return root.pressed ? Style.statePressed : root.dragged ? Style.stateDrag : root.hovered ? Style.stateHover : Style.stateRest;
  }

  ColorGlide on color {}
}
