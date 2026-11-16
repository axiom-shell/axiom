pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A list that scrolls inside once it passes `maxHeight`, padded by the focus
// ring so a row's ring isn't cut (ToolPane's pinned list, the layouts editor's lists).
Item {
  id: root

  property real maxHeight
  default property alias content: column.data
  readonly property alias contentHeight: column.implicitHeight
  // The list is taller than the room it has: it scrolls
  readonly property bool cut: column.implicitHeight > root.height

  implicitHeight: Math.min(column.implicitHeight, root.maxHeight)

  StyledScrollView {
    // Out by the ring's width on every side, and padded by it, so a
    // row's focus ring isn't cut at the list's edges (`bleed` for the
    // sides: the Flickable then doesn't clip at its padding)
    anchors.fill: parent
    anchors.margins: -Style.focusWidth
    contentPadding: 0
    bleed: Style.focusWidth
    topPadding: Style.focusWidth
    bottomPadding: Style.focusWidth
    // A bar only while the capped list overflows
    showScrollBar: root.cut

    ColumnLayout {
      id: column
      width: parent?.width ?? 0
      spacing: Widget.spacing / 2
    }
  }
}
