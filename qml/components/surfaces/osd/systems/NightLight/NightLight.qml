pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Night light on the OSD: the night light tile. A stub until its port
// (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Night light")
  exposes: [
    {
      "key": "nightLight",
      "part": "tile",
      "icon": "nightlight",
      "label": "Night light"
    }
  ]
}
