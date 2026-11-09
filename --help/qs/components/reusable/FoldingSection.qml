pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A FoldHeader over a FoldingColumn: clicking the heading emits
// `toggled`, and the body folds shut while `collapsed`.
// FoldingCard's fold without the card, for sections inside one (the theme
// list's groups).
ColumnLayout {
  id: root

  property string title
  // Shown only while unfolded
  property string description
  property bool collapsed: false
  property alias bodySpacing: body.spacing
  default property alias content: body.content

  signal toggled

  Layout.fillWidth: true
  spacing: Widget.spacing

  FoldHeader {
    title: root.title
    description: root.description
    collapsed: root.collapsed
    onToggled: root.toggled()
  }

  FoldingColumn {
    id: body
    open: !root.collapsed
    Layout.fillWidth: true
    spacing: Widget.spacing
  }
}
