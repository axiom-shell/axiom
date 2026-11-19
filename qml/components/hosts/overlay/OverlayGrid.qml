pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// One page's card grid, sized to its screen: cards of the card size there
// times the page's own sizing, at most two filling the height
// (OverlayConfig.layoutFor), their content laid out at `unit` and drawn
// `zoom` (its Content size factor) times that, so text keeps the Content
// size's size on every monitor. Each overlay page, page window and the
// onboarder has its own; a page that still overflows is shrunk by its
// PageBox.
QtObject {
  id: root

  // The screen whose card size it starts from, and the drawn px a page
  // may take, set by its host
  property var screen: null
  property real availableWidth: 0
  property real availableHeight: 0
  // The page's own sizing (its Card and Content size factors,
  // Sizing.factors), null for the global sizes alone
  property var sizing: null
  // A card size of its own (an edge menu's, a screen layout's), used
  // as is, undrawn, instead of what fits; 0 fits the space
  property int fixedUnit: 0
  // The px between its cards: the layout's, or with a card size of its
  // own the layout's drawn at its zoom (GridPlacement.gapOf), set by its host
  property real gap: GridPlacement.cardSpacing
  // A page window's grid (hosts/window/PageWindow): cards the size the
  // overlay has on its screen, whatever the window's size, and pages
  // filling the window's height (BaseView.pageHeight)
  property bool windowed: false
  // What its page is drawn at, as a whole (PageBox.contentZoom),
  // so modules sit on whole drawn px (GridPlacement.rectPx); 1 where each
  // module is zoomed instead (an edge menu's)
  property real drawnZoom: 1

  readonly property var _layout: root.fixedUnit > 0 ? null : (root.windowed ? OverlayConfig.layoutFor(root.screen, root.screen?.width ?? 0, root.screen?.height ?? 0, root.sizing) : OverlayConfig.layoutFor(root.screen, root.availableWidth, root.availableHeight, root.sizing))
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
