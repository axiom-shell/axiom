pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// A Material Symbols icon: `text` is its name ("wifi"), or several names
// separated by spaces or newlines. Anything else (a glyph or text a user
// typed into an icon field) is drawn in the text font instead.
StyledText {
  id: root

  // -- Public API --
  readonly property bool isSymbol: Utils.isSymbolName(text)
  // Material Symbols' variable axes
  property real fill: 0
  property int weight: 400
  // "xs" | "sm" | "md" | "lg" | "xl" (Style.iconSize)
  property string size: "sm"

  // -- Implementation --
  textFamily: isSymbol ? Appearance.iconFamily : Appearance.fontFamily
  textSize: Style.iconSize(root.size)
  // A ligature glyph never wraps or elides
  overflow: "none"
  // Filled symbols are built from overlapping contours, which the default
  // distance-field renderer draws as blotches, and curve rendering leaves seams
  // and uneven thin strokes. Native rendering gets both right, but a scaled
  // native glyph is resampled and blurs: grow an icon by size, not `scale`.
  // Drawn under a zoom (ancestors' `contentZoom`s: the overlay's pages, an
  // edge menu's modules) an unfilled one is drawn by the distance-field
  // renderer, which scales cleanly
  renderType: TextRender.typeFor(root._drawnZoom, root.isSymbol, root.fill)
  font.variableAxes: isSymbol ? {
    "FILL": root.fill,
    "wght": root.weight
  } : ({})
}
