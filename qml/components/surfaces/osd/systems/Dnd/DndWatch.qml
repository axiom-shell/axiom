pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Do not disturb's state for the OSD: whether it's on
OSDWatch {
  state: ({
      "dnd": {
        "value": NotificationManager.dnd
      }
    })
}
