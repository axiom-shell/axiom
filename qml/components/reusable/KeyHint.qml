pragma ComponentBehavior: Bound
import QtQuick

import qs.config

// A key in a controls hint: a keycap and what it does, e.g. [↵] open
Row {
  id: root

  property string key: ""
  property string label: ""

  spacing: Widget.spacing

  Surface {
    anchors.verticalCenter: parent.verticalCenter
    tone: "sunken"
    outlined: true
    width: Math.max(height, Math.ceil(keyText.implicitWidth) + Widget.spacing * 2)
    height: Math.max(Widget.smallHeight, Math.ceil(keyText.implicitHeight) + Widget.px(2))
    radius: Style.radiusInner

    StyledLabel {
      id: keyText
      anchors.centerIn: parent
      role: "micro"
      overflow: "none"
      tone: "muted"
      text: root.key
    }
  }

  StyledLabel {
    anchors.verticalCenter: parent.verticalCenter
    role: "caption"
    tone: "faint"
    text: root.label
  }
}
