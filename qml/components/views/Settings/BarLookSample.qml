pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.bar.look

// What the Bar style block draws of bars, the one file of it that draws
// them (so when the bar's drawing code moves, only this changes): a tile's
// picture (a ChoiceTiles preview). Three boxes (an icon, an icon with a
// short label, a label), each its own accent from the theme, on a strip
// of bar, in a bar style (a BarStyle's values) with one key set to the
// tile's value, in the look that resolves to (barConfig.look,
// BarLook.resolve): their caps and room as WidgetDecorations places them
// (BarRuns), a merged run's one background, a tab reaching to the strip's
// top edge, separators between, the bar's gradient along the three. Plain
// shapes from the drawing kit, no bar widgets: made once per tile, its
// properties set in place on an edit. It reads the look's traits and
// resolved fields, never its style's name.
Item {
  id: root

  // The tile's option, and the key it sets
  required property var value
  property string key: ""
  // The BarStyle values the other keys come from
  property var values: ({})
  // The bar entry (Bars.items) whose spacing the samples take, or null
  property var bar: null

  // The style drawn: the values with the tile's key set
  readonly property var _style: Object.assign({}, root.values, root.key !== "" ? {
    [root.key]: root.value
  } : {})
  // The boxes' thickness, as a bar's
  readonly property real _thickness: Math.round(Widget.px(22))
  // The sample bar: `bar` along a top edge with no widgets of its own,
  // in the style drawn. Worked out again only when what it's drawn from
  // changes, and kept only if it differs: as a binding it would read the
  // config readers, which every settings edit replaces, and every tile
  // would redraw on an edit that changes none of them.
  // (Its first value a binding, replaced as it completes)
  property var _barConfig: root._enriched()
  Component.onCompleted: root._barConfig = root._enriched()
  function _enriched() {
    return BarsConfig.enrichBarConfig(Object.assign({}, root.bar ?? {}, {
      "edge": "top",
      "thickness": root._thickness,
      "widgets": {},
      "style": root._style
    }), {}, {});
  }
  function _refresh() {
    const next = root._enriched();
    if (!Utils.deepEqual(next, root._barConfig))
      root._barConfig = next;
  }
  on_StyleChanged: root._refresh()
  onBarChanged: root._refresh()
  on_ThicknessChanged: root._refresh()

  // Its look, resolved (shape and grouping as drawn, its traits), and
  // what of it the runs read (BarRuns.context)
  readonly property var _look: root._barConfig.look
  readonly property var _ctx: BarRuns.context(root._barConfig)

  // The three samples' places in their one run (BarRuns.segmentAt, clear
  // of their content as a bar widget's: a line of text), and their boxes
  // along the strip ({ x, lead, length, back }), the bar's spacing apart
  readonly property var _samples: [first, second, third]
  readonly property var _segments: [0, 1, 2].map(index => BarRuns.segmentAt(root._ctx, {
      "index": index,
      "count": 3
    }, root._barConfig.fontSize))
  readonly property var _boxes: {
    const out = [];
    let x = 0;
    for (let index = 0; index < 3; index++) {
      const segment = root._segments[index];
      const length = segment.lead + Math.ceil(root._samples[index].implicitWidth) + segment.trail;
      out.push({
        "x": x,
        "lead": segment.lead,
        "length": length,
        "back": segment.back
      });
      x += length + root._barConfig.groupSpacing;
    }
    return out;
  }
  readonly property real _length: root._boxes[2].x + root._boxes[2].length
  // Across: the boxes centred on the strip, a tab reaching from them to
  // its top edge, its content moved to the tab's middle
  readonly property real _rowTop: Math.round((root.height - root._thickness) / 2)
  readonly property real _reach: root._look.shape.name === "tab" ? root._rowTop : 0
  readonly property real _shift: BarTabs.tabShift(root._reach, false)

  implicitHeight: Widget.px(36)

  // A sample's content: an icon and a label, either left out, in the
  // colors its box gives them (WidgetLook: Auto, so the bar's gradient
  // takes its place), apart on a split bar
  component Sample: Item {
    id: sample

    required property int index
    property string icon: ""
    property string text: ""
    // Its accent (a theme color name)
    property string color: ""

    readonly property var box: root._boxes[sample.index]
    readonly property real padding: root._barConfig.innerPadding
    readonly property bool both: sample.icon !== "" && sample.text !== ""
    // An icon part and a label apart (a split look)
    readonly property bool splits: root._barConfig.splitRoom >= 0 && sample.both
    readonly property real gap: sample.splits ? root._barConfig.splitRoom : sample.both ? root._barConfig.iconGap : 0
    // Measured from the fonts, not the drawn items (their colors follow
    // where the box sits, which follows its length)
    readonly property real iconLength: sample.icon !== "" ? Math.ceil(iconMetrics.advanceWidth) : 0
    // Its colors, where it sits along the strip
    readonly property var colors: look.colors
    // Along it, the middle of the gap between its parts, and what the
    // icon part holds (as a split bar widget's)
    readonly property real splitAt: sample.splits ? sample.padding + sample.iconLength + sample.gap / 2 : -1
    readonly property rect splitPart: sample.splits ? Qt.rect(sample.padding, (root._thickness - root._barConfig.fontSize) / 2, sample.iconLength, root._barConfig.fontSize) : Qt.rect(0, 0, 0, 0)

    implicitWidth: sample.padding * 2 + sample.iconLength + sample.gap + (sample.text !== "" ? Math.ceil(textMetrics.advanceWidth) : 0)
    width: sample.implicitWidth
    height: root._thickness
    x: sample.box.x + sample.box.lead
    y: root._rowTop + root._shift

    readonly property WidgetLook _look: WidgetLook {
      id: look
      barConfig: root._barConfig
      properties: ({
          "backgroundColor": sample.color,
          "foregroundColor": "base00"
        })
      accentField: "backgroundColor"
      autoColors: ({
          "backgroundColor": {
            "role": "accent",
            "gradient": true
          }
        })
      length: sample.implicitWidth
      barOffset: sample.box.x + sample.box.lead
      barLength: root._length
      splits: sample.splits
    }

    TextMetrics {
      id: iconMetrics
      font: iconItem.font
      text: sample.icon
    }

    TextMetrics {
      id: textMetrics
      font: textItem.font
      text: sample.text
    }

    StyledIcon {
      id: iconItem
      visible: sample.icon !== ""
      text: sample.icon
      textSize: root._barConfig.fontSize
      textColor: sample.colors.icon
      x: sample.padding
      anchors.verticalCenter: parent.verticalCenter
    }

    StyledText {
      id: textItem
      visible: sample.text !== ""
      text: sample.text
      textSize: root._barConfig.fontSize
      textColor: sample.colors.text
      x: sample.padding + sample.iconLength + sample.gap
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  // The bar the boxes sit on
  Rectangle {
    anchors.fill: parent
    radius: Widget.radius
    color: root._barConfig.palette.background
  }

  // The strip, shrunk to fit a narrow tile
  Item {
    width: root._length
    height: root.height
    anchors.centerIn: parent
    scale: Math.min(1, (root.width - Widget.smallPadding * 2) / Math.max(1, root._length))
    enabled: false

    // A merged run's one background, under the boxes
    WidgetBackground {
      visible: root._look.grouping === "merged"
      z: -2
      barConfig: root._barConfig
      colors: BarsConfig.groupColors(root._barConfig, 0.5)
      gradientStart: 0
      gradientEnd: 1
      startCap: root._segments[0].startCap
      endCap: root._segments[2].endCap
      width: root._length
      height: root._thickness + root._reach
      y: root._rowTop - root._reach
    }

    // Each box, a powerline segment reaching back under the one before
    // (so drawn under it)
    Repeater {
      model: 3

      delegate: WidgetBackground {
        id: background
        required property int index
        readonly property var box: root._boxes[background.index]
        readonly property var segment: root._segments[background.index]
        readonly property Sample sample: root._samples[background.index]

        z: -1 - background.index / 3
        barConfig: root._barConfig
        colors: background.sample?.colors ?? null
        startCap: background.segment.startCap
        endCap: background.segment.endCap
        seamStart: background.segment.seamStart
        seamEnd: background.segment.seamEnd
        shownStart: background.segment.shownStart
        levelStartCap: background.segment.levelStartCap
        levelEndCap: background.segment.levelEndCap
        gradientStart: (background.box.x - background.box.back) / root._length
        gradientEnd: (background.box.x + background.box.length) / root._length
        // A split box's parts, from the background's start (back under the
        // one before, and across from the tab's outer edge)
        splitAt: background.sample?.splits ? background.box.back + background.box.lead + background.sample.splitAt : -1
        splitPart: background.sample?.splits ? Qt.rect(background.box.back + background.box.lead + background.sample.splitPart.x, root._reach + root._shift + background.sample.splitPart.y, background.sample.splitPart.width, background.sample.splitPart.height) : Qt.rect(0, 0, 0, 0)
        x: background.box.x - background.box.back
        y: root._rowTop - root._reach
        width: background.box.length + background.box.back
        height: root._thickness + root._reach
      }
    }

    // A separator in each gap (none in a powerline, whose boxes touch)
    Repeater {
      model: 2

      delegate: SeparatorMark {
        id: mark
        required property int index
        readonly property real center: root._boxes[mark.index].x + root._boxes[mark.index].length + root._barConfig.groupSpacing / 2

        visible: root._look.separators.style !== "none"
        style: root._look.separators.style
        color: root._barConfig.palette.separator
        thickness: root._look.separators.thickness
        length: BarLayout.dividerLength(mark.style, root._thickness)
        x: mark.center - width / 2
        y: root._rowTop + Math.round((root._thickness - height) / 2) + root._shift
      }
    }

    Sample {
      id: first
      index: 0
      icon: "wifi"
      color: "base0D"
    }

    Sample {
      id: second
      index: 1
      icon: "volume_up"
      text: "42%"
      color: "base0B"
    }

    Sample {
      id: third
      index: 2
      text: "12:30"
      color: "base0E"
    }
  }
}
