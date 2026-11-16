pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods

// A single choice as a wrapping row of equal tiles (a TileFlow) in an even
// grid (ChoiceGrid: one line when all fit, never one per line while two
// fit), each a PreviewTile: a preview over its label, or a card with an
// icon, description and tag. The chosen one is filled with the accent
// container and ringed in the accent, one that can't be picked greyed, saying
// why in a tooltip on hover. One Tab stop: arrow keys move between the tiles,
// Enter or Space picks. The owner keeps the value: set `value`, and update it
// from `picked`.
TileFlow {
  id: root

  // [{ value, label, preview, icon, description, tag, tagTone,
  // disabledReason }]: `preview` (optional) a Component drawn over the
  // label, its root declaring `required property var value` (handed the
  // option's) and any previewProperties; `icon`, `description` or `tag` make
  // the tile a card instead; a non-empty `disabledReason` greys the tile and
  // is its tooltip
  property var options: []
  // "grid": the even grid; "rows": two to a line (one option, one), every
  // tile as tall as the tallest on its line (a pair of onboarding choices)
  property string layout: "grid"
  property var value
  // Every tile's preview, for options without their own
  property Component preview: null
  // More properties every preview is made with, beside its `value`, and
  // kept up to date in place (the Bar style block's look)
  property var previewProperties: ({})
  // The preview's height, on every tile while any tile has one
  property real previewHeight: Widget.px(36)
  // The narrowest a preview is drawn (a fixed number: previews are built
  // later from the queue, so it can't be measured)
  property real previewMinWidth: Widget.px(96)

  signal picked(var value)

  readonly property int _selected: Array.prototype.findIndex.call(root.options, option => option.value === root.value)
  readonly property bool _previews: root.preview !== null || Array.prototype.some.call(root.options, option => !!option.preview)
  // The tile the keys are on
  property int _cursor: -1
  // The narrowest tile: the widest label (measured) in its margins, and the
  // preview's floor while there are previews
  readonly property real _leastTile: {
    let widest = 0;
    for (let i = 0; i < measures.count; i++)
      widest = Math.max(widest, (measures.objectAt(i) as TextMetrics)?.advanceWidth ?? 0);
    const label = Math.ceil(widest) + Widget.smallPadding * 2;
    return root._previews ? Math.max(label, root.previewMinWidth + Widget.smallPadding * 2) : label;
  }

  // Each tile's own height, for the rows layout
  property var _heights: []

  minTileWidth: Style.typeBody * 9
  columns: root.layout === "rows" ? Math.max(1, Math.min(2, root.options.length)) : ChoiceGrid.columns(root.options.length, root.width, root.minTileWidth, root._leastTile, root.spacing)
  activeFocusOnTab: true
  onActiveFocusChanged: {
    if (root.activeFocus && (root._cursor < 0 || root._cursor >= root.options.length))
      root._cursor = Math.max(0, root._selected);
  }

  function _report(index, height) {
    if (root._heights[index] === height)
      return;
    const next = root._heights.slice();
    next[index] = height;
    root._heights = next;
  }

  // The tallest tile on `index`'s line
  function _rowHeight(index) {
    const first = index - index % root.columns;
    let tallest = 0;
    for (let i = first; i < Math.min(first + root.columns, root.options.length); i++)
      tallest = Math.max(tallest, root._heights[i] ?? 0);
    return tallest;
  }

  function _move(by, event) {
    const next = root._cursor + by;
    event.accepted = next >= 0 && next < root.options.length;
    if (event.accepted)
      root._cursor = next;
  }

  function _pick(index) {
    const option = root.options[index];
    if (option && !option.disabledReason && option.value !== root.value)
      root.picked(option.value);
  }

  Keys.onLeftPressed: event => root._move(-1, event)
  Keys.onRightPressed: event => root._move(1, event)
  Keys.onUpPressed: event => root._move(-root.columns, event)
  Keys.onDownPressed: event => root._move(root.columns, event)
  Keys.onReturnPressed: root._pick(root._cursor)
  Keys.onEnterPressed: root._pick(root._cursor)
  Keys.onSpacePressed: root._pick(root._cursor)

  // One metrics per option, unseen, by count (options come from config)
  Instantiator {
    id: measures
    model: root.options.length

    TextMetrics {
      required property int index
      font.family: Appearance.fontFamily
      font.pixelSize: Style.roleLabel.size
      font.weight: Style.weightMedium
      text: root.options[index]?.label ?? String(root.options[index]?.value ?? "")
    }
  }

  Repeater {
    // By count: an option's reason changes as other settings do
    model: root.options.length

    delegate: PreviewTile {
      id: tile
      required property int index
      readonly property var option: root.options[tile.index] ?? ({})

      width: root.tileWidth
      height: root.layout === "rows" ? root._rowHeight(tile.index) : tile.implicitHeight
      title: tile.option.label ?? String(tile.option.value ?? "")
      icon: tile.option.icon ?? ""
      description: tile.option.description ?? ""
      tag: tile.option.tag ?? ""
      tagTone: tile.option.tagTone ?? "accent"
      selected: tile.index === root._selected
      disabledReason: tile.option.disabledReason ?? ""
      preview: tile.option.preview ?? root.preview
      previewProperties: Object.assign({}, root.previewProperties, {
        "value": tile.option.value
      })
      previewHeight: root._previews ? root.previewHeight : 0
      tabStop: false
      ringed: root.activeFocus && tile.index === root._cursor
      onImplicitHeightChanged: root._report(tile.index, tile.implicitHeight)
      Component.onCompleted: root._report(tile.index, tile.implicitHeight)
      onClicked: {
        root._cursor = tile.index;
        root._pick(tile.index);
      }
    }
  }
}
