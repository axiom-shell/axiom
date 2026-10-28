pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Popouts section: behaviour shared by bar popouts and
// screen-edge popouts. (Named PopoutsConfig because `Popouts` is the bar
// popout wrapper type.)
QtObject {
  readonly property var _c: ConfigManager.live.Popouts

  readonly property int openDelay: _c.timing.openDelay
  readonly property int dismissDelay: _c.timing.closeDelay
  readonly property int edgeTriggerSize: _c.trigger.size
  // Space between a popout's box (inside its stroke) and its content
  readonly property int padding: Widget.px(_c.padding)
}
