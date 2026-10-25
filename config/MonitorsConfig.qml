pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Monitors section: the monitor profiles ({ id, name,
// outputs: [MonitorRule] }), edited on the Monitors page (MonitorManager) and
// applied by the compositor's config writer
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Monitors

  // Goes through a string so a reload that leaves them unchanged doesn't
  // re-apply them
  readonly property string _profilesJson: JSON.stringify(_c.items)
  readonly property var profiles: JSON.parse(_profilesJson)
}
