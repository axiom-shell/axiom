pragma ComponentBehavior: Bound
import QtQuick

import qs.components.methods

// A BarWidget's value segments (a widget showing several values in one
// box: System Stats' metrics): one IconTextRow and ValueGraphic per key,
// side by side (a column on a vertical bar, the value small and upright
// under its icon), in the display style of `appearance`. A segment's data
// comes from the widget's `segmentData` (`dataOf`) as { icon, text,
// minimumText, ratio (-1: none), history (null: none), graphMin (0),
// graphMax (1), caption, field ("": the widget's colors, else the name of
// the color field it reads in), muted (false) }. Where the segments split
// into an icon part and a label each (a split bar), it reports their
// places: the first as `splitAt` / `splitPart` and the rest as
// `innerSplits`, in its own coordinates (as WidgetBackground reads them).
Item {
  id: root

  required property var barConfig
  // The segments shown, their ids (config, never live values)
  required property var keys
  // key -> its data (above)
  required property var dataOf
  // The widget's paint (WidgetLook.paint) and its display appearance
  // ({ style, segments, width, colorText })
  required property var paint
  required property var appearance
  required property bool isVertical

  // Each segment's icon part and label set apart on a split bar, as its
  // row reports them (IconTextRow.splits), moved from the row into the
  // widget: where the row sits in the box (the grid centred in it, the row
  // centred across), by the rows' sizes and the grid's gap. The first part
  // starts at the box's start; each later one is an inner part from the
  // middle of the gap before it. (The rows register themselves: they're in
  // a component of their own, out of reach of an id)
  property var _items: []
  // The gap the grid keeps between segments along the bar: a split bar's
  // room for a divider between segments, else the usual
  readonly property real _gap: root.barConfig.splitRoom >= 0 ? root.barConfig.splitRoom : (root.isVertical ? root.barConfig.innerGap : root.barConfig.innerPadding)
  // Per segment, null when it doesn't split: { from, at, part } in the widget
  readonly property var _placed: {
    const items = root._items.filter(item => item !== null && item !== undefined);
    const lengthOf = item => root.isVertical ? item.height : item.width;
    const total = items.reduce((sum, item) => sum + lengthOf(item), 0) + Math.max(0, items.length - 1) * root._gap;
    let start = Math.round(((root.isVertical ? root.height : root.width) - total) / 2);
    const placed = [];
    for (const item of items) {
      if (item.splits) {
        const across = Math.round(((root.isVertical ? root.width : root.height) - (root.isVertical ? item.width : item.height)) / 2);
        const part = item.splitPart;
        placed.push({
          "from": start - root._gap / 2,
          "at": start + item.splitAt,
          "part": root.isVertical ? Qt.rect(across + part.x, start + part.y, part.width, part.height) : Qt.rect(start + part.x, across + part.y, part.width, part.height)
        });
      } else {
        placed.push(null);
      }
      start += lengthOf(item) + root._gap;
    }
    return placed;
  }
  readonly property bool splits: root._placed.some(p => p !== null)
  readonly property real splitAt: root._placed[0]?.at ?? -1
  readonly property rect splitPart: root._placed[0]?.part ?? Qt.rect(0, 0, 0, 0)
  readonly property var innerSplits: root._placed.slice(1).filter(p => p !== null)

  implicitWidth: stack.implicitWidth
  implicitHeight: stack.implicitHeight

  BaseWidget {
    id: stack
    anchors.fill: parent
    isVertical: root.isVertical
    crossSize: root.barConfig.thickness
    padding: root.keys.length > 0 ? root.barConfig.innerPadding : 0

    content: Grid {
      columns: root.isVertical ? 1 : Math.max(1, root.keys.length)
      spacing: root._gap
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      Repeater {
        model: root.keys.length

        // One icon + label each, laid out as every bar widget's is; on a
        // vertical bar the value small and upright under the icon
        delegate: IconTextRow {
          id: segment
          required property int index
          Component.onCompleted: {
            const items = root._items.slice();
            items[segment.index] = segment;
            root._items = items;
          }
          Component.onDestruction: {
            const items = root._items.slice();
            if (items[segment.index] === segment) {
              items[segment.index] = null;
              root._items = items;
            }
          }
          readonly property var seg: Object.assign({
            "icon": "",
            "text": "",
            "minimumText": "",
            "ratio": -1,
            "history": null,
            "graphMin": 0,
            "graphMax": 1,
            "caption": "",
            "field": "",
            "muted": false
          }, root.dataOf(root.keys[segment.index]))
          readonly property string style: ValueGraphics.resolvedStyle(root.appearance.style, root.isVertical, segment.seg.history !== null, segment.seg.ratio)
          // Its own color field's, else the widget's, dimmed where it is
          readonly property color _text: segment.seg.field !== "" ? root.paint.field(segment.seg.field, "text") : root.paint.text
          readonly property color _icon: segment.seg.field !== "" ? root.paint.field(segment.seg.field, "icon") : root.paint.icon

          isVertical: root.isVertical
          crossSize: root.barConfig.thickness
          padding: 0
          fontSize: root.barConfig.fontSize
          spacing: root.isVertical ? 0 : root.barConfig.innerGap * 1.5
          textScale: root.isVertical ? 0.7 : 0.9
          uprightLabel: true
          // Its icon part and label apart on a split bar
          splitRoom: root.barConfig.splitRoom
          icon: segment.seg.icon
          text: segment.seg.text
          minimumText: segment.seg.minimumText
          showText: segment.style !== "icon" && segment.style !== "stacked"
          textColor: segment.seg.muted ? root.paint.muted("text", segment._text) : segment._text
          iconColor: segment.seg.muted ? root.paint.muted("icon", segment._icon) : segment._icon
          leadLength: graphic.drawn ? graphic.length : 0
          leadAfterIcon: graphic.afterIcon

          ValueGraphic {
            id: graphic
            parent: segment.lead
            anchors.fill: parent
            style: segment.style
            ratio: Math.max(0, Math.min(1, segment.seg.ratio))
            history: segment.seg.history ?? []
            graphMin: segment.seg.graphMin
            graphMax: segment.seg.graphMax
            text: segment.seg.text
            minimumText: segment.seg.minimumText
            // Stacked: the value over its name, where the value goes
            subtext: segment.seg.caption
            segmentCount: root.appearance.segments
            preferredLength: root.appearance.width
            vertical: root.isVertical
            crossSize: root.barConfig.thickness
            room: ValueGraphics.boxRoom(root.barConfig.thickness, root.barConfig.look.shape)
            fontSize: root.barConfig.fontSize
            middle: segment.iconMiddle
            paint: root.paint.graphic
          }
        }
      }
    }
  }
}
