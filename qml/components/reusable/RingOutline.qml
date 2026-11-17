pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A ring round its parent's box: an outer line in `color`, then a line in the
// page colour inside it, so it reads on any fill (an accent one too). The OSD
// tiles' "just changed" and preview outlines, and the level bar's. Fades or
// hides as its host sets `opacity` / `visible`.
Rectangle {
  id: root

  // -- Public API --
  // The outer line
  property color ringColor: Style.accent
  // The inner page-colour line's width, 0 for none
  property real gap: Widget.px(2)

  // -- Implementation --
  anchors.fill: parent
  radius: Style.radius
  color: "transparent"
  border.width: Widget.px(2)
  border.color: root.ringColor

  Rectangle {
    visible: root.gap > 0
    anchors.fill: parent
    anchors.margins: Widget.px(2)
    radius: Math.max(0, Style.radius - Widget.px(2))
    color: "transparent"
    border.width: root.gap
    border.color: Style.surfacePage
  }
}
