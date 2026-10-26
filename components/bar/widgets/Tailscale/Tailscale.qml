pragma ComponentBehavior: Bound

import QtQuick

import qs.services.apps
import qs.services.system
import qs.config
import qs.components.bar.widgets.base

// The Tailscale bar widget: connected or not, and the tailnet's name, from
// TailscaleManager (acquired at the widget's interval); a click notifies it.
BarIconWidget {
  id: root

  readonly property bool isConnected: TailscaleManager.connected
  readonly property string tailnetName: TailscaleManager.tailnetName

  readonly property var tailscaleRequest: ({
      "interval": root.properties.interval
    })
  onTailscaleRequestChanged: TailscaleManager.acquire(root, tailscaleRequest)
  Component.onCompleted: TailscaleManager.acquire(root, tailscaleRequest)
  Component.onDestruction: TailscaleManager.release(root)

  icon: isConnected ? "shield_lock" : "signal_disconnected"
  text: isConnected ? (properties.label || tailnetName) : ""
  showText: properties.showLabel

  accentColor: Theme.resolveColor(isConnected ? properties.connectedColor : properties.disconnectedColor)

  iconScale: 1.1
  textScale: 0.9

  clickable: true
  onClicked: NotificationManager.sendNotification("axiom", "Tailscale", root.isConnected ? I18n.tr("Connected to: {0}", root.tailnetName) : I18n.tr("Disconnected"))
}
