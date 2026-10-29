pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.system
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The primary connection's kind and device. Hovering opens the Wi-Fi
// menu, middle click runs a command. Its display style draws the Wi-Fi
// signal, the download speed (sparkline) or the network's name.
ValueStyleWidget {
  id: root

  readonly property string iface: NetworkingManager.netInfo.device
  readonly property string kind: NetworkingManager.primaryKind
  readonly property bool connected: kind !== ""

  accentColor: Theme.resolveColor(connected ? properties.backgroundColor : properties.disconnectedColor)
  icon: getIcon()
  text: iface
  labelShown: properties.showName && iface !== ""
  // The Wi-Fi signal; none on a wire
  ratio: kind === "wifi" ? NetworkingManager.primarySignal / 100 : -1
  // The download speed, kept by SystemManager only while it's drawn
  readonly property bool graphed: root.appearance.style === "sparkline"
  history: graphed ? SystemManager.netRxHistory : null
  graphMax: Math.max(1, ...(root.history ?? []))
  styleText: NetworkingManager.primaryName
  subtext: NetworkingManager.netInfo.ip
  onGraphedChanged: root._acquire()
  Component.onCompleted: root._acquire()
  Component.onDestruction: SystemManager.release(root)
  function _acquire() {
    if (root.graphed)
      SystemManager.acquire(root, {
        "metrics": ["net"],
        "history": true
      });
    else
      SystemManager.release(root);
  }

  function getIcon() {
    switch (kind) {
    case "wifi":
      return "wifi";
    case "ethernet":
      return "lan";
    default:
      return NetworkingManager.available && !NetworkingManager.wifiEnabled ? "signal_wifi_0_bar" : "signal_wifi_off";
    }
  }

  clickable: root.properties.middleCommand !== ""
  acceptedButtons: Qt.MiddleButton
  onClicked: CommandManager.runDetached(root.properties.middleCommand)

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WifiNetworks"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
  }
}
