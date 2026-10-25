pragma ComponentBehavior: Bound
import QtQuick
import qs.config
import qs.services.apps
import qs.components.content.parts
import qs.components.reusable
import qs.components.content.base

// Screenshots through ScreenshotManager (region, active window or the
// focused screen), saved to the Screenshots section's folder and copied to
// the clipboard. Recording (ScreenshotManager, with wf-recorder) shows only
// when it's installed.
Card {
  id: root

  readonly property bool recording: ScreenshotManager.recording

  // [mode, icon, label]; the record tile's icon and label follow
  // `recording` in the delegate, so a toggle rebuilds nothing
  readonly property var modes: [["region", "screenshot_region", I18n.tr("Region")], ["window", "wrap_text", I18n.tr("Window")], ["screen", "screenshot_monitor", I18n.tr("Screen")]].filter(mode => ScreenshotManager.kinds.includes(mode[0])).concat(ScreenshotManager.hasRecorder ? [["record", "fiber_manual_record", I18n.tr("Record")]] : [])

  function capture(mode) {
    if (mode === "record")
      ScreenshotManager.toggleRecording();
    else
      ScreenshotManager.take(mode);
  }

  TileGrid {
    id: grid
    anchors.fill: parent
    anchors.margins: root.pad
    count: root.modes.length

    Repeater {
      model: root.modes

      ActionTile {
        required property var modelData
        required property int index
        readonly property bool stops: modelData[0] === "record" && root.recording
        x: grid.tileX(index)
        y: grid.tileY(index)
        width: grid.tileWidth
        height: grid.tileHeight
        icon: stops ? "stop" : modelData[1]
        label: stops ? I18n.tr("Stop") : modelData[2]
        showLabel: !root.compact
        active: stops
        activeColor: Theme.error
        onClicked: root.capture(modelData[0])
      }
    }
  }
}
