pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Night light on the OSD: one tile, lit and unusual while on; either way
// its icon (NightLightWatch reads NightLightManager)
OSDSystem {
  // I18n.tr("Night light")
  exposes: [
    {
      "key": "nightLight",
      "part": "tile",
      "icon": "nightlight",
      "label": "Night light",
      "action": "nightLight"
    }
  ]
}
