pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Airplane mode on the OSD: the airplane mode tile. A stub until its port
// (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Airplane mode")
  exposes: [
    {
      "key": "airplane",
      "part": "tile",
      "icon": "airplanemode_active",
      "label": "Airplane mode"
    }
  ]
}
