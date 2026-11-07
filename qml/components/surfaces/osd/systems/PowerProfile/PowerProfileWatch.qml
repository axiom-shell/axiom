pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Power profile's state for the OSD: a stub until its port, with no state,
// so nothing it watches ever changes
OSDWatch {
  state: ({})
}
