pragma ComponentBehavior: Bound
import QtQuick
import qs.services.apps
import qs.components.surfaces.osd.engine

// Screen recording's state for the OSD: whether a recorder is there and
// whether it records
OSDWatch {
  state: ({
      "recording": {
        "available": ScreenshotManager.hasRecorder,
        "value": ScreenshotManager.recording
      }
    })
}
