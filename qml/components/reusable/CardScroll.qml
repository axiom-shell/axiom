pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config

// A box's scrolling column of cards: the settings page's gutter (inside the
// box's padding, the scroll bar's lane on the right, room for a row's tint
// past both sides) and the card gap. The host places it like any item (fill
// or anchors) and never adds bleed margins of its own.
Item {
  id: root

  // The cards go into the column
  default property alias content: body.data
  property alias spacing: body.spacing
  // The column (for ensurePolished and mapToItem)
  readonly property alias body: body
  readonly property alias flickable: scroll.contentItem
  readonly property alias availableHeight: scroll.availableHeight
  readonly property alias contentHeight: scroll.contentHeight

  StyledScrollView {
    id: scroll
    anchors.fill: parent
    // Room for a row's hover tint past the column (the box's padding holds it)
    anchors.leftMargin: -Style.rowBleed
    anchors.rightMargin: -Style.rowBleed
    bleed: Style.rowBleed
    contentPadding: 0
    showScrollBar: true

    ColumnLayout {
      id: body
      width: scroll.availableWidth
      spacing: Style.cardGap
    }
  }
}
