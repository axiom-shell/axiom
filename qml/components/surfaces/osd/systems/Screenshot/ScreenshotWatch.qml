pragma ComponentBehavior: Bound
import QtQuick
import qs.services.apps
import qs.components.surfaces.osd.engine

// Screenshots' state for the OSD: each screenshot taken (ScreenshotManager's
// lastShot, set only while an OSD shows its card: OSDConfig.routeOf),
// pulsed so each counts. A click on its card opens the picture
OSDWatch {
  id: root

  state: ({
      "screenshot": {
        "event": root.events.screenshot?.event ?? null,
        "seq": root.events.screenshot?.seq ?? 0
      }
    })

  function activate(change) {
    ScreenshotManager.open(ScreenshotManager.lastShot?.path ?? "");
  }

  Connections {
    target: ScreenshotManager
    function onLastShotChanged() {
      if (ScreenshotManager.lastShot)
        root.pulse("screenshot", ScreenshotManager.lastShot);
    }
  }
}
