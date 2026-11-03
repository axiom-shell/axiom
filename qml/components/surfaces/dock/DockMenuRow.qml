pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// A clickable row in a dock app's menu: an icon and a label
Rectangle {
  id: root

  property string icon: ""
  property string text: ""
  // Drawn in the error color on hover (Close)
  property bool danger: false

  signal clicked

  implicitWidth: row.implicitWidth + Widget.spacing * 2
  implicitHeight: Math.max(label.implicitHeight, glyph.implicitHeight) + Widget.spacing
  radius: Widget.radius / 2
  color: area.containsMouse ? (root.danger ? Theme.error : Theme.backgroundHighlight) : "transparent"

  RowLayout {
    id: row
    anchors.fill: parent
    anchors.leftMargin: Widget.spacing
    anchors.rightMargin: Widget.spacing
    spacing: Widget.spacing

    StyledIcon {
      id: glyph
      text: root.icon
      textColor: area.containsMouse && root.danger ? Theme.background : Theme.foreground
    }

    StyledText {
      id: label
      Layout.fillWidth: true
      Layout.maximumWidth: Widget.px(300)
      text: root.text
      textColor: area.containsMouse && root.danger ? Theme.background : Theme.foreground
      elide: Text.ElideRight
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
