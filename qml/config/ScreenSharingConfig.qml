pragma Singleton
import QtQuick
import qs.services.core

// Reader for the ScreenSharing section: whether axiom's screen-share picker
// answers the portals (ScreenShareManager; the daemon reads the rest)
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.ScreenSharing

  readonly property bool enabled: _c.enabled
}
