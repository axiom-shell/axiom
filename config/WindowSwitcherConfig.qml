pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Reader for the WindowSwitcher section (Alt+Tab). Named
// WindowSwitcherConfig because `WindowSwitcher` is the shell module type.
QtObject {
  readonly property var _c: ConfigManager.live.WindowSwitcher

  // all | monitor | workspace (DockLayout.inScope's scopes)
  readonly property string scope: _c.scope
  // Placed as the launcher is (LauncherConfig): a ScreenEdge, its centre's
  // position along it (0-1), and whether it floats off the edge
  // (`distance` 0-0.5 across the free screen: 0.5 centres it) or grows out
  // of it
  readonly property int edge: ScreenEdge.fromConfig(_c.edge)
  readonly property real position: _c.position / 100
  readonly property bool detached: _c.detached
  readonly property real distance: _c.distance / 100
  // leftToRight | rightToLeft | topToBottom | bottomToTop
  // (WindowOrder.tileGrid's orders)
  readonly property string order: _c.order
  readonly property bool previews: _c.previews
  readonly property int tileSize: Widget.px(_c.tileSize)
  readonly property int showDelay: _c.showDelay
  // The switch windows keys open the compositor's own switcher, where
  // axiom writes its config (the daemon's writer reads it)
  readonly property bool compositorSwitcher: _c.compositorSwitcher
}
