pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The keyboard focus ring: an outline outside its parent. Bind `shown` to
// keyboard focus (`activeFocus` after a Tab or arrow key), never to mouse
// focus; only controls that take keyboard focus carry one.
Rectangle {
  id: root

  // -- Public API --
  property bool shown: false

  // -- Implementation --
  readonly property real _parentRadius: root.parent && root.parent.radius !== undefined ? root.parent.radius : 0

  visible: root.shown
  anchors.fill: parent
  anchors.margins: -Style.focusWidth
  radius: root._parentRadius + Style.focusWidth
  color: "transparent"
  border.width: Style.focusWidth
  border.color: Style.focusRing
}
