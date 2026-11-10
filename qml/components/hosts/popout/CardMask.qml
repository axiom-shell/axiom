pragma ComponentBehavior: Bound
import Quickshell
import QtQuick
import QtQuick.Controls

// A window's input mask on a tiled menu's cards alone (MenuTiles): the
// union of `rects` ({ x, y, width, height }, from MenuTiles.union, in the
// coordinates of what holds them) moved by `offset` into the window, so a
// click between two cards reaches what's behind. A host's own `regions`
// join it (FreeMenu's header menu). While a popup is open in the window
// (a context menu, a module's dropdown), which may reach past the cards,
// the whole of `box` (the menu's box, an item in the window) takes input
// too. Modelled by count, as BlurRegion: rects moving (a scroll) update
// their regions, never remake them.
Region {
  id: root

  property var rects: []
  property point offset: Qt.point(0, 0)
  property Item box: null
  // Regions of the host's own, joined to the cards
  property var extra: []

  // A popup of the window's open (a Popup shows as a child of its
  // window's overlay)
  readonly property bool popupOpen: (root.box?.Overlay.overlay?.visibleChildren.length ?? 0) > 0

  readonly property int _count: root.rects.length

  regions: [boxRegion].concat(Array.from(cardRegions.instances), root.extra)

  property Region _box: Region {
    id: boxRegion
    item: root.popupOpen ? root.box : null
  }

  property Variants _cards: Variants {
    id: cardRegions
    model: Array.from({
      "length": root._count
    }, (_, i) => i)

    delegate: Region {
      id: card
      required property int modelData
      readonly property var rect: root.rects[card.modelData] ?? null
      x: root.offset.x + (card.rect?.x ?? 0)
      y: root.offset.y + (card.rect?.y ?? 0)
      width: card.rect?.width ?? 0
      height: card.rect?.height ?? 0
    }
  }
}
