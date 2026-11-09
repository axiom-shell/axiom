pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// One key (or modifier) of a keybind, drawn as a small keycap
Rectangle {
  id: root

  property string text
  // Lower, for the reference's compact density
  property bool compact: false

  implicitHeight: Math.round(Widget.height * (root.compact ? 0.62 : 0.75))
  implicitWidth: Math.max(implicitHeight, content.implicitWidth + Widget.padding)
  radius: Widget.radius / 2
  color: Theme.backgroundHighlight

  StyledLabel {
    id: content
    anchors.centerIn: parent
    text: root.text
    textSize: Appearance.fontSize - (root.compact ? 2 : 1)
  }
}
