pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Polkit section: whether axiom is the session's polkit
// agent (PolkitManager)
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Polkit

  readonly property bool enabled: _c.enabled
}
