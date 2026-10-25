pragma Singleton
import QtQuick
import qs.services.core

// Reader for the SelfUpdate section (see SelfUpdateManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.SelfUpdate

  // "auto" | "notify" | "off"
  readonly property string mode: _c.mode
  // "tags" (releases) | "main" (the main branch)
  readonly property string channel: _c.channel
}
