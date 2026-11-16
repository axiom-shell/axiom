pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.reusable

// One SegmentButton tab per entry in a wrapping row: `count` tabs, the
// `current` one active, `labelAt(i)` / `iconAt(i)` giving each one's text and
// glyph; `picked(i)` when one is clicked. The entry list cards (EntryListCard,
// CalendarAccountsCard) use it.
Flow {
  id: root

  property int count: 0
  property int current: 0
  property var labelAt: i => ""
  property var iconAt: i => ""

  signal picked(int index)

  spacing: Widget.spacing / 2

  Repeater {
    model: root.count

    delegate: SegmentButton {
      id: tab
      required property int index

      text: root.labelAt(tab.index)
      iconText: root.iconAt(tab.index)
      active: tab.index === root.current
      onClicked: root.picked(tab.index)
    }
  }
}
