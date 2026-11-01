pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Drives section: where drive events show, what plugging in a
// removable drive does, and the drives left alone (DrivesManager).
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Drives

  // Where drive events show: "osd" (an OSD showing `drive`, else
  // notifications) | "notification" | "off" (DriveInfo.channel)
  readonly property string announce: _c.announce
  // "ask" (always a notification) | "mount" | "nothing"
  readonly property string onInsert: _c.onInsert
  // Warn when a mounted drive is unplugged without ejecting
  readonly property bool warnUnplugged: _c.warnUnplugged
  // Volume UUIDs or labels never handled or listed
  readonly property var ignore: _c.ignore
}
