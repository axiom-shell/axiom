pragma Singleton
import QtQuick
import qs.services.core

// Reader for the WorkspaceOverlay section (the full-screen workspace
// overview). Named WorkspaceOverlayConfig because `WorkspaceOverlay` is the
// shell module type.
QtObject {
  readonly property var _c: ConfigManager.live.WorkspaceOverlay

  // Cells show the monitor's wallpaper, else `color`
  readonly property bool wallpaper: _c.background === "wallpaper"
  readonly property color color: Theme.resolveColor(_c.color)
  // 0-1: how dark workspaces other than the active one are drawn
  readonly property real dimInactive: _c.dimInactive / 100
  // 0-1 of the screen the grid may take
  readonly property real size: _c.size / 100
  // 0-1 opacity of the backdrop
  readonly property real backdrop: _c.backdrop / 100
  readonly property bool showNumbers: _c.showNumbers
  readonly property bool showTitles: _c.showTitles
  readonly property bool showHint: _c.showHint
}
