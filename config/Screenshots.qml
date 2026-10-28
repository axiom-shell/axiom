pragma Singleton
import QtQuick
import qs.services.core

// Reader for the Screenshots section: where screenshots and recordings are
// saved (ScreenshotManager resolves the empty defaults)
QtObject {
  id: root

  readonly property var _c: ConfigManager.live.Screenshots

  // With ~ expanded; empty for <Pictures>/Screenshots
  readonly property string folder: Paths.expandHome(_c.folder)
  // With ~ expanded; empty for the screenshot folder
  readonly property string recordingFolder: Paths.expandHome(_c.recordingFolder)
}
