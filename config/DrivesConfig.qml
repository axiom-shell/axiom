pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Drives section: what plugging in a removable drive does,
// and the drives left alone (DrivesManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Drives

  // "ask" | "mount" | "nothing"
  readonly property string onInsert: _c.onInsert
  // Open the folder after every mount
  readonly property bool openAfterMount: _c.openAfterMount
  // Volume UUIDs or labels never handled or listed
  readonly property var ignore: _c.ignore
}
