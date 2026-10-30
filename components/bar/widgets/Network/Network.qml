pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.system
import qs.components.reusable
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The primary connection's kind and device, with a lock on the icon while
// a VPN is up (showVpn). Hovering opens the Wi-Fi menu, middle click runs
// a command. Its display style draws the Wi-Fi signal, the download speed
// (sparkline) or the network's name (and the VPN's).
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
  readonly property var vpn: root.properties.showVpn ? VpnManager.primary : null
  styleText: root.vpn ? I18n.tr("{0} · {1}", NetworkingManager.primaryName, root.vpn.name) : NetworkingManager.primaryName
  subtext: NetworkingManager.netInfo.ip
  onGraphedChanged: root._acquire()
  Component.onCompleted: {
    root._acquire();
    root._acquireVpn();
  }
  Component.onDestruction: {
    SystemManager.release(root);
    VpnManager.release(root);
  }
  readonly property bool _vpnShown: root.properties.showVpn
  on_VpnShownChanged: root._acquireVpn()
  function _acquireVpn() {
    if (root._vpnShown)
      VpnManager.acquire(root);
    else
      VpnManager.release(root);
  }
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

  // On the icon's bottom-right corner (wherever the label and style put
  // the icon), drawn in its host (where the widget sits at 0, 0) as the
  // widget clips to its box (BaseWidget), like the notification bell's
  // badge. None while the icon isn't shown.
  StyledIcon {
    parent: root.parent
    visible: opacity > 0
    opacity: root.vpn !== null && root.iconRect.width > 0 ? 1 : 0
    x: Math.round(root.iconRect.x + root.iconRect.width - width * 0.6)
    y: Math.round(root.iconRect.y + root.iconRect.height - height * 0.8)
    text: "lock"
    fill: 1
    textSize: root.fontSize - 5
    textColor: Theme.resolveColor(root.properties.vpnColor)

    Glide on opacity {}
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "WifiNetworks"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
    extraData: ({
        "vpnShown": root.properties.popoutVpn
      })
  }
}
