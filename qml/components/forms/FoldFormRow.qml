pragma ComponentBehavior: Bound
import QtQuick
import qs.components.reusable

// A card's fold row for an editor's extra options: a FoldHeader in a FormRow,
// the look of the settings card's own fold row (SettingsField's `foldHeader`,
// which is itself a FormRow, so can't be reused here). The host owns `open` (a
// plain property); the rows behind it are its siblings with `shown: open && …`,
// each keeping its own tree level (a fold is not a dependency: no indent).
FormRow {
  id: root

  property string title
  // Whether the rows behind it show
  property bool open: false
  // An unsaved edit behind it (the dot, while shut)
  property bool marked: false

  signal toggled

  tinted: false
  hoverable: false
  bodyHeight: header.implicitHeight

  FoldHeader {
    id: header
    width: parent.width
    title: root.title
    collapsed: !root.open
    marked: root.marked
    onToggled: root.toggled()
  }
}
