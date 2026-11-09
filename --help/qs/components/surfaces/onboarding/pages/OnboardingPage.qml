pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable
import qs.components.content.base
import qs.components.hosts.overlay

// One onboarding page: a titled card as wide as the Monitors page and two
// cards high, sized from the overlay's grid, with a short introduction
// over the page's own content (its children). `extras` go beside the card
// (e.g. the Monitors page or the wallpaper picker).
Item {
  id: root

  property OverlayGrid grid
  property string title
  property string intro
  // Content beside the card, left to right after it
  property alias extras: extraRow.data
  default property alias content: card.bodyContent

  // As wide as the Monitors page unless the page sets its own (a page
  // with extras beside the card)
  property real cardWidth: root.grid ? root.grid.unit * 2.6 + OverlayConfig.cardSpacing : 0
  readonly property real cardHeight: root.grid ? root.grid.span(8) : 0

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    spacing: OverlayConfig.cardSpacing

    Item {
      Layout.preferredWidth: root.cardWidth
      Layout.preferredHeight: root.cardHeight

      TitledCard {
        id: card
        color: Theme.background
        title: root.title
        showActions: false

        StyledText {
          Layout.fillWidth: true
          visible: root.intro !== ""
          text: root.intro
          wrapMode: Text.WordWrap
          textColor: Theme.foregroundAlt
        }
      }
    }

    RowLayout {
      id: extraRow
      spacing: OverlayConfig.cardSpacing
      visible: children.length > 0
    }
  }
}
