pragma ComponentBehavior: Bound
import QtQuick

import qs.services.system
import qs.services.ui

// One VPN in a VPN list (VpnManager.rows): its kind, name and status, and
// connect / disconnect. Clicking the row toggles it. A password
// NetworkManager asks for shows in the shared prompt (VpnManager).
DeviceRow {
  id: row

  required property var vpn

  icon: VpnManager.kindIcon(row.vpn?.kind ?? "")
  title: row.vpn?.name ?? ""
  status: VpnManager.statusText(row.vpn)
  failed: (row.vpn?.error ?? "") !== ""
  connected: row.vpn?.state === "on"
  busy: VpnManager.busy(row.vpn)
  onActivated: {
    ShellManager.onScreen("vpn");
    VpnManager.toggle(row.vpn);
  }
  onConnectClicked: {
    ShellManager.onScreen("vpn");
    VpnManager.toggle(row.vpn);
  }
}
