pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Bluetooth on the OSD: the Bluetooth tile and its card. A stub until its
// port (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Bluetooth")
  exposes: [
    {
      "key": "bluetooth",
      "part": "tile",
      "icon": "bluetooth",
      "label": "Bluetooth"
    }
  ]
}
