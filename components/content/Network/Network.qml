pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.config
import qs.services.apps
import qs.services.system
import qs.components.methods
import qs.components.reusable
import qs.components.content.parts
import qs.components.content.base

// The primary connection (name, IP, wifi signal), live throughput with a
// graph, and Tailscale's state when it's installed. A strip is one row over
// the graphs (opening the Wi-Fi networks over the grid); compact, the
// connection and its download rate.
Card {
  id: root

  readonly property var info: NetworkingManager.netInfo
  readonly property string kindIcon: root.info.kind === "wifi" ? "signal_wifi_4_bar" : root.info.kind === "ethernet" ? "lan" : "dns"
  // "Running 100.x.y.z", or "" when Tailscale isn't installed
  readonly property string tailscale: TailscaleManager.available ? (TailscaleManager.backendState + " " + TailscaleManager.ip).trim() : ""

  readonly property var tailscaleRequest: ({
      "interval": TailscaleConfig.interval
    })
  onTailscaleRequestChanged: TailscaleManager.acquire(root, tailscaleRequest)

  Component.onCompleted: {
    NetworkingManager.refreshIp();
    SystemManager.acquire(root, {
      "metrics": ["net"],
      "history": true,
      "interval": 1000
    });
    TailscaleManager.acquire(root, root.tailscaleRequest);
  }
  Component.onDestruction: {
    SystemManager.release(root);
    TailscaleManager.release(root);
  }

  // Short of room for the full layout (a strip): one row over the graphs
  readonly property bool strip: !root.compact && root.height < Appearance.fontSize * 10
  readonly property var rx: Utils.rateParts(SystemManager.netRx)

  fullMinWidth: Appearance.fontSize * 11
  fullMinHeight: Appearance.fontSize * 3

  // Download and upload, one graph over the other
  component Graphs: Item {
    id: graphs
    property real fade: 1
    Sparkline {
      anchors.fill: parent
      values: SystemManager.netRxHistory
      maxValue: 0
      lineColor: Theme.accentAlt
      fillOpacity: 0.2 * graphs.fade
      capacity: SystemManager.historyLength
    }
    Sparkline {
      anchors.fill: parent
      values: SystemManager.netTxHistory
      maxValue: 0
      lineColor: Theme.accent
      fillOpacity: 0.08 * graphs.fade
      lineWidth: 1.5
      showBaseline: false
      capacity: SystemManager.historyLength
    }
  }

  // Compact: the connection type, name and download rate
  compactContent: CompactFigure {
    icon: root.kindIcon
    value: root.info.kind !== "" ? root.rx[0] : ""
    unit: root.info.kind !== "" ? root.rx[1] : ""
    label: root.info.name || I18n.tr("Disconnected")
  }

  // A strip: the graphs faint behind the connection and its rates
  Graphs {
    visible: root.strip
    anchors.fill: parent
    anchors.margins: Appearance.borderWidth
    opacity: 0.5
    fade: 0.6
  }
  RowLayout {
    visible: root.strip
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing

    StyledIcon {
      text: root.kindIcon
      textColor: Theme.accent
      textSize: Appearance.fontSizeBy(2)
    }
    StyledText {
      Layout.fillWidth: true
      text: root.info.name || I18n.tr("Disconnected")
      elide: Text.ElideRight
      font.bold: true
    }
    RateLabel {
      rate: SystemManager.netRx
      textColor: Theme.accentAlt
    }
    RateLabel {
      visible: root.width > Appearance.fontSize * 22
      direction: "up"
      rate: SystemManager.netTx
      textColor: Theme.accent
    }
    ExpandButton {
      module: root
      type: NetworkingManager.available ? "WifiNetworks" : ""
    }
  }

  ColumnLayout {
    visible: !root.strip
    anchors.fill: parent
    anchors.margins: root.pad
    spacing: Widget.spacing / 2

    ModuleHeader {
      icon: root.kindIcon
      title: root.info.name || I18n.tr("Disconnected")
      StyledText {
        visible: root.info.kind === "wifi"
        text: `${root.info.signal}%`
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.7
      }
    }
    // Address and Tailscale on one line where there's room
    Flow {
      Layout.fillWidth: true
      spacing: Widget.spacing * 1.5
      StyledText {
        visible: root.info.ip !== ""
        text: root.info.ip
        textSize: Appearance.fontSizeBy(-2)
        opacity: 0.7
      }
      StyledText {
        visible: root.tailscale !== ""
        width: Math.min(implicitWidth, parent.width)
        elide: Text.ElideRight
        text: I18n.tr("Tailscale · {0}", root.tailscale)
        textSize: Appearance.fontSizeBy(-2)
        textColor: root.tailscale.startsWith("Running") ? Theme.success : Theme.foreground
        opacity: 0.8
      }
    }

    Graphs {
      Layout.fillWidth: true
      Layout.fillHeight: true
      Layout.topMargin: Widget.spacing / 2
    }

    RowLayout {
      Layout.fillWidth: true
      RateLabel {
        rate: SystemManager.netRx
        textColor: Theme.accentAlt
      }
      Item {
        Layout.fillWidth: true
      }
      RateLabel {
        direction: "up"
        rate: SystemManager.netTx
        textColor: Theme.accent
      }
    }
  }
}
