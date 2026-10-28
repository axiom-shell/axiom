pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Monitors section: the monitor profiles ({ id, name,
// outputs: [MonitorRule] }), edited on the Monitors page (MonitorManager) and
// applied on each hotplug by the daemon
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Monitors

  // Goes through a string so a config change leaving them unchanged doesn't
  // notify their readers
  readonly property string _profilesJson: JSON.stringify(_c.items)
  readonly property var profiles: JSON.parse(_profilesJson)
}
