pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Night light's state for the OSD: whether it's on, and whether a
// night-light tool is there at all (`available`: its tile hidden without)
OSDWatch {
  state: ({
      "nightLight": {
        "available": NightLightManager.available,
        "value": NightLightManager.active
      }
    })
}
