pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Tailscale section: what every Tailscale widget and module
// shares (see TailscaleManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Tailscale

  // How often `tailscale status` is read (ms)
  readonly property int interval: _c.interval
  // List offline peers after the online ones
  readonly property bool showOffline: _c.showOffline
  // Show the Connect / Disconnect buttons
  readonly property bool actions: _c.actions
}
