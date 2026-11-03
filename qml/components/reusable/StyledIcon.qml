pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// A Material Symbols icon: `text` is its name ("wifi"), or several names
// separated by spaces or newlines. Anything else (a glyph or text a user
// typed into an icon field) is drawn in the text font instead.
StyledText {
  id: root

  // -- Public API --
  readonly property bool isSymbol: /^\s*[a-z][a-z0-9_]*(\s+[a-z][a-z0-9_]*)*\s*$/.test(text)
  // Material Symbols' variable axes
  property real fill: 0
  property int weight: 400

  // -- Implementation --
  textFamily: isSymbol ? Appearance.iconFamily : Appearance.fontFamily
  // Filled symbols are built from overlapping contours, which the default
  // distance-field renderer draws as blotches, and curve rendering leaves seams
  // and uneven thin strokes. Native rendering gets both right, but a scaled
  // native glyph is resampled and blurs: grow an icon by size, not `scale`.
  // Drawn scaled (ancestors' `contentZoom`s: the overlay's pages, an edge
  // menu's modules), an unfilled one is drawn by the distance-field renderer, which
  // scales cleanly
  renderType: isSymbol && !(root._zoomed && root.fill === 0) ? Text.NativeRendering : Text.QtRendering
  // The ancestors whose `contentZoom`s it's drawn at (a page's, a menu
  // module's), found once it's placed
  // (var: qmllint knows only Item's members)
  property var _zoomHosts: []
  readonly property bool _zoomed: Math.abs(root._zoomHosts.reduce((zoom, host) => zoom * host.contentZoom, 1) - 1) > 0.01
  Component.onCompleted: {
    const hosts = [];
    for (let item = root.parent; item; item = item.parent) {
      if ("contentZoom" in item)
        hosts.push(item);
    }
    root._zoomHosts = hosts;
  }
  font.variableAxes: isSymbol ? {
    "FILL": root.fill,
    "wght": root.weight
  } : ({})
}
