pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Notifications section (toasts and the history). Named
// NotificationsConfig because `Notifications` is a surface, module and bar
// widget type.
QtObject {
  readonly property var _c: ConfigManager.config.Notifications

  // The ScreenTarget toasts show on (see General.screensFor)
  readonly property var screen: _c.screen

  // "topLeft" | "topRight" | "bottomLeft" | "bottomRight"
  readonly property string position: _c.position
  readonly property bool top: position === "topLeft" || position === "topRight"
  readonly property bool left: position === "topLeft" || position === "bottomLeft"

  // Gaps from the work area's edges, per side (only the corner's two apply)
  readonly property var _gaps: _c.gaps
  readonly property bool evenGaps: _gaps.even
  readonly property int gapTop: evenGaps ? _gaps.all : _gaps.top
  readonly property int gapBottom: evenGaps ? _gaps.all : _gaps.bottom
  readonly property int gapLeft: evenGaps ? _gaps.all : _gaps.left
  readonly property int gapRight: evenGaps ? _gaps.all : _gaps.right

  // Toasts
  readonly property int timeout: _c.timeout
  // Use a notification's own expireTimeout (0 = never) when it sets one
  readonly property bool appTimeouts: _c.appTimeouts
  readonly property bool criticalStays: _c.criticalStays
  readonly property int maxToasts: _c.maxToasts
  readonly property int width: Widget.px(_c.width)
  readonly property bool quietFullscreen: _c.quietFullscreen

  // History
  readonly property bool clearOnFocus: _c.clearOnFocus
  readonly property bool removeOnClick: _c.removeOnClick
  readonly property bool closeRemoves: _c.closeRemoves
  readonly property int maxEntries: _c.maxEntries
  // How old an entry may get (ms), 0 = keep forever
  readonly property real maxAge: _c.maxAge
}
