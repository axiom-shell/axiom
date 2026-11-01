pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Drives section: drive notifications, what plugging in a
// removable drive does, and the drives left alone (DrivesManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Drives

  // Drive notifications (off: only an OSD showing `drive` says anything)
  readonly property bool notifications: _c.notifications
  // "ask" | "mount" | "nothing" (ask: only with notifications on)
  readonly property string onInsert: _c.onInsert
  // Warn when a mounted drive is unplugged without ejecting
  readonly property bool warnUnplugged: _c.warnUnplugged
  // Volume UUIDs or labels never handled or listed
  readonly property var ignore: _c.ignore
}
