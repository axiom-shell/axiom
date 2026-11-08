pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// Two parts side by side while it's at least `minWidth` wide, the first
// taking `share` of the room, else stacked: a list beside the selected
// entry's form (an OSD's systems and bars), a picker beside a fold (a wide
// EntryListCard). Its children are the two parts, each taking the width
// through `firstWidth` / `secondWidth`
// (`Layout.preferredWidth: split.firstWidth`), both aligned to the top.
GridLayout {
  id: root

  // Side by side from this width on
  property real minWidth: Widget.px(560)
  // The first part's share of the width, side by side
  property real share: 0.4

  readonly property bool split: root.width >= root.minWidth
  readonly property real firstWidth: root.split ? Math.floor((root.width - root.columnSpacing) * root.share) : root.width
  readonly property real secondWidth: root.split ? root.width - root.columnSpacing - root.firstWidth : root.width

  Layout.fillWidth: true
  columns: root.split ? 2 : 1
  columnSpacing: Widget.spacing * 2
  rowSpacing: Widget.spacing * 1.5
}
