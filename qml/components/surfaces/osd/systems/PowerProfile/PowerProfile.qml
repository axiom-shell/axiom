pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Power profile on the OSD: the power profile tile. A stub until its port
// (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Power profile")
  exposes: [
    {
      "key": "powerProfile",
      "part": "tile",
      "icon": "speed",
      "label": "Power profile"
    }
  ]
}
