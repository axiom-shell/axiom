pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// The line showing where a drop lands: Widget.px(2) thick, accent. The
// caller places and sizes its length; `vertical` marks the thickness as width.
Rectangle {
  property bool vertical: false
  readonly property real thickness: Widget.px(2)

  implicitWidth: vertical ? thickness : 0
  implicitHeight: vertical ? 0 : thickness
  width: implicitWidth
  height: implicitHeight
  radius: thickness / 2
  color: Style.accent
}
