pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small flat button on a ListEntryRow, faint until the row is hovered
// or selected. `lit` keeps it at full strength and in the accent (the
// state it toggles is on); `danger` hovers in the error colour.
SquareIconButton {
  id: root

  required property ListEntryRow row
  property bool lit: false
  property bool danger: false

  size: Widget.height - Widget.px(6)
  iconColor: root.row.selected ? Theme.background : (root.lit ? Theme.accent : Theme.foreground)
  backgroundColor: "transparent"
  hoverColor: root.danger ? Theme.error : (root.row.selected ? Qt.darker(Theme.accent, 1.15) : Theme.backgroundAlt)
  opacity: root.lit || root.row.selected || root.row.hovered ? 1 : 0.35
}
