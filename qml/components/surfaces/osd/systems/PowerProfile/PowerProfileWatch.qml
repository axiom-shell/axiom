pragma ComponentBehavior: Bound
import QtQuick
import qs.services.system
import qs.components.surfaces.osd.engine

// The power profile's state for the OSD: the profile in use ("" with no
// profiles daemon)
OSDWatch {
  state: ({
      "powerProfile": {
        "value": BatteryManager.profile
      }
    })
}
