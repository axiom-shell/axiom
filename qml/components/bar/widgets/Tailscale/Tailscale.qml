pragma ComponentBehavior: Bound

import QtQuick

import qs.services.core
import qs.services.apps
import qs.config
import qs.components.hosts.popout
import qs.components.bar.widgets.base

// The Tailscale bar widget: connected or not, and the tailnet's name, from
// TailscaleManager (acquired at the Tailscale section's interval). Hovering
// opens the Tailscale popout; left click runs the click command, right
// click checks again now. Stacked: the label over this machine's address.
ValueStyleWidget {
  id: root

  readonly property bool isConnected: TailscaleManager.connected
  readonly property string tailnetName: TailscaleManager.tailnetName

  Component.onCompleted: TailscaleManager.acquire(root)
  Component.onDestruction: TailscaleManager.release(root)

  icon: isConnected ? properties.connectedIcon : properties.disconnectedIcon
  text: isConnected ? (properties.label || tailnetName) : ""
  labelShown: properties.showLabel
  subtext: isConnected ? TailscaleManager.ip : ""

  accentColor: Theme.resolveColor(isConnected ? properties.connectedColor : properties.disconnectedColor)

  iconScale: 1.1
  textScale: 0.9

  clickable: true
  acceptedButtons: Qt.LeftButton | Qt.RightButton
  onClicked: button => {
    if (button === Qt.RightButton)
      TailscaleManager.refresh();
    else
      CommandManager.runDetached(root.properties.clickCommand);
  }

  PopoutAnchor {
    hitArea: root.hitArea
    popoutName: "Tailscale"
    active: EdgeMenusConfig.opensOwnPopout(root.properties)
  }
}
