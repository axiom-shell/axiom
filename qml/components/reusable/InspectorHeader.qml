pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// The top of an editor's inspector (bar widget, overlay module or cell):
// the thing's icon in a well (accent-filled when `filled`), its name and
// where it is, then its actions (children), over a faint divider
ColumnLayout {
  id: root

  property string icon
  property bool filled: true
  property string title
  property string subtitle
  default property alias actions: row.data

  Layout.fillWidth: true
  spacing: Widget.spacing

  RowLayout {
    id: row
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height + Widget.padding
    spacing: Widget.spacing

    Rectangle {
      Layout.preferredWidth: Widget.height + Widget.px(4)
      Layout.preferredHeight: Widget.height + Widget.px(4)
      radius: Widget.radius
      color: root.filled ? Theme.accent : Theme.backgroundAlt

      StyledIcon {
        anchors.centerIn: parent
        text: root.icon
        textColor: root.filled ? Theme.background : Theme.accent
        textSize: Appearance.fontSizeBy(4)
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      StyledText {
        text: root.title
        textSize: Appearance.fontSizeBy(4)
        font.bold: true
        elide: Text.ElideRight
        Layout.fillWidth: true
      }

      StyledText {
        text: root.subtitle
        opacity: 0.6
        textSize: Appearance.fontSizeBy(-2)
        elide: Text.ElideRight
        Layout.fillWidth: true
      }
    }
  }

  StyledSeparator {
    Layout.fillWidth: true
    opacity: 0.3
  }
}
