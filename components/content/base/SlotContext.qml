pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// What Card and Panel derive from their slot, in one place: its size in
// grid units (four to a card), shape, whether it's compact, bare, and the
// padding content lays out within
QtObject {
  // [col, row, colSpan, rowSpan] in grid units, four to a card
  property var slotRect: [0, 0, 4, 4]
  // { kind: "overlay" } or { kind: "edgeMenu", id, bare }
  property var host: ({
      "kind": "overlay"
    })
  // Shown as a card (false: a bar popout, which is never compact or bare)
  property bool embedded: true
  // The slot's size in px, and the least the module's full layout needs
  // (0: any). A unit is 25 to 140 px depending on the screen or menu, and
  // text doesn't scale with it, so modules say what they need in px
  property real width: 0
  property real height: 0
  property real fullMinWidth: 0
  property real fullMinHeight: 0

  readonly property int cols: slotRect[2]
  readonly property int rows: slotRect[3]
  // "square" | "horizontal" | "vertical"
  readonly property string shape: OverlayConfig.slotShape(slotRect)
  // A quarter card or smaller, or smaller than the full layout needs:
  // room for the key figure only (by px once laid out, so a module isn't
  // built compact and rebuilt before it has a size)
  readonly property bool compact: embedded && ((cols <= 2 && rows <= 2) || (width > 0 && width < fullMinWidth) || (height > 0 && height < fullMinHeight))
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
  readonly property real pad: OverlayConfig.cardPad(compact, bare && !drawsBox && host?.padded !== true && host?.kind !== "lockscreen" && host?.kind !== "greeter" && host?.kind !== "desktop")
  // The room inside `pad`
  readonly property real innerWidth: width - pad * 2
  readonly property real innerHeight: height - pad * 2
}
