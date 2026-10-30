pragma ComponentBehavior: Bound
import QtQuick

import qs.config
import qs.services.core
import qs.services.system
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// Whether a VPN is up, and its name (VpnManager: NetworkManager's VPNs,
// and Tailscale). Hovering opens the VPN popout; left click connects or
// disconnects the VPN used last, middle click runs a command. Stacked:
// the name over its address.
ValueStyleWidget {
  id: root

  readonly property var vpn: VpnManager.primary
  readonly property bool connected: vpn !== null

  Component.onCompleted: VpnManager.acquire(root)
  Component.onDestruction: VpnManager.release(root)

  hidden: properties.hideWhenOff && !connected
  icon: connected ? "vpn_lock" : "vpn_key_off"
  text: connected ? vpn.name : ""
  labelShown: properties.showName && connected
  subtext: connected ? vpn.ipv4 : ""
  accentColor: Theme.resolveColor(connected ? properties.connectedColor : properties.disconnectedColor)

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
  onClicked: button => {
    if (button === Qt.MiddleButton)
      CommandManager.runDetached(root.properties.middleCommand);
    else
      VpnManager.toggleLast();
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "VpnConnections"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
  }
}
