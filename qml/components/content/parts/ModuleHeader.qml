pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// Icon + title row at the top of a module; children go on the right at their own width, the title
// eliding first. A trailing label caps itself: Layout.maximumWidth: Widget.textPx(160), overflow: "line"
RowLayout {
  id: root

  property string icon: ""
  property string title: ""
  property color iconColor: Style.accent
  default property alias trailing: trail.data

  Layout.fillWidth: true
  spacing: Widget.spacing

  StyledIcon {
    visible: root.icon !== ""
    text: root.icon
    size: "md"
    textColor: root.iconColor
  }

  StyledLabel {
    Layout.fillWidth: true
    role: "title"
    text: root.title
  }

  RowLayout {
    id: trail
    spacing: Widget.spacing / 2
  }
}
