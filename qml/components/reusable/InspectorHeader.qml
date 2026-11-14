pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// The top of an editor's inspector (bar widget, overlay module or cell):
// the thing's icon in a well (accent-filled when `filled`), its name and
// where it is, then its actions (children); under them, while
// `showsLinks`, a wrapping row of links to where related things are set
// (`links`), all over a faint divider
ColumnLayout {
  id: root

  property string icon
  property bool filled: true
  property string title
  property string subtitle
  default property alias actions: row.data
  property alias links: linkRow.data
  // Set by the host, from whether any link leads anywhere (not from the
  // links' `visible`, false while this row is hidden)
  property bool showsLinks: false

  Layout.fillWidth: true
  spacing: Widget.spacing

  RowLayout {
    id: row
    Layout.fillWidth: true
    Layout.preferredHeight: Widget.height + Widget.padding
    spacing: Widget.spacing

    Surface {
      Layout.preferredWidth: Widget.height + Widget.px(4)
      Layout.preferredHeight: Widget.height + Widget.px(4)
      tone: root.filled ? "accentContainer" : "highest"

      StyledIcon {
        anchors.centerIn: parent
        text: root.icon
        size: "md"
        tone: root.filled ? "text" : "accent"
      }
    }

    ColumnLayout {
      Layout.fillWidth: true
      spacing: 0

      StyledLabel {
        text: root.title
        role: "title"
        overflow: "line"
        Layout.fillWidth: true
      }

      StyledLabel {
        text: root.subtitle
        role: "caption"
        tone: "muted"
        overflow: "line"
        Layout.fillWidth: true
      }
    }
  }

  Flow {
    id: linkRow
    visible: root.showsLinks
    Layout.fillWidth: true
    spacing: Widget.spacing * 2
  }

  StyledSeparator {
    Layout.fillWidth: true
  }
}
