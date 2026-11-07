pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// Night light's state for the OSD: whether it's on
OSDWatch {
  state: ({
      "nightLight": {
        "value": NightLightManager.active
      }
    })
}
