pragma ComponentBehavior: Bound
import QtQuick

import qs.services.apps
import qs.config
import qs.components.bar.widgets.base

// A screen recording in progress (ScreenshotManager): a red dot and the
// time recorded; a click stops it. Hidden entirely while not recording.
BarIconWidget {
  id: root

  hidden: !ScreenshotManager.recording
  readonly property int elapsed: ScreenshotManager.recordingElapsed

  icon: "radio_button_checked"
  text: `${Math.floor(root.elapsed / 60)}:${String(root.elapsed % 60).padStart(2, "0")}`
  showText: properties.showTimer && ScreenshotManager.recordingSince > 0

  accentColor: Theme.resolveColor(properties.activeColor)
  clickable: true
  onClicked: ScreenshotManager.stopRecording()
}
