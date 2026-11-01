pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Idle section. The axiom daemon reads the rest of it
// itself (internal/idle) and runs the steps; the shell only needs to know
// whether it's on, and caffeine's warning.
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Idle

  readonly property bool enabled: _c.enabled
  // A notification before a caffeine timer runs out (IdleManager)
  readonly property bool caffeineWarning: _c.caffeineWarning
}
