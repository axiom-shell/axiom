pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Icons section. (Named IconsConfig: `Icons` is shadowed in
// files importing Quickshell service modules.)
QtObject {
  readonly property var _c: ConfigManager.live.Icons

  // App name → icon path/URL for apps whose icon doesn't resolve
  readonly property var overrides: _c.overrides
}
