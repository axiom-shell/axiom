pragma ComponentBehavior: Bound
import QtQuick
import qs.config

// Base for overlay modules (what BaseWidget is for bar modules): the card
// box filling its slot. Modules set only what differs, e.g. `color`,
// and pick their internal layout from `shape` / `compact` (see
// OverlaySlot, which sets `slotRect`).
Rectangle {
  id: root

  // This module's `properties` from config (schema defaults filled in)
  property var properties: ({})
  // Set by the card host, for content that can also be a popout (see Panel)
  property bool embedded: true
  // The slot this module fills, in grid units (four to a card): [col, row,
  // colSpan, rowSpan]
  property var slotRect: [0, 0, 4, 4]
  // Where the card is shown: { kind: "overlay" } or { kind: "menu", id,
  // bare }
  property var host: ({
      "kind": "overlay"
    })
  // The least width and height (px, inside the padding) the module's full
  // layout needs; a smaller slot is compact (see SlotContext)
  property real fullMinWidth: 0
  property real fullMinHeight: 0
  // The height (px) its content wants, and what the grid grows it to (see
  // SlotContext)
  property alias wantedHeight: slot.wantedHeight
  readonly property alias growHeight: slot.growHeight
  // The grid showing this module (a ModuleGrid), which can grow a module's
  // detail over it (see ExpandedModule); null where nothing can
  property var expander: null
  // Whether `type` can be shown over the grid here, and showing it, grown
  // from `from` (an item in this module; the whole module when left out)
  function canExpand(type) {
    return root.expander?.canExpand(type) ?? false;
  }
  function expand(type, properties, from) {
    root.expander?.expand(type, properties ?? {}, from ?? root);
  }
  // Derived from the slot (see SlotContext): no card box (an edge menu
  // with moduleBorders off), the span in grid units, "square" |
  // "horizontal" | "vertical", compact (a quarter card or less, or under
  // the full layout's minimum: room for the key figure only), and the inner
  // padding modules lay their content out within
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
  }

  // What a compact card shows instead of its content (e.g. a
  // CompactFigure), filling the box inside `pad`; without one, a compact
  // card shows its content as usual (as Panel's)
  property Component compactContent: null
  readonly property bool _showCompact: root.compact && root.compactContent !== null
  // Children go in here, filling the card, hidden while the compact
  // content shows
  default property alias content: full.data

  anchors.fill: parent
  color: bare ? "transparent" : Appearance.fill(Theme.background)
  border.color: Theme.border
  border.width: bare ? 0 : Appearance.borderWidth
  radius: Widget.radius
  clip: true

  Item {
    id: full
    anchors.fill: parent
    visible: !root._showCompact
  }

  Loader {
    anchors.fill: parent
    anchors.margins: root.pad
    active: root._showCompact
    sourceComponent: root.compactContent
  }
}
