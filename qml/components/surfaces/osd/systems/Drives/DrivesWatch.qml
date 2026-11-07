pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Removable drives' state for the OSD: whether udisks2 answers, how many
// drives are plugged in, and each thing done to one (DrivesManager's
// lastEvent, set only while an OSD shows its cards: OSDConfig.routeOf),
// pulsed so the same one twice counts. A click on its card acts on it
OSDWatch {
  id: root

  state: ({
      "drive": {
        "available": DrivesManager.available,
        "count": DrivesManager.count,
        "event": root.events.drive?.event ?? null,
        "seq": root.events.drive?.seq ?? 0
      }
    })

  // Opens the drive, asks for its passphrase, or shows the Drives module
  function activate(change) {
    DrivesManager.activate(DrivesManager.lastEvent);
  }

  Connections {
    target: DrivesManager
    function onLastEventChanged() {
      if (DrivesManager.lastEvent)
        root.pulse("drive", DrivesManager.lastEvent);
    }
  }
}
