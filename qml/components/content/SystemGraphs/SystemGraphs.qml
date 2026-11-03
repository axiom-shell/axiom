pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.system
import qs.components.methods
import qs.components.content.parts
import qs.components.content.base

// Live graphs of system metrics: the current value over a minute of
// history per metric. As an overlay card, in the grid that best fits the
// slot (compact shows the first metric's figure over its graph); as the
// SystemStats widget's popout, the metrics that widget shows.
// properties: { metrics: ["cpu", "mem", "gpu", "cpuTemp", "net"] }
Panel {
  id: root

  // A popout's metrics, from its anchor's payload (a card uses properties)
  property var popoutMetrics: null

  readonly property var knownMetrics: ["cpu", "mem", "gpu", "cpuTemp", "net"]
  // Depends on the config only (never on live values), so the graphs and
  // the SystemManager registration aren't rebuilt on every sample
  readonly property var metrics: (root.popoutMetrics ?? root.properties.metrics ?? ["cpu", "mem"]).filter(m => root.knownMetrics.includes(m))
  readonly property var shown: root.compact ? root.metrics.slice(0, 1) : root.metrics

  implicitWidth: Widget.px(root.columns > 1 ? 520 : 360)
  // A popout's graphs are a fixed height
  readonly property real graphHeight: Widget.px(56)

  // What each metric shows: label, value, unit, subtitle, history, scale
  function info(metric) {
    switch (metric) {
    case "cpu":
      return {
        "label": "CPU",
        "value": Math.round(SystemManager.cpuUsage),
        "unit": "%",
        "sub": SystemManager.hasCpuTemp ? `${SystemManager.cpuTemp}°C` : "",
        "history": SystemManager.cpuHistory,
        "max": 100,
        "color": Theme.accent
      };
    case "mem":
      return {
        "label": I18n.tr("Memory"),
        "value": Math.round(SystemManager.memUsage),
        "unit": "%",
        "sub": `${(SystemManager.memUsedBytes / Utils.bytesPerGiB).toFixed(1)} / ${(SystemManager.memTotalBytes / Utils.bytesPerGiB).toFixed(1)} GiB`,
        "history": SystemManager.memHistory,
        "max": 100,
        "color": Theme.success
      };
    case "gpu":
      return {
        "label": "GPU",
        "value": Math.round(SystemManager.gpuUsage),
        "unit": "%",
        "sub": SystemManager.gpuTemp > 0 ? `${SystemManager.gpuTemp}°C` : "",
        "history": SystemManager.gpuHistory,
        "max": 100,
        "color": Theme.info
      };
    case "cpuTemp":
      return {
        "label": I18n.tr("CPU temp"),
        "value": SystemManager.cpuTemp,
        "unit": "°C",
        "sub": "",
        "history": SystemManager.cpuTempHistory,
        "max": 100,
        "color": Theme.warning
      };
    case "net":
      {
        const rx = Utils.rateParts(SystemManager.netRx);
        const tx = Utils.rateParts(SystemManager.netTx);
        return {
          "label": I18n.tr("Network"),
          "value": rx[0],
          "unit": rx[1],
          "sub": `↑ ${tx[0]} ${tx[1]}`,
          "history": SystemManager.netRxHistory,
          "max": 0,
          "color": Theme.accentAlt
        };
      }
    }
    return null;
  }

  function register() {
    SystemManager.acquire(root, {
      "metrics": root.metrics,
      "history": true,
      "interval": 1000
    });
  }
  onMetricsChanged: register()
  Component.onCompleted: register()
  Component.onDestruction: SystemManager.release(root)

  // A popout: one column, two past three metrics. A card: the columns
  // whose panels come closest to a 2:1 figure-over-graph shape
  readonly property int columns: {
    const n = Math.max(1, root.shown.length);
    if (!root.embedded)
      return n > 3 ? 2 : 1;
    const w = root.innerWidth, h = root.innerHeight;
    let best = 1, bestErr = Infinity;
    for (let c = 1; c <= n; c++) {
      const r = Math.ceil(n / c);
      const aspect = ((w - (c - 1) * root.pad) / c) / ((h - (r - 1) * root.pad) / r);
      const err = Math.abs(Math.log(aspect / 2)) + (r * c - n) * 0.3;
      if (err < bestErr) {
        bestErr = err;
        best = c;
      }
    }
    return best;
  }

  // Compact: the first metric's figure centred over its graph
  compactContent: Item {
    readonly property var metric: root.info(root.shown[0])

    // Out to the card's edges, under the figure
    Sparkline {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: Appearance.borderWidth - root.pad
      height: (parent.height + root.pad * 2) * 0.45
      values: parent.metric?.history ?? []
      maxValue: parent.metric?.max ?? 100
      lineColor: parent.metric?.color ?? Theme.accent
      fillOpacity: 0.15
      showBaseline: false
      capacity: SystemManager.historyLength
    }

    CompactFigure {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: parent.height * 0.75
      value: String(parent.metric?.value ?? "")
      unit: parent.metric?.unit ?? ""
      label: parent.metric?.label ?? ""
      valueColor: parent.metric?.color ?? Theme.foreground
    }
  }

  ModuleHeader {
    visible: !root.embedded
    icon: "show_chart"
    title: I18n.tr("System")
  }

  GridLayout {
    Layout.fillWidth: true
    Layout.fillHeight: root.embedded
    columns: root.columns
    columnSpacing: root.pad
    rowSpacing: root.pad
    uniformCellWidths: true
    uniformCellHeights: true

    Repeater {
      model: root.compact ? [] : root.shown

      ColumnLayout {
        id: panel
        required property string modelData
        readonly property var metric: root.info(panel.modelData)
        Layout.fillWidth: true
        Layout.fillHeight: root.embedded
        Layout.preferredWidth: 1
        Layout.preferredHeight: root.embedded ? 1 : -1
        spacing: Widget.spacing / 2

        StatFigure {
          Layout.fillWidth: true
          label: panel.metric.sub !== "" ? `${panel.metric.label} · ${panel.metric.sub}` : panel.metric.label
          value: String(panel.metric.value)
          unit: panel.metric.unit
          valueColor: panel.metric.color
        }

        Sparkline {
          Layout.fillWidth: true
          Layout.fillHeight: root.embedded
          Layout.preferredHeight: root.embedded ? -1 : root.graphHeight
          Layout.minimumHeight: Appearance.fontSize
          values: panel.metric.history
          maxValue: panel.metric.max
          lineColor: panel.metric.color
          capacity: SystemManager.historyLength
        }
      }
    }
  }
}
