pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.components.methods
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// CPU / memory / temperature / GPU / disk readouts from SystemManager, one
// segment per metric switched on (`items`, WidgetSegments) in the display
// style (docs/dev/bar/display-styles.md). The box takes the worst state and
// only a hot metric is in the warning colour; a metric the machine can't
// report (no GPU, no CPU sensor) is hidden. Drawn one box per metric (Boxes:
// One per item), each box is its one metric.
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
  function _metric(key) {
    return root._metrics.find(m => m.key === key);
  }

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

  // Short names, stacked under the value
  // I18n.tr("CPU") I18n.tr("RAM") I18n.tr("Temp") I18n.tr("GPU") I18n.tr("Disk")
  readonly property var _captions: ({
      "cpu": "CPU",
      "mem": "RAM",
      "temp": "Temp",
      "gpu": "GPU",
      "disk": "Disk"
    })

  // Live icon/value/level for one segment key
  function _metricData(key) {
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
  // Its metrics from config, the ones switched on (BarBoxes' ids:
  // x-boxItems): the template counts them. One the machine can't
  // report is a hidden segment, never left out, so the count stays config's.
  items: root._metrics.filter(m => root.properties[m.option]).map(m => m.key)

  // The shown ones this machine reports, as a string: it notifies only when
  // the set changes, not on every sample (disk reads the live disks map)
  readonly property string _reported: root.shownItems.filter(k => root._reportable(k)).join(",")
  readonly property var _reportedKeys: root._reported === "" ? [] : root._reported.split(",")

  hidden: root._reported === ""

  // Hot: at or above the warning threshold. The box takes the worst state
  // (P6: "SystemStats colours only the hot metric (the box takes the worst state).")
  function _hot(key) {
    return root._metricData(key).level >= root.properties.warnThreshold;
  }
  readonly property bool warning: root._reportedKeys.some(k => root._hot(k))
  accentField: root.warning ? "warnColor" : "backgroundColor"

  // Pill fills the whole box: only with one metric shown, else a fill
  appearance: root.properties.appearance.style === "pill" && root._reportedKeys.length !== 1 ? Object.assign({}, root.properties.appearance, {
    "style": "fill"
  }) : root.properties.appearance
  // The pill's level: its one metric's (the template's pill level)
  ratio: root.appearance.style === "pill" ? Math.max(0, root._metricData(root._reportedKeys[0]).level / 100) : -1

  segmentData: key => {
    const stat = root._metricData(key);
    const metric = root._metric(key);
    return {
      "icon": stat.icon,
      "text": stat.value,
      "minimumText": stat.widest,
      "ratio": Math.max(0, stat.level / 100),
      "history": metric.history !== "" ? (SystemManager[metric.history] ?? []) : null,
      "graphMin": 0,
      "graphMax": 100,
      "caption": I18n.tr(root._captions[key]),
      // In the box's colours where it matches the box's state, else in the
      // usual colour: a cool metric in a warning box
      "field": root.warning && !root._hot(key) ? "backgroundColor" : "",
      "hidden": !root._reportable(key)
    };
  }

  // Ask only for what's shown; re-acquiring replaces the old request
  readonly property var statsRequest: ({
      "interval": root.properties.interval,
      "metrics": root.shownItems.map(k => root._metric(k).metric),
      "diskPaths": root.shownItems.includes("disk") ? [root.properties.diskPath] : [],
      "history": root.properties.appearance.style === "sparkline"
    })
  onStatsRequestChanged: SystemManager.acquire(root, statsRequest)
  Component.onCompleted: SystemManager.acquire(root, statsRequest)
  Component.onDestruction: SystemManager.release(root)

  // The popout graphs what the bar shows. `graphed` is checked first, so
  // this never reads the disks map and stays from config and what the
  // machine can report only
  readonly property var graphMetrics: root.shownItems.filter(k => root._metric(k).graphed && root._reportable(k)).map(k => root._metric(k).metric)

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "SystemGraphs"
    active: MenusConfig.opensOwnPopout(root.properties) && root.graphMetrics.length > 0
    extraData: ({
        "popoutMetrics": root.graphMetrics
      })
  }
}
