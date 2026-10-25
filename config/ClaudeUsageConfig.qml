pragma Singleton
import QtQuick
import qs.services.core

// Reader for the ClaudeUsage section: the Claude Code logins every Claude
// usage widget reports on (see ClaudeUsageManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.ClaudeUsage

  // [{ id, label, configDir }], configDir as typed (may hold ~)
  readonly property var accounts: _c.items
  // How often usage is fetched (ms)
  readonly property int interval: _c.interval
}
