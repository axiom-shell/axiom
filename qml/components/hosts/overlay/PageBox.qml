pragma ComponentBehavior: Bound
import QtQuick
import qs.components.methods

// A page laid out at its grid's unit and drawn as a whole, scaled from its
// top left and placed in the middle of its parent on a whole px, so the
// modules' edges on whole drawn px (OverlayGrid.drawnZoom) are on the
// screen's. It's drawn at its grid's `zoom`, less what it takes to fit its
// room. The host gives its `width` and `height` (the page's size in layout
// px) and puts the page inside. `contentZoom`: what StyledIcon looks for to
// draw its glyphs for a scaled page. Item.scale doesn't feed back into the
// sizes, so no binding loop. Shared by the overlay's pages, page windows and
// the onboarder.
Item {
  id: root

  // Its grid's zoom (OverlayGrid.zoom)
  property real zoom: 1
  // The drawn px it may take, 0 for no limit on that axis
  property real roomWidth: 0
  property real roomHeight: 0
  // Whether the room's height shrinks it too. A page window fills its
  // height instead (OverlayGrid.availableHeight): its fit depends on the
  // width alone
  property bool fitHeight: true
  // The most it's drawn at, as a share of its zoom: the onboarder shows its
  // pages as small as the overlay's first
  property real fitCap: 1

  // The share of its zoom it's drawn at, so it fits its room
  readonly property real fitScale: {
    const fitWidth = root.roomWidth > 0 ? GridPlacement.fitLength(root.width * root.zoom, root.roomWidth) : 1;
    const fitTall = root.fitHeight && root.roomHeight > 0 ? GridPlacement.fitLength(root.height * root.zoom, root.roomHeight) : 1;
    return Math.min(root.fitCap, fitWidth, fitTall);
  }
  // What the page, laid out at the grid's unit, is drawn at
  readonly property real contentZoom: root.zoom * root.fitScale

  x: Math.round((parent.width - width * scale) / 2)
  y: Math.round((parent.height - height * scale) / 2)
  transformOrigin: Item.TopLeft
  scale: root.contentZoom
  readonly property real drawnZoom: root.contentZoom * TextRender.zoomAt(root.parent)
  readonly property var inkHostAbove: InkHost.find(root.parent)
}
