pragma ComponentBehavior: Bound
import QtQuick

import qs.services.apps
import qs.config
import qs.components.methods
import qs.services.ui
import qs.components.bar.widgets.base

// A screen recording in progress (ScreenshotManager): a red dot and the
// time recorded; a click stops it. Hidden entirely while not recording.
BarIconWidget {
  id: root

  hidden: !ScreenshotManager.recording

  icon: "radio_button_checked"
  text: StopwatchClock.format(ScreenshotManager.recordingElapsed * 1000)
  showText: properties.showTimer && ScreenshotManager.recordingSince > 0

  accentColor: Theme.resolveColor(properties.activeColor)
  clickable: true
  onClicked: ActionsManager.run("screenRecord", {
    "call": "close",
    "fromScreen": true
  })
}
