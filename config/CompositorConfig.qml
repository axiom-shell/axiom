pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Compositor section: how axiom sets the compositor up
// (CompositorConfigManager)
QtObject {
  readonly property var _c: ConfigManager.config.Compositor

  // "detached" | "included" | "managed"
  readonly property string mode: _c.mode
  readonly property bool requiredSettings: _c.requiredSettings
}
