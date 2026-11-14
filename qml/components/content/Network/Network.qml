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
// graph, and the VPNs up (VpnManager, Tailscale among them unless
// VpnConfig.showTailscale is off: then Tailscale's own state). A strip is one row over
// the graphs (opening the Wi-Fi networks over the grid); compact, the
// connection and its download rate.
Card {
  id: root

  readonly property var info: NetworkingManager.netInfo
  readonly property string kindIcon: root.info.kind === "wifi" ? "signal_wifi_4_bar" : root.info.kind === "ethernet" ? "lan" : "dns"
  // "Connected 100.x.y.z", or "" when Tailscale isn't installed or is a
  // VPN row
  readonly property string tailscale: TailscaleManager.available && !VpnConfig.showTailscale ? (TailscaleManager.stateText + " " + TailscaleManager.ip).trim() : ""
  // "Work, Home", or "" with no VPN up
  readonly property string vpns: VpnManager.activeRows.map(r => r.name).join(", ")

  Component.onCompleted: {
    NetworkingManager.refreshIp();
    SystemManager.acquire(root, {
      "metrics": ["net"],
      "history": true,
      "interval": 1000
    });
    TailscaleManager.acquire(root);
    VpnManager.acquire(root);
  }
  Component.onDestruction: {
    SystemManager.release(root);
    TailscaleManager.release(root);
    VpnManager.release(root);
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
      lineColor: Style.accentAlt
      fillOpacity: 0.2 * graphs.fade // style-exempt: the chart fill fades its data colour
      capacity: SystemManager.historyLength
    }
    Sparkline {
      anchors.fill: parent
      values: SystemManager.netTxHistory
      maxValue: 0
      lineColor: Style.accent
      fillOpacity: 0.08 * graphs.fade // style-exempt: the chart fill fades its data colour
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
  Loader {
    anchors.fill: parent
    active: root.strip

    sourceComponent: Item {
      Graphs {
        anchors.fill: parent
        anchors.margins: Appearance.borderWidth
        opacity: 0.5 // style-exempt: backdrop graphs behind the figures
        fade: 0.6
      }
      RowLayout {
        anchors.fill: parent
        anchors.margins: root.pad
        spacing: Widget.spacing

        StyledIcon {
          text: root.kindIcon
          size: "md"
          tone: "accent"
        }
        StyledLabel {
          Layout.fillWidth: true
          text: root.info.name || I18n.tr("Disconnected")
          overflow: "line"
          font.weight: Style.weightStrong
        }
        RateLabel {
          rate: SystemManager.netRx
          textColor: Style.accentAlt
        }
        RateLabel {
          visible: root.width > Appearance.fontSize * 22
          direction: "up"
          rate: SystemManager.netTx
          textColor: Style.accent
        }
        ExpandButton {
          module: root
          type: NetworkingManager.available ? "WifiNetworks" : ""
        }
      }
    }
  }

  Loader {
    anchors.fill: parent
    anchors.margins: root.pad
    active: !root.strip

    sourceComponent: ColumnLayout {
      spacing: Widget.spacing / 2

      ModuleHeader {
        icon: root.kindIcon
        title: root.info.name || I18n.tr("Disconnected")
        StyledText {
          visible: root.info.kind === "wifi"
          text: `${root.info.signal}%`
          role: "caption"
          tone: "faint"
        }
      }
      // Address, the VPNs and Tailscale on one line where there's room
      Flow {
        Layout.fillWidth: true
        spacing: Widget.spacing * 1.5
        StyledText {
          visible: root.info.ip !== ""
          text: root.info.ip
          role: "caption"
          tone: "faint"
        }
        StyledText {
          visible: root.vpns !== ""
          width: Math.min(implicitWidth, parent.width)
          overflow: "line"
          text: I18n.tr("VPN · {0}", root.vpns)
          role: "caption"
          tone: "success"
        }
        StyledText {
          visible: root.tailscale !== ""
          width: Math.min(implicitWidth, parent.width)
          overflow: "line"
          text: I18n.tr("Tailscale · {0}", root.tailscale)
          role: "caption"
          tone: TailscaleManager.connected ? "success" : "muted"
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
          textColor: Style.accentAlt
        }
        Item {
          Layout.fillWidth: true
        }
        RateLabel {
          direction: "up"
          rate: SystemManager.netTx
          textColor: Style.accent
        }
      }
    }
  }
}
