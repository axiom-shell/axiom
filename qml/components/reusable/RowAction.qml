pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A small flat button on a ListEntryRow, dimmed until the row shows its
// actions (hovered, focused or selected). `lit` keeps it shown in the
// primary kind (the state it toggles is on); `danger` hovers in the error
// container.
StyledIconButton {
  id: root

  required property ListEntryRow row
  property bool lit: false
  property bool danger: false

  size: Widget.compactHeight
  kind: root.lit ? "primary" : root.danger ? "danger" : "text"
  opacity: root.lit || root.row.revealed ? 1 : 0.35 // style-exempt: the resting dimness the user chose

  // A focused action handles Tab itself, so its row never sees it
  Keys.onTabPressed: root.row._tabFrom(root, true)
  Keys.onBacktabPressed: root.row._tabFrom(root, false)

  Glide on opacity {}
}
