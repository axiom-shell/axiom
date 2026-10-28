pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Todo section: how every todo widget and module shows the
// list (the items are TodoManager's, in the data folder).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Todo

  readonly property bool showCompleted: _c.showCompleted
}
