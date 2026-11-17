pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A list that scrolls inside once it passes `maxHeight`, padded by the focus
// ring so a row's ring isn't cut (ToolPane's pinned list, the layouts editor's
// lists). `maxHeight` is `maxShare` of the height of `shareOf`, a box its host
// sizes, unless a host sets it; with neither it takes its content height. Never
// the list's own layout parent as a default: a content-sized column's height
// would follow the list's, which follows the cap, a loop.
Item {
  id: root

  // The part of `shareOf`'s height it takes before it scrolls
  property real maxShare: 0.4
  // A box its host sizes (never this list's own layout)
  property Item shareOf: null
  property real maxHeight: root.shareOf ? Math.round(root.shareOf.height * root.maxShare) : Infinity
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
