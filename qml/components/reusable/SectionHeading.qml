pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// A section's title in the text colour (hidden when empty), with an optional muted description under
// it, folded to three lines behind More (FieldGroup, the theme list)
ColumnLayout {
  id: root

  property string title: ""
  property string description: ""

  Layout.fillWidth: true
  spacing: 2

  StyledText {
    role: "title"
    overflow: "wrap"
    visible: root.title !== ""
    Layout.fillWidth: true
    text: root.title
  }

  ClampedText {
    text: root.description
  }
}
