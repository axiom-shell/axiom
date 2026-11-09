pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// Icon + title row at the top of a module; children go on the right
RowLayout {
  id: root

  property string icon: ""
  property string title: ""
  property color iconColor: Theme.accent
  default property alias trailing: trail.data

  Layout.fillWidth: true
  spacing: Widget.spacing

  StyledIcon {
    visible: root.icon !== ""
    text: root.icon
    textColor: root.iconColor
    textSize: Appearance.fontSizeBy(2)
  }

  StyledText {
    Layout.fillWidth: true
    text: root.title
    elide: Text.ElideRight
    font.bold: true
  }

  RowLayout {
    id: trail
    spacing: Widget.spacing / 2
  }
}
