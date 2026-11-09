pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.components.methods
import qs.components.reusable
import qs.components.bar
import qs.components.bar.widgets.base

// What the Bar style block draws of bars, the one file of it that draws
// them (so when the bar's drawing code moves, only this changes). A tile's
// picture (a ChoiceTiles preview): three fixed sample widgets (an icon, an
// icon with a short label, a label), each its own accent from the theme,
// on a strip of bar, drawn by the bar's own pieces in a bar style (a
// BarStyle's values) with one key set to the tile's value: their
// backgrounds and caps as WidgetGroup gives them, a merged run's one
// background, a tab reaching to the strip's top edge, separators between,
// the bar's gradient along the three. Nothing in it is live: no services,
// no widget types. With `liveConfig` it draws instead that bar's own
// widgets, live, as the bar editor's chips do but each in the shape's
// caps (the block's strip).
Item {
  id: root

  // The tile's option, and the key it sets
  required property var value
  property string key: ""
  // The BarStyle values the other keys come from
  property var values: ({})
  // The bar entry (Bars.items) whose spacing the samples take, or null
  property var bar: null
  // A bar's preview config (BarManager.previewConfigOf): its widgets drawn
  // live in place of the samples, wrapping, or null
  property var liveConfig: null

  // The look drawn: the bar's (lookOf) in the values with the tile's key
  // set, its shape as drawn, as enrichBarConfig works it out (only boxed
  // styles have one)
  readonly property var _style: Object.assign({}, root.values, root.key !== "" ? {
    [root.key]: root.value
  } : {})
  readonly property var _look: BarsConfig.lookOf(Object.assign({}, root.bar ?? {}, {
    "style": root._style
  }))
  readonly property string _shape: BarsConfig.boxedStyles.includes(root._look.widgetStyle) ? BarWidgetStyle.shape(root._look) : "rounded"

  implicitHeight: root.liveConfig ? liveLoader.implicitHeight : Widget.px(36)

  // The bar the widgets sit on
  Rectangle {
    anchors.fill: parent
    radius: Widget.radius
    color: Theme.background
  }

  // The three samples, shrunk to fit a narrow tile
  Loader {
    anchors.fill: parent
    active: !root.liveConfig
    sourceComponent: Item {
      id: samples

      // The widgets' thickness, as a bar's
      readonly property real thickness: Math.round(Widget.px(22))
      // The sample bar: `bar` along a top edge with no widgets of its own,
      // in the look drawn
      readonly property var barConfig: BarsConfig.enrichBarConfig(Object.assign({}, root.bar ?? {}, {
        "location": "top",
        "thickness": samples.thickness,
        "widgets": {},
        "style": root._style
      }), {}, {})
      readonly property var look: root._look
      readonly property string shape: root._shape
      // Its grouping as drawn (only boxed styles group)
      readonly property string grouping: BarsConfig.groupingOf(samples.look)
      readonly property bool opaque: BarWidgetStyle.opaque(samples.look.widgetStyle, samples.look.splitIcon, samples.look.splitLabelFill)
      // A powerline's widgets touch, leaving no gap to divide
      readonly property bool separators: samples.grouping !== "powerline" && samples.look.separatorStyle !== "none"

      // Their places in their run (BarShapes.segment), and their boxes along
      // the strip ({ x, lead, length, back }), the bar's spacing apart
      readonly property var widgets: [first, second, third]
      readonly property var segments: [0, 1, 2].map(index => BarShapes.segment(samples.shape, samples.look.widgetEnds, samples.grouping, samples.opaque, index, 3, samples.thickness))
      readonly property var boxes: {
        const out = [];
        let x = 0;
        for (let index = 0; index < 3; index++) {
          const segment = samples.segments[index];
          const length = segment.lead + Math.ceil(samples.widgets[index].implicitWidth) + segment.trail;
          out.push({
            "x": x,
            "lead": segment.lead,
            "length": length,
            "back": segment.back
          });
          x += length + samples.barConfig.groupSpacing;
        }
        return out;
      }
      readonly property real length: samples.boxes[2].x + samples.boxes[2].length
      // Across: the widgets centred on the strip, a tab reaching from them
      // to its top edge, its content moved to the tab's middle
      readonly property real rowTop: Math.round((samples.height - samples.thickness) / 2)
      readonly property real reach: samples.shape === "tab" ? samples.rowTop : 0
      readonly property real shift: BarShapes.tabShift(samples.reach, false)

      Item {
        width: samples.length
        height: samples.height
        anchors.centerIn: parent
        scale: Math.min(1, (samples.width - Widget.smallPadding * 2) / Math.max(1, samples.length))
        enabled: false

        // A merged run's one background, under the widgets'
        WidgetBackground {
          visible: samples.grouping === "merged"
          z: -2
          barConfig: samples.barConfig
          colors: BarsConfig.groupColors(samples.barConfig, 0.5)
          gradientStart: 0
          gradientEnd: 1
          startCap: samples.segments[0].startCap
          endCap: samples.segments[2].endCap
          width: samples.length
          height: samples.thickness + samples.reach
          y: samples.rowTop - samples.reach
          tabLimits: [null, null]
        }

        // Each widget's background, a powerline segment reaching back under
        // the one before (so drawn under it)
        Repeater {
          model: 3

          delegate: WidgetBackground {
            id: background
            required property int index
            readonly property var box: samples.boxes[background.index]
            readonly property var segment: samples.segments[background.index]
            readonly property BarIconWidget widget: samples.widgets[background.index]

            z: -1 - background.index / 3
            barConfig: samples.barConfig
            colors: background.widget.colors
            startCap: background.segment.startCap
            endCap: background.segment.endCap
            seamStart: background.segment.seamStart
            seamEnd: background.segment.seamEnd
            shownStart: background.segment.shownStart
            levelStartCap: background.segment.levelStartCap
            levelEndCap: background.segment.levelEndCap
            gradientStart: (background.box.x - background.box.back) / samples.length
            gradientEnd: (background.box.x + background.box.length) / samples.length
            // A split widget's parts, from the background's start (back
            // under the one before, and across from the tab's outer edge)
            splitAt: background.widget.splits ? background.box.back + background.box.lead + background.widget.splitAt : -1
            splitPart: background.widget.splits ? Qt.rect(background.box.back + background.box.lead + background.widget.splitPart.x, samples.reach + samples.shift + background.widget.splitPart.y, background.widget.splitPart.width, background.widget.splitPart.height) : Qt.rect(0, 0, 0, 0)
            x: background.box.x - background.box.back
            y: samples.rowTop - samples.reach
            width: background.box.length + background.box.back
            height: samples.thickness + samples.reach
          }
        }

        Repeater {
          model: samples.separators ? 2 : 0

          delegate: SeparatorMark {
            id: mark
            required property int index
            readonly property real center: samples.boxes[mark.index].x + samples.boxes[mark.index].length + samples.barConfig.groupSpacing / 2

            style: samples.look.separatorStyle
            color: Theme.resolveColor(samples.look.separatorColor)
            thickness: samples.look.separatorThickness
            length: BarLayout.dividerLength(mark.style, samples.thickness)
            x: mark.center - width / 2
            y: samples.rowTop + Math.round((samples.thickness - height) / 2) + samples.shift
          }
        }

        // The widgets: fixed content, each color Auto, so the bar's
        // gradient takes its place
        BarIconWidget {
          id: first
          readonly property var box: samples.boxes[0]
          icon: "wifi"
          showText: false
          properties: ({
              "backgroundColor": "base0D",
              "foregroundColor": "base00"
            })
          barConfig: samples.barConfig
          autoColors: ({
              "backgroundColor": "accent"
            })
          barOffset: first.box.x + first.box.lead
          barLength: samples.length
          x: first.box.x + first.box.lead
          y: samples.rowTop + samples.shift
        }

        BarIconWidget {
          id: second
          readonly property var box: samples.boxes[1]
          icon: "volume_up"
          text: "42%"
          properties: ({
              "backgroundColor": "base0B",
              "foregroundColor": "base00"
            })
          barConfig: samples.barConfig
          autoColors: ({
              "backgroundColor": "accent"
            })
          barOffset: second.box.x + second.box.lead
          barLength: samples.length
          x: second.box.x + second.box.lead
          y: samples.rowTop + samples.shift
        }

        BarIconWidget {
          id: third
          readonly property var box: samples.boxes[2]
          text: "12:30"
          properties: ({
              "backgroundColor": "base0E",
              "foregroundColor": "base00"
            })
          barConfig: samples.barConfig
          autoColors: ({
              "backgroundColor": "accent"
            })
          barOffset: third.box.x + third.box.lead
          barLength: samples.length
          x: third.box.x + third.box.lead
          y: samples.rowTop + samples.shift
        }
      }
    }
  }

  // The bar's own widgets, live, each on its background as the bar
  // editor's chips draw them (WidgetChip) but in the shape's caps, wrapping
  Loader {
    id: liveLoader
    width: parent.width
    active: root.liveConfig !== null
    sourceComponent: Flow {
      id: live

      readonly property var widgets: [].concat(...BarsConfig.sectionNames.map(section => root.liveConfig?.widgets?.[section] ?? [])).filter(widget => widget.visible !== false)

      // Each widget alone, in the shape's caps (BarShapes.segment): merged,
      // a run of one, on the run's background
      readonly property var segment: BarShapes.segment(root._shape, root._look.widgetEnds, "separate", false, 0, 1, root.liveConfig.thickness)
      readonly property bool merged: BarsConfig.groupingOf(root._look) === "merged"

      padding: Widget.smallPadding
      spacing: Widget.spacing

      Repeater {
        // By count: an edit's new config reaches each widget in place
        model: live.widgets.length

        delegate: Item {
          id: chip
          required property int index

          implicitWidth: Math.min(host.width, Widget.px(260))
          implicitHeight: host.height
          width: chip.implicitWidth
          height: chip.implicitHeight
          clip: true
          enabled: false

          WidgetBackground {
            visible: live.merged && host.hasBackground
            anchors.fill: host
            barConfig: root.liveConfig
            colors: BarsConfig.groupColors(root.liveConfig)
            startCap: live.segment.startCap
            endCap: live.segment.endCap
          }

          WidgetBackground {
            visible: host.hasBackground
            anchors.fill: host
            barConfig: root.liveConfig
            colors: host.background
            startCap: live.segment.startCap
            endCap: live.segment.endCap
            // A split widget's parts
            splitAt: host.split?.at ?? -1
            splitPart: host.split?.part ?? Qt.rect(0, 0, 0, 0)
            backgroundLevel: host.backgroundLevel
            backgroundLevelColor: host.backgroundLevelColor
          }

          BarWidgetHost {
            id: host
            preview: true
            panel: null
            screen: null
            barConfig: root.liveConfig
            widget: live.widgets[chip.index] ?? ({})
            leadInset: host.hasBackground ? root.liveConfig.innerPadding + live.segment.lead : 0
            trailInset: host.hasBackground ? root.liveConfig.innerPadding + live.segment.trail : 0
          }
        }
      }
    }
  }
}
