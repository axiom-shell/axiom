pragma ComponentBehavior: Bound

import QtQuick

import qs.services.core
import qs.services.apps
import qs.config
import qs.components.bar.widgets.base

// The Tailscale bar widget: connected or not, and the tailnet's name, from
// TailscaleManager (acquired at the Tailscale section's interval). Left
// click runs the click command, right click checks again now.
BarIconWidget {
  id: root

  readonly property bool isConnected: TailscaleManager.connected
  readonly property string tailnetName: TailscaleManager.tailnetName

  readonly property var tailscaleRequest: ({
      "interval": TailscaleConfig.interval
    })
  onTailscaleRequestChanged: TailscaleManager.acquire(root, tailscaleRequest)
  Component.onCompleted: TailscaleManager.acquire(root, tailscaleRequest)
  Component.onDestruction: TailscaleManager.release(root)

  icon: isConnected ? properties.connectedIcon : properties.disconnectedIcon
  text: isConnected ? (properties.label || tailnetName) : ""
  showText: properties.showLabel

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
}
