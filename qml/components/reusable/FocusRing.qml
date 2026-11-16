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
  // The bottom corners square (a ring round a header band over a body)
  property bool squareBottom: false

  // -- Implementation --
  // (var: qmllint knows only Item's members)
  readonly property var _host: root.parent
  readonly property real _parentRadius: root._host && root._host.radius !== undefined ? root._host.radius : 0

  visible: root.shown
  anchors.fill: parent
  anchors.margins: -Style.focusWidth
  radius: root._parentRadius + Style.focusWidth
  bottomLeftRadius: root.squareBottom ? 0 : root.radius
  bottomRightRadius: root.squareBottom ? 0 : root.radius
  color: "transparent"
  border.width: Style.focusWidth
  border.color: Style.focusRing
}
