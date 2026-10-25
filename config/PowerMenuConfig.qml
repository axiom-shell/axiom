pragma Singleton
import QtQuick
import qs.services.core

// Reader for the PowerMenu section. Named PowerMenuConfig because
// `PowerMenu` is the surface type.
QtObject {
  readonly property var _c: ConfigManager.config.PowerMenu

  // The ScreenTarget it opens on (see General.screensFor)
  readonly property var screen: _c.screen
  // Session actions shown, in order
  readonly property var actions: _c.actions
  // Destructive actions ask for a second press
  readonly property bool confirm: _c.confirm
  readonly property int tileSize: Widget.px(_c.tileSize)
  readonly property bool showHeader: _c.showHeader
  readonly property bool showHint: _c.showHint
  // Dim the screen behind it
  readonly property bool showBackdrop: _c.showBackdrop
  // 0-1 opacity of the backdrop
  readonly property real backdrop: _c.backdrop / 100
}
