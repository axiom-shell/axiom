pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small flat button on a ListEntryRow, hidden until the row shows its
// actions (hovered, focused or selected). `lit` keeps it shown in the
// primary kind (the state it toggles is on); `danger` hovers in the error
// container.
SquareIconButton {
  id: root

  required property ListEntryRow row
  property bool lit: false
  property bool danger: false

  size: Widget.height - Widget.px(6)
  kind: root.lit ? "primary" : root.danger ? "danger" : "text"
  opacity: root.lit || root.row.revealed ? 1 : 0

  Glide on opacity {}
}
