pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.components.methods
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// CPU / memory / temperature / GPU / disk readouts from SystemManager, one
// segment per enabled metric in the display style (a ValueGraphic each:
// docs/dev/bar/display-styles.md). Metrics the machine can't report (no
// GPU, no CPU sensor) are left out. Drawn one box per metric (Boxes: One
// per item), each box is this widget showing its one metric (`box`),
// which splits and pills as any value widget does.
BarWidget {
  id: root

  // Every metric: the option that shows it, SystemManager's name for it,
  // whether the popout graphs it (disk has no history), and the
  // SystemManager list its sparkline draws
  readonly property var _metrics: [
    {
      "key": "cpu",
      "history": "cpuHistory",
      "option": "showCpu",
      "metric": "cpu",
      "graphed": true
    },
    {
      "key": "mem",
      "history": "memHistory",
      "option": "showMemory",
      "metric": "mem",
      "graphed": true
    },
    {
      "key": "temp",
      "history": "cpuTempHistory",
      "option": "showTemp",
      "metric": "cpuTemp",
      "graphed": true
    },
    {
      "key": "gpu",
      "history": "gpuHistory",
      "option": "showGpu",
      "metric": "gpu",
      "graphed": true
    },
    {
      "key": "disk",
      "history": "",
      "option": "showDisk",
      "metric": "disk",
      "graphed": false
    }
  ]
  // Its one metric when drawn one box per metric, else every one switched on
  readonly property var _enabled: root._metrics.filter(m => root.box !== "" ? m.key === root.box : root.properties[m.option])

  // Whether this machine can report a metric. Disk reads the live disks
  // map, so only call it where re-evaluating on every sample is harmless.
  function _reportable(key) {
    switch (key) {
    case "temp":
      return SystemManager.hasCpuTemp;
    case "gpu":
      return SystemManager.hasGpu;
    case "disk":
      return !!SystemManager.disks[root.properties.diskPath];
    default:
      return true;
    }
  }

  // Which segments show, from config and what the machine can report. A
  // string, so it only notifies when the set changes: a model rebuilt on
  // every sample would recreate the delegates many times a second.
  readonly property string segmentKeys: root._enabled.filter(m => root._reportable(m.key)).map(m => m.key).join(",")
  readonly property var segments: segmentKeys === "" ? [] : segmentKeys.split(",")

  // Short names, stacked under the value
  // I18n.tr("CPU") I18n.tr("RAM") I18n.tr("Temp") I18n.tr("GPU") I18n.tr("Disk")
  readonly property var _captions: ({
      "cpu": "CPU",
      "mem": "RAM",
      "temp": "Temp",
      "gpu": "GPU",
      "disk": "Disk"
    })

  readonly property var appearance: properties.appearance
  // Pill fills the whole widget's background: only with one metric
  readonly property string style: appearance.style === "pill" && segments.length !== 1 ? "fill" : appearance.style
  readonly property bool pill: style === "pill"
  // The style a metric's segment draws as: the disk keeps no history (a
  // fill instead); every segment has a value
  function segmentStyle(key) {
    return ValueGraphics.resolvedStyle(root.style, root.isVertical, root._metrics.find(m => m.key === key).history !== "", 0);
  }
  // The room across inside its box, which stacked's lines fit in
  readonly property real _boxRoom: ValueGraphics.boxRoom(root.barConfig.thickness, root.barConfig.look.shape)
  // A line, or the graphic reaching furthest across the bar of those its
  // shown metrics draw
  contentAcross: Math.max(root.barConfig.fontSize, ...root.segments.map(key => ValueGraphics.across(root.segmentStyle(key), root.isVertical, root.barConfig.thickness, root.barConfig.fontSize, root._boxRoom)))

  // Live icon/value/level for one segment key
  function segmentData(key) {
    const p = properties;
    switch (key) {
    case "cpu":
      return {
        "icon": "memory",
        "value": `${SystemManager.cpuUsage}%`,
        "widest": "00%",
        "level": SystemManager.cpuUsage
      };
    case "mem":
      {
        // Whole GiB from 10 upright on a vertical bar: "15.6G" is wider
        // than its column
        const gib = SystemManager.memUsedBytes / Utils.bytesPerGiB;
        return {
          "icon": "memory_alt",
          "value": p.memoryFormat === "used" ? gib.toFixed(root.isVertical && gib >= 10 ? 0 : 1) + "G" : `${SystemManager.memUsage}%`,
          "widest": p.memoryFormat === "used" ? "00.0G" : "00%",
          "level": SystemManager.memUsage
        };
      }
    case "temp":
      return {
        "icon": "thermometer",
        "value": `${SystemManager.cpuTemp}°`,
        "widest": "00°",
        "level": SystemManager.cpuTemp
      };
    case "gpu":
      return {
        "icon": "developer_board",
        "value": `${SystemManager.gpuUsage}%`,
        "widest": "00%",
        "level": SystemManager.gpuUsage
      };
    default:
      {
        const usage = SystemManager.disks[p.diskPath]?.usage ?? 0;
        return {
          "icon": "hard_drive",
          "value": `${usage}%`,
          "widest": "00%",
          "level": usage
        };
      }
    }
  }
  readonly property bool warning: segments.some(key => segmentData(key).level >= properties.warnThreshold)

  hasBackground: segments.length > 0
  accentField: warning ? "warnColor" : "backgroundColor"
  backgroundLevel: root.pill ? Math.min(1, root.segmentData(root.segments[0]).level / 100) : -1
  backgroundLevelColor: BarWidgetStyle.levelColor(root.colors)
  readonly property bool _textByState: BarWidgetStyle.textByState(root.colors, root.appearance)
  readonly property color textColor: root._textByState ? root.accentColor : root.colors.text

  implicitWidth: stack.implicitWidth
  implicitHeight: stack.implicitHeight

  // With one metric, its icon part and label set apart on a split bar, as
  // the metric's segment reports them (IconTextWidget.splits), moved from
  // the segment into the widget: the box's padding, centred in it
  // (Its first segment registers itself: the segments are in a component
  // of their own, out of reach of an id)
  property IconTextWidget _first: null
  readonly property IconTextWidget _single: root.segments.length === 1 ? root._first : null
  readonly property real _singleStart: root._single ? Math.round(((root.isVertical ? root.height : root.width) - (root.isVertical ? root._single.height : root._single.width)) / 2) : 0
  readonly property real _singleAcross: root._single ? Math.round(((root.isVertical ? root.width : root.height) - (root.isVertical ? root._single.width : root._single.height)) / 2) : 0
  splits: root._single?.splits ?? false
  // `_single` itself tested: it goes null before `splits` follows
  splitAt: root._single?.splits ? root._singleStart + root._single.splitAt : -1
  splitPart: root._single?.splits ? (root.isVertical ? Qt.rect(root._singleAcross + root._single.splitPart.x, root._singleStart + root._single.splitPart.y, root._single.splitPart.width, root._single.splitPart.height) : Qt.rect(root._singleStart + root._single.splitPart.x, root._singleAcross + root._single.splitPart.y, root._single.splitPart.width, root._single.splitPart.height)) : Qt.rect(0, 0, 0, 0)

  // Ask only for what's shown; re-acquiring replaces the old request
  readonly property var statsRequest: ({
      "interval": root.properties.interval,
      "metrics": root._enabled.map(m => m.metric),
      "diskPaths": root.properties.showDisk ? [root.properties.diskPath] : [],
      "history": root.style === "sparkline"
    })
  onStatsRequestChanged: SystemManager.acquire(root, statsRequest)
  Component.onCompleted: SystemManager.acquire(root, statsRequest)
  Component.onDestruction: SystemManager.release(root)

  // The popout graphs what the bar shows. `graphed` is checked first, so
  // this never reads the disks map and stays from config and what the
  // machine can report only, as with segmentKeys
  readonly property var graphMetrics: root._enabled.filter(m => m.graphed && root._reportable(m.key)).map(m => m.metric)

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "SystemGraphs"
    active: MenusConfig.opensOwnPopout(root.properties) && root.graphMetrics.length > 0
    extraData: ({
        "popoutMetrics": root.graphMetrics
      })
  }

  BaseWidget {
    id: stack
    anchors.fill: parent
    isVertical: root.isVertical
    crossSize: root.barConfig.thickness
    padding: root.segments.length > 0 ? root.barConfig.innerPadding : 0

    content: Grid {
      columns: root.isVertical ? 1 : Math.max(1, root.segments.length)
      spacing: root.isVertical ? root.barConfig.innerGap : root.barConfig.innerPadding
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      Repeater {
        model: root.segments

        // One icon + label each, laid out as every bar widget's is; on a
        // vertical bar the value small and upright under the icon
        delegate: IconTextWidget {
          id: segment
          required property var modelData
          required property int index
          Component.onCompleted: if (segment.index === 0)
            root._first = segment
          Component.onDestruction: if (root._first === segment)
            root._first = null
          readonly property var stat: root.segmentData(modelData)
          readonly property var metric: root._metrics.find(m => m.key === segment.modelData)
          readonly property string style: root.segmentStyle(segment.modelData)

          isVertical: root.isVertical
          crossSize: root.barConfig.thickness
          padding: 0
          fontSize: root.barConfig.fontSize
          spacing: root.isVertical ? 0 : root.barConfig.innerGap * 1.5
          textScale: root.isVertical ? 0.7 : 0.9
          uprightLabel: true
          // Its icon part and label apart on a split bar, alone in its box
          splitRoom: root.segments.length === 1 ? root.barConfig.splitRoom : -1
          icon: segment.stat.icon
          text: segment.stat.value
          minimumText: segment.stat.widest
          showText: segment.style !== "icon" && segment.style !== "stacked"
          foregroundColor: root.textColor
          iconColor: root._textByState ? root.accentColor : root.colors.icon
          leadLength: graphic.drawn ? graphic.length : 0
          leadAfterIcon: graphic.afterIcon

          ValueGraphic {
            id: graphic
            parent: segment.lead
            anchors.fill: parent
            style: segment.style
            ratio: Math.max(0, Math.min(1, segment.stat.level / 100))
            history: segment.style === "sparkline" ? SystemManager[segment.metric.history] : []
            graphMin: 0
            graphMax: 100
            text: segment.stat.value
            minimumText: segment.stat.widest
            // Stacked: the value over its name, where the value goes
            subtext: I18n.tr(root._captions[segment.modelData])
            segmentCount: root.appearance.segments
            preferredLength: root.appearance.width
            vertical: root.isVertical
            crossSize: root.barConfig.thickness
            room: root._boxRoom
            fontSize: root.barConfig.fontSize
            middle: segment.iconMiddle
            color: root.colors.icon
            textColor: root.textColor
          }
        }
      }
    }
  }
}
