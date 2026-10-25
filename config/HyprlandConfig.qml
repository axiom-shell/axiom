pragma Singleton
import QtQuick
import qs.services.core

// Reader for Compositor.hyprland: what axiom writes into Hyprland
// (the daemon's Hyprland writer). Named HyprlandConfig because `Hyprland` is
// Quickshell's singleton.
QtObject {
  readonly property var _c: ConfigManager.config.Compositor.hyprland

  // The managed hyprland.lua's own settings (layout, animations, ...)
  readonly property string _managedJson: JSON.stringify(_c)
  readonly property var managed: JSON.parse(_managedJson)
}
