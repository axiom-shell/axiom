pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// One SegmentButton tab per entry in a wrapping row: `count` tabs, the
// `current` one active, `labelAt(i)` / `iconAt(i)` giving each one's text and
// glyph; `picked(i)` when one is clicked, `menuRequested(i, tab, x, y)` on a
// right click (x and y in the tab). The entry list cards (EntryListCard,
// CalendarAccountsCard) use it.
Flow {
  id: root

  property int count: 0
  property int current: 0
  property var labelAt: i => ""
  property var iconAt: i => ""

  signal picked(int index)
  signal menuRequested(int index, Item item, real x, real y)

  spacing: Widget.spacing / 2

  Repeater {
    model: root.count

    delegate: SegmentButton {
      id: tab
      required property int index

      text: root.labelAt(tab.index)
      iconText: root.iconAt(tab.index)
      active: tab.index === root.current
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      onClicked: root.picked(tab.index)
      onMenuRequested: (x, y) => root.menuRequested(tab.index, tab, x, y)
    }
  }
}
