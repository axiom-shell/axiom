pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Session section: what starts with the compositor while
// axiom manages its config ({ recommendedEnv, env, autostart }).
QtObject {
  id: root

  readonly property var _c: ConfigManager.config.Session

  // Goes through a string so a reload that leaves it unchanged doesn't
  // rewrite the managed config
  readonly property string _sessionJson: JSON.stringify(_c)
  readonly property var session: JSON.parse(_sessionJson)
}
