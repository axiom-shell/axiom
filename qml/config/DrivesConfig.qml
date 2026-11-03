pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Drives section: whether drive events notify, what plugging in a
// removable drive does, and the drives left alone (DrivesManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Drives

  // Drive events as notifications, where no OSD shows `drive`
  // (OSDConfig.routeOf)
  readonly property bool notify: _c.notify
  // "ask" (always a notification) | "mount" | "nothing"
  readonly property string onInsert: _c.onInsert
  // Warn when a mounted drive is unplugged without ejecting
  readonly property bool warnUnplugged: _c.warnUnplugged
  // Volume UUIDs or labels never handled or listed
  readonly property var ignore: _c.ignore
}
