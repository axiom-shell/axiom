pragma ComponentBehavior: Bound
import QtQuick
import qs.services.session
import qs.components.surfaces.osd.engine

// Caffeine's state for the OSD: whether idle is held off
OSDWatch {
  state: ({
      "caffeine": {
        "value": IdleManager.caffeine
      }
    })
}
