pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Removable drives on the OSD: the removable drive tile and its cards. A
// stub until its port (`stub`: the timelines skip it); only what it exposes
// is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Removable drives")
  exposes: [
    {
      "key": "drive",
      "part": "tile",
      "icon": "usb",
      "label": "Removable drives"
    }
  ]
}
