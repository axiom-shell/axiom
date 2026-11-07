pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Airplane mode's state for the OSD: whether it's on
OSDWatch {
  state: ({
      "airplane": {
        "value": NetworkingManager.airplane
      }
    })
}
