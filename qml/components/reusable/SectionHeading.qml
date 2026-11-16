pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A section's title in the text colour (hidden when empty), with an optional
// accent `icon` before it and a `rule` (a separator) filling the rest of its
// line, and an optional muted description under it, folded to three lines
// behind More (FieldGroup, the theme list, search results)
ColumnLayout {
  id: root

  property string title: ""
  property string description: ""
  // A Material Symbols name, in the accent before the title; none while empty
  property string icon: ""
  // A separator fills the title's line after it
  property bool rule: false

  Layout.fillWidth: true
  spacing: 2

  RowLayout {
    Layout.fillWidth: true
    visible: root.title !== ""
    spacing: Widget.spacing

    StyledIcon {
      visible: root.icon !== ""
      text: root.icon
      size: "md"
      tone: "accent"
    }

    StyledText {
      role: "title"
      overflow: "wrap"
      Layout.fillWidth: !root.rule
      text: root.title
    }

    StyledSeparator {
      visible: root.rule
      Layout.fillWidth: true
      Layout.alignment: Qt.AlignVCenter
    }
  }

  ClampedText {
    text: root.description
  }
}
