pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.components.reusable

// A settings card that folds: clicking its header (title, help text,
// chevron) emits `toggled`, and the body below animates shut while
// `collapsed`. Folded with `marked` set, it shows the unsaved-edits dot.
// The generated cards (SettingsGroupCard) and the list cards
// (EntryListCard) are built on it.
StyledContainer {
  id: root

  property string title
  // Shown only while unfolded
  property string description
  // A line above the title (the section, in search results)
  property string section
  property bool collapsed: false
  // False: the header doesn't fold it (search results)
  property bool foldable: true
  property bool marked: false
  // Beside the header, while unfolded (an Add button)
  property alias headerExtras: extras.data
  default property alias content: body.content

  signal toggled

  Layout.fillWidth: true
  implicitHeight: column.implicitHeight + Widget.padding * 2

  ColumnLayout {
    id: column
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.margins: Widget.padding
    spacing: Widget.spacing * 1.5

    RowLayout {
      Layout.fillWidth: true
      spacing: Widget.spacing

      FoldHeader {
        Layout.alignment: Qt.AlignTop
        title: root.title
        description: root.description
        section: root.section
        collapsed: root.collapsed
        foldable: root.foldable
        marked: root.marked
        onToggled: root.toggled()
      }

      // Only as wide as what's in it (a layout fills by default, which
      // took half the header from the title and chevron)
      RowLayout {
        id: extras
        visible: !root.collapsed && children.length > 0
        Layout.fillWidth: false
        Layout.alignment: Qt.AlignTop
        spacing: Widget.spacing
      }
    }

    // Between the header and the fields, while unfolded
    StyledSeparator {
      visible: !root.collapsed && body.content.length > 0
      Layout.fillWidth: true
      separatorHeight: 1
      opacity: 0.6
    }

    FoldingColumn {
      id: body
      open: !root.collapsed
      Layout.fillWidth: true
      spacing: Widget.spacing * 1.5
    }
  }
}
