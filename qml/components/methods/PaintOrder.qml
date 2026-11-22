pragma Singleton
import QtQuick

// The order the backing window paints the chrome's shapes in (pure): each
// shape's fill and stroke together, lower levels first, so a surface standing
// on a bar hides the bar's stroke under its fill (BlurShape.paintLevel,
// BlurBackingWindow's copies). Sites read a level by name (`of`), never a
// bare number. Ties fall to registration order, which no level may rely on
// where two of its shapes overlap.
QtObject {
  id: root

  // Lowest first. Kept as plain JSON, as LayerStack.layers is
  readonly property var levels: [
    {
      "name": "base",
      "level": 0,
      "why": "Solid bars' fill and integrated edge menus' strips: they never overlap, each placed in what the other leaves."
    },
    {
      "name": "frame",
      "level": 1,
      "why": "The border's frame, over a solid bar's inner part as the strip draws today; a solid bar's inner stroke and the border-off rect (border off, so never with the frame) over their fills and a strip."
    },
    {
      "name": "bar",
      "level": 2,
      "why": "Pills and islands: they hang over the frame's stroke, inside the border."
    },
    {
      "name": "merge",
      "level": 3,
      "why": "A pill merging into another bar's at a corner (CornerMerge): over the pill it merges into."
    },
    {
      "name": "surface",
      "level": 4,
      "why": "Surfaces attached to any of them (bar and edge popouts, docks, menus, menu tiles): over bars, whatever their window's layer."
    },
    {
      "name": "submenu",
      "level": 5,
      "why": "Submenus: over their parent."
    },
    {
      "name": "toast",
      "level": 6,
      "why": "Toasts, over docks, for the frames a dock slides away under arriving toasts: their Overlay window lies over the dock's Top one."
    }
  ]

  // An eraser (a shape another backing window draws over this one) sits this
  // far under its level, so it ties only with other erasers and never with a
  // shape of this window
  readonly property real eraserOffset: 0.5

  // The level of `name`; NaN for a name not listed
  function of(name) {
    return root.levels.find(l => l.name === name)?.level ?? NaN;
  }
}
