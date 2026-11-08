pragma ComponentBehavior: Bound
import QtQuick
import qs.services.compositor
import qs.components.surfaces.osd.engine

// Monitors' state for the OSD: each monitor connected or removed
// (MonitorManager's lastEvent, set only while an OSD shows its card:
// OSDConfig.routeOf), pulsed so the same one twice counts; none where
// the compositor gives no monitors
OSDWatch {
  id: root

  state: ({
      "monitor": {
        "available": CompositorManager.supports.monitors === true,
        "event": root.events.monitor?.event ?? null,
        "seq": root.events.monitor?.seq ?? 0
      }
    })

  Connections {
    target: MonitorManager
    function onLastEventChanged() {
      if (MonitorManager.lastEvent)
        root.pulse("monitor", MonitorManager.lastEvent);
    }
  }
}
