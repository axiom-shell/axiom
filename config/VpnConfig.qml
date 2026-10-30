pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Vpn section: what every VPN widget and module shares
// (see VpnManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Vpn

  // Notify when a VPN drops on its own
  readonly property bool notifyOnDrop: _c.notifyOnDrop
  // List Tailscale with NetworkManager's VPNs
  readonly property bool showTailscale: _c.showTailscale
  // What Edit connections runs ("" hides it)
  readonly property string editorCommand: _c.editorCommand
}
