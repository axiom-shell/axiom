pragma Singleton
import QtQuick
import qs.services.core

// Reader for the WindowSwitcher section (Alt+Tab). Named
// WindowSwitcherConfig because `WindowSwitcher` is the shell module type.
QtObject {
  readonly property var _c: ConfigManager.config.WindowSwitcher

  // all | monitor | workspace (DockLayout.inScope's scopes)
  readonly property string scope: _c.scope
  readonly property bool previews: _c.previews
  readonly property int tileSize: Widget.px(_c.tileSize)
  readonly property int showDelay: _c.showDelay
}
