pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// A key in a controls hint: a keycap and what it does, e.g. [↵] open
Row {
  id: root

  property string key: ""
  property string label: ""

  spacing: Widget.spacing

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: Math.max(height, keyText.implicitWidth + Widget.spacing * 2)
    height: keyText.implicitHeight + Widget.px(4)
    radius: Widget.radius / 2
    color: Appearance.fill(Theme.backgroundAlt)
    border.color: Theme.border
    border.width: 1

    StyledText {
      id: keyText
      anchors.centerIn: parent
      text: root.key
      textColor: Theme.foregroundAlt
      textSize: Appearance.fontSizeBy(-4)
    }
  }

  StyledText {
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    textColor: Theme.foregroundInactive
    textSize: Appearance.fontSizeBy(-3)
  }
}
