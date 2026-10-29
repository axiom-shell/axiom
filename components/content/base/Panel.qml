pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.components.reusable

// Content that lays out as a column and can be shown by either host: a bar
// popout (sized to its content, with the popout's box) or an overlay card
// (`embedded`: fills the slot, with the card's box). Children go into the
// margin-inset column. Content sets `margins`/`spacing`, and implicitWidth
// (plus implicitHeight if it isn't just the column's).
Item {
  id: root

  // -- From the host --
  // The bar popout wrapper, when a popout shows this (null in a card)
  property var wrapper: null
  // In an overlay card: fill the slot, draw the card box, and let lists
  // fill the height instead of their popout cap
  property bool embedded: false
  // Card only: this module's `properties` from config, and its slot
  // ([col, row, colSpan, rowSpan] in grid units, see Card)
  property var properties: ({})
  property var slotRect: [0, 0, 4, 4]
  // Card only: where it's shown, { kind: "overlay" } or { kind: "edgeMenu",
  // id, bare }
  property var host: ({
      "kind": "overlay"
    })
  // Card only: the least width and height (px) the full column needs; a
  // smaller slot is compact (see SlotContext)
  property real fullMinWidth: 0
  property real fullMinHeight: 0
  // Card only: the content draws its own box (a `background`) even when
  // bare, so it keeps its padding (see SlotContext)
  property bool drawsBox: false
  // Card only: the height (px) its content wants, for a grid that lets it
  // grow (`properties.grow`, see ModuleGrid): its height plus what its
  // scrolling list is short of, or less what it has to spare; while
  // compact (nothing laid out to measure), any positive value. 0: nothing
  // to show, back to its place
  property real wantedHeight: 0
  // What the grid grows it to: what it wants, but never less than its full
  // layout needs (fullMinHeight), so growing shows the full layout and
  // never shrinks it back to compact. 0 when it wants nothing, or is too
  // narrow for the full layout (taller wouldn't help)
  readonly property real growHeight: root.wantedHeight > 0 && !(root.width > 0 && root.width < root.fullMinWidth) ? Math.max(root.wantedHeight, root.fullMinHeight) : 0
  // Card only: the grid showing it, and growing a detail over it, as on
  // Card
  property var expander: null
  function canExpand(type) {
    return root.expander?.canExpand(type) ?? false;
  }
  function expand(type, properties, from) {
    root.expander?.expand(type, properties ?? {}, from ?? root);
  }
  // Derived from the slot, as on Card (see SlotContext); a popout is never
  // bare or compact
  readonly property alias bare: slot.bare
  readonly property alias cols: slot.cols
  readonly property alias rows: slot.rows
  readonly property alias shape: slot.shape
  readonly property alias compact: slot.compact
  readonly property alias pad: slot.pad
  readonly property alias innerWidth: slot.innerWidth
  readonly property alias innerHeight: slot.innerHeight

  property SlotContext _slot: SlotContext {
    id: slot
    slotRect: root.slotRect
    host: root.host
    embedded: root.embedded
    width: root.width
    height: root.height
    fullMinWidth: root.fullMinWidth
    fullMinHeight: root.fullMinHeight
    drawsBox: root.drawsBox
  }

  // Bar popout only: the largest implicit size content that changes size
  // while open can take (0: undeclared), so the popout's window is made
  // that big from the start rather than resized (see BarPopouts.spareAcross)
  property real maxImplicitWidth: 0
  property real maxImplicitHeight: 0

  // Bar popout only: which way the popout grows as the content does
  // (BarPopouts.growth), "down" in a card. Content that grows keeps its
  // controls on the side it grows from: with `flips`, its column's items
  // show in reverse order while it grows "up" (from a bottom bar, or low
  // on a side bar), the controls last, by the bar (see LayoutOrder for
  // what the column may hold).
  readonly property string growth: root.embedded ? "down" : root.wrapper?.growth ?? "down"
  readonly property bool growsUp: root.growth === "up"
  property bool flips: false
  property LayoutOrder _order: LayoutOrder {
    layout: column
    reversed: root.flips && root.growsUp
  }

  // Bar popout only: keep the keyboard (and a focus grab) while a text
  // field is up; a click outside the popout calls focusLost()
  property bool wantsKeyboardFocus: false
  signal focusLost

  // Pointer over the content; `hovered` (what the popout wrapper reads) can
  // add more reasons to stay open, e.g. a drag in progress
  readonly property bool pointerInside: hoverHandler.hovered
  property bool hovered: pointerInside

  // What a compact card shows instead of the column (e.g. a
  // CompactFigure), filling the box inside `pad`; without one, a compact
  // card shows the column as usual
  property Component compactContent: null
  // Drawn under the content, filling the box (e.g. a blurred cover)
  property Component background: null
  readonly property bool _showCompact: root.compact && root.compactContent !== null

  // In a popout the box reaches out over the host's padding
  // (Popouts.padding) to the surface's stroke, so a `background` fills the
  // whole popout while the column keeps the padding
  readonly property real bleed: root.embedded ? 0 : PopoutsConfig.padding
  // The box's corner radius, for backgrounds that follow its shape (in a
  // popout, the inside of the surface's stroke)
  readonly property real boxRadius: root.embedded ? Widget.radius : Math.max(0, Appearance.borderRadius - Appearance.borderWidth)

  // Popout only: the host's surface already pads it (Popouts.padding)
  property int margins: 0
  property alias spacing: column.spacing
  readonly property alias body: column
  default property alias content: column.data

  implicitHeight: column.implicitHeight + margins * 2
  // A card sizes this to its slot (the Loader fills it); a popout sizes
  // itself to the content
  width: root.embedded ? (parent?.width ?? implicitWidth) : implicitWidth
  height: root.embedded ? (parent?.height ?? implicitHeight) : implicitHeight

  Rectangle {
    anchors.fill: parent
    anchors.margins: -root.bleed
    // A popout's surface draws its own fill
    color: root.embedded && !root.bare ? Appearance.fill(Theme.background) : "transparent"
    border.color: root.embedded && !root.bare ? Theme.border : "transparent"
    border.width: root.embedded && !root.bare ? Appearance.borderWidth : 0
    radius: root.boxRadius
    clip: true

    HoverHandler {
      id: hoverHandler
    }

    Loader {
      anchors.fill: parent
      active: root.background !== null
      sourceComponent: root.background
    }

    Loader {
      anchors.fill: parent
      anchors.margins: root.pad
      active: root._showCompact
      sourceComponent: root.compactContent
    }

    ColumnLayout {
      id: column
      visible: !root._showCompact
      anchors.fill: parent
      anchors.margins: root.embedded ? root.pad : root.bleed + root.margins
      spacing: Widget.spacing
    }
  }
}
