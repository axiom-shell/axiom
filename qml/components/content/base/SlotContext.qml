pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// What Card and Panel derive from their slot, in one place: its size in
// grid units (four to a card), shape, whether it's compact, bare, and the
// padding content lays out within
QtObject {
  // [col, row, colSpan, rowSpan] in grid units, four to a card
  property var slotRect: [0, 0, 4, 4]
  // { kind: "overlay" } or { kind: "menu", id, bare }
  property var host: ({
      "kind": "overlay"
    })
  // Shown as a card (false: a bar popout, which is never compact or bare)
  property bool embedded: true
  // The slot's size in px, and the least the module's full layout needs
  // inside its padding (0: any). A unit is 25 to 140 px depending on the
  // screen or menu, and text doesn't scale with it, so modules say what
  // they need in px
  property real width: 0
  property real height: 0
  property real fullMinWidth: 0
  property real fullMinHeight: 0
  // The height (px) the content wants, for a grid that lets it grow
  // (`properties.grow`, see ModuleGrid): its height plus what its
  // scrolling list is short of, or less what it has to spare; while
  // compact (nothing laid out to measure), any positive value. 0: nothing
  // to show, back to its place
  property real wantedHeight: 0

  readonly property int cols: slotRect[2]
  readonly property int rows: slotRect[3]
  // "square" | "horizontal" | "vertical"
  readonly property string shape: GridPlacement.slotShape(slotRect)
  // The full layout's room inside its padding (px, once laid out) is
  // under its fullMin sizes, which are inner px
  readonly property bool _tooNarrow: width > 0 && width - fullPad * 2 < fullMinWidth
  readonly property bool _tooShort: height > 0 && height - fullPad * 2 < fullMinHeight
  // A quarter card or smaller, or smaller than the full layout needs:
  // room for the key figure only (by px once laid out, so a module isn't
  // built compact and rebuilt before it has a size)
  readonly property bool compact: embedded && ((cols <= 2 && rows <= 2) || _tooNarrow || _tooShort)
  // What the grid grows it to: what it wants, but never less than its full
  // layout needs (fullMinHeight inside the padding), so growing shows the
  // full layout and never shrinks it back to compact. 0 when it wants
  // nothing, or is too narrow for the full layout (taller wouldn't help)
  readonly property real growHeight: wantedHeight > 0 && !_tooNarrow ? Math.max(wantedHeight, fullMinHeight + fullPad * 2) : 0
  // No card box (an overlay page, an edge menu or the lock screen with
  // moduleBorders off)
  readonly property bool bare: embedded && (host?.bare ?? false)
  // Content that draws its own box (e.g. a blurred cover) even when bare,
  // so it keeps its padding inside that box
  property bool drawsBox: false
  // A bare module in an edge menu drops its padding too (the menu pads
  // it); on the lock screen, the greeter and the desktop nothing else
  // would, nor on an overlay page or in an expanded detail (`padded`:
  // Custom, ExpandedModule)
  readonly property bool _unpadded: bare && !drawsBox && host?.padded !== true && host?.kind !== "lockscreen" && host?.kind !== "greeter" && host?.kind !== "desktop"
  readonly property real pad: OverlayConfig.cardPad(compact, _unpadded)
  // The full layout's padding, what `compact` is decided by (so it doesn't
  // depend on itself)
  readonly property real fullPad: OverlayConfig.cardPad(false, _unpadded)
  // The room inside `pad`
  readonly property real innerWidth: width - pad * 2
  readonly property real innerHeight: height - pad * 2
}
