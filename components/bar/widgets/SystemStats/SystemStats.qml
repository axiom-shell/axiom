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
// GPU, no CPU sensor) are left out.
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
  readonly property var _enabled: root._metrics.filter(m => root.properties[m.option])

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

  // Live icon/value/level for one segment key
  function segmentData(key) {
    const p = properties;
    switch (key) {
    case "cpu":
      return {
        "icon": "memory",
        "value": `${SystemManager.cpuUsage}%`,
        "widest": "100%",
        "level": SystemManager.cpuUsage
      };
    case "mem":
      return {
        "icon": "memory_alt",
        "value": p.memoryFormat === "used" ? (SystemManager.memUsedBytes / Utils.bytesPerGiB).toFixed(1) + "G" : `${SystemManager.memUsage}%`,
        "widest": p.memoryFormat === "used" ? "00.0G" : "100%",
        "level": SystemManager.memUsage
      };
    case "temp":
      return {
        "icon": "thermometer",
        "value": `${SystemManager.cpuTemp}°`,
        "widest": "100°",
        "level": SystemManager.cpuTemp
      };
    case "gpu":
      return {
        "icon": "developer_board",
        "value": `${SystemManager.gpuUsage}%`,
        "widest": "100%",
        "level": SystemManager.gpuUsage
      };
    default:
      {
        const usage = SystemManager.disks[p.diskPath]?.usage ?? 0;
        return {
          "icon": "hard_drive",
          "value": `${usage}%`,
          "widest": "100%",
          "level": usage
        };
      }
    }
  }
  readonly property bool warning: segments.some(key => segmentData(key).level >= properties.warnThreshold)

  hasBackground: segments.length > 0
  accentColor: Theme.resolveColor(warning ? properties.warnColor : properties.backgroundColor)
  backgroundLevel: root.pill ? Math.min(1, root.segmentData(root.segments[0]).level / 100) : -1
  backgroundLevelColor: Qt.alpha(root.colors.icon, 0.35)
  // Colour the text by state only where it isn't the background already
  readonly property bool _textByState: root.appearance.colorText && root.colors.fill.a < 1
  readonly property color textColor: root._textByState ? root.accentColor : root.colors.text

  implicitWidth: box.implicitWidth
  implicitHeight: box.implicitHeight

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
    active: EdgeMenusConfig.opensOwnPopout(root.properties) && root.graphMetrics.length > 0
    extraData: ({
        "popoutMetrics": root.graphMetrics
      })
  }

  BaseWidget {
    id: box
    anchors.fill: parent
    isVertical: root.isVertical
    crossSize: root.barConfig.widgetSize
    padding: root.segments.length > 0 ? root.barConfig.widgetPadding : 0
    radius: root.barConfig.radius
    showBackground: false

    content: Grid {
      columns: root.isVertical ? 1 : Math.max(1, root.segments.length)
      spacing: root.isVertical ? root.barConfig.widgetSpacing : root.barConfig.widgetPadding
      horizontalItemAlignment: Grid.AlignHCenter
      verticalItemAlignment: Grid.AlignVCenter

      Repeater {
        model: root.segments

        // One icon + label each, laid out as every bar widget's is; on a
        // vertical bar the value small and upright under the icon
        delegate: IconTextWidget {
          id: segment
          required property var modelData
          readonly property var stat: root.segmentData(modelData)
          readonly property var metric: root._metrics.find(m => m.key === segment.modelData)
          // The disk keeps no history (a fill instead); stacked on a
          // vertical bar is a label
          readonly property string style: root.style === "sparkline" && segment.metric.history === "" ? "fill" : root.style === "stacked" && root.isVertical ? "label" : root.style

          isVertical: root.isVertical
          crossSize: root.barConfig.widgetSize
          padding: 0
          showBackground: false
          fontSize: root.barConfig.fontSize
          spacing: root.isVertical ? 0 : root.barConfig.widgetSpacing * 1.5
          textScale: root.isVertical ? 0.7 : 0.9
          uprightLabel: true
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
            crossSize: root.barConfig.widgetSize
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
