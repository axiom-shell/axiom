pragma Singleton
import QtQuick
import qs.services.core
import qs.components.methods

// Reader for the Notifications section (toasts and the history). Named
// NotificationsConfig because `Notifications` is a surface, module and bar
// widget type.
QtObject {
  readonly property var _c: ConfigManager.live.Notifications

  // The ScreenTarget toasts show on (see General.screensFor)
  readonly property var screen: _c.screen

  // Where the stack sits: a ScreenEdge, 0-1 along it, held off it, and the
  // gap when held (-1: Auto, ScreenEdgeManager.detachedGaps)
  readonly property int edge: ScreenEdge.fromConfig(_c.edge)
  readonly property real position: _c.position / 100
  readonly property bool detached: _c.detached
  readonly property int gap: _c.gap

  // "slide" | "fade" | "none", and the slide's edge ("auto" or an edge
  // name, see ToastMotion.slideEdge)
  readonly property string motionStyle: _c.motion.style
  readonly property string motionDirection: _c.motion.direction

  // Toasts
  readonly property int timeout: _c.timeout
  // Use a notification's own expireTimeout (0 = never) when it sets one,
  // and drop a notification its app withdraws from the history
  readonly property bool followApps: _c.followApps
  readonly property bool criticalStays: _c.criticalStays
  readonly property int maxToasts: _c.maxToasts
  readonly property int width: Widget.px(_c.width)
  readonly property bool quietFullscreen: _c.quietFullscreen

  // Do not disturb: on a daily schedule ("HH:MM"), and whether critical
  // ones toast through it
  readonly property var _dnd: _c.dnd
  readonly property bool dndSchedule: _dnd.schedule
  readonly property string dndStartAt: _dnd.startAt
  readonly property string dndEndAt: _dnd.endAt
  readonly property bool dndAllowCritical: _dnd.allowCritical

  // Per-app rules: [{ id, app, toasts, history, urgency ("app" | "low" |
  // "normal" | "critical"), timeout (ms, -1 for the default) }]
  readonly property var apps: _c.apps

  // History
  readonly property bool clearOnFocus: _c.clearOnFocus
  // Focus the app's window after running a clicked notification's action
  readonly property bool clickFocuses: _c.clickFocuses
  readonly property bool removeOnClick: _c.removeOnClick
  readonly property bool closeRemoves: _c.closeRemoves
  readonly property int maxEntries: _c.maxEntries
  // How old an entry may get (ms), 0 = keep forever
  readonly property real maxAge: _c.maxAge
}
