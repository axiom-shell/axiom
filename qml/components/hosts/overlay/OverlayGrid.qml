pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// One overlay's card grid, sized to its screen: cards of the card size
// there times the overlay's Module size, at most two filling the height
// (OverlayConfig.layoutFor), their content laid out at `unit` and drawn
// `zoom` (the Module size) times that, so text keeps the Interface
// scale's size on every monitor. Each OverlayPanel has its own; pages
// that still overflow are shrunk by OverlayPages.
QtObject {
  id: root

  // The screen whose card size it starts from, and the drawn px a page
  // may take, set by the panel
  property var screen: null
  property real availableWidth: 0
  property real availableHeight: 0
  // A card size of its own (an edge menu's, a screen layout's), used
  // as is, undrawn, instead of what fits; 0 fits the space
  property int fixedUnit: 0
  // The px between its cards: the layout's, or with a card size of its
  // own the layout's drawn at its zoom (GridPlacement.gapOf), set by its host
  property real gap: GridPlacement.cardSpacing

  readonly property var _layout: root.fixedUnit > 0 ? null : OverlayConfig.layoutFor(root.screen, root.availableWidth, root.availableHeight)
  // The card size content lays out at, and the one it's drawn at
  readonly property int unit: root._layout ? root._layout.unit : root.fixedUnit
  readonly property int drawnUnit: root._layout ? root._layout.drawn : root.fixedUnit
  readonly property real zoom: root._layout ? root._layout.zoom : 1
  // The room in layout px, what views size themselves against
  readonly property real roomWidth: root.availableWidth / root.zoom
  readonly property real roomHeight: root.availableHeight / root.zoom

  function span(n) {
    return GridPlacement.span(n, root.unit, root.gap);
  }

  // One grid unit across and down, and the whole grid, for modules
  // reaching `bounds` (see GridPlacement.trackSizes)
  function sizes(bounds, stretch) {
    return GridPlacement.trackSizes(bounds, root.unit, stretch, root.gap);
  }
}
