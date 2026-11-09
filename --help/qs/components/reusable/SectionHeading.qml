pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A section's title in the accent, with an optional muted description under
// it, folded to three lines behind More (FieldGroup, the theme list)
ColumnLayout {
  id: root

  property string title: ""
  property string description: ""

  Layout.fillWidth: true
  spacing: 2

  StyledText {
    wrapMode: Text.WordWrap
    Layout.fillWidth: true
    text: root.title
    textColor: Theme.accent
    textSize: Appearance.fontSizeBy(1)
    font.bold: true
  }

  ClampedText {
    text: root.description
    textOpacity: 0.7
  }
}
