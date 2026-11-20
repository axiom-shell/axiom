pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

import qs.config
import qs.services.system
import qs.components.reusable

// What the internet sees (VpnManager.publicIp), to check the traffic goes
// through the VPN: its label, the address and a Check button (asks
// VpnConfig.publicIpUrl). `available` is whether it can show (a VPN up and
// a check URL); a host sets its own `visible`. `lineHeight` is the row's
// height.
RowLayout {
  id: root

  property real lineHeight: Widget.smallHeight
  readonly property bool available: VpnManager.anyActive && VpnConfig.publicIpUrl !== ""

  Layout.fillWidth: true
  Layout.leftMargin: Widget.padding
  Layout.preferredHeight: root.lineHeight
  spacing: Widget.spacing

  StyledLabel {
    text: I18n.tr("Public IP")
    role: "micro"
    tone: "muted"
  }
  StyledLabel {
    Layout.fillWidth: true
    text: VpnManager.publicIpBusy ? I18n.tr("Checking…") : VpnManager.publicIp || "—"
    overflow: "line"
    role: "micro"
  }
  FlatIconButton {
    size: root.lineHeight
    enabled: !VpnManager.publicIpBusy
    iconText: "travel_explore"
    iconSize: Style.iconXs
    tooltipText: I18n.tr("Check (asks {0})", VpnConfig.publicIpUrl)
    onClicked: VpnManager.checkPublicIp()
  }
}
