pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Brightness on the OSD: the brightness bar. A stub until its port (`stub`:
// the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Brightness")
  exposes: [
    {
      "key": "brightness",
      "part": "bar",
      "icon": options.icon || "brightness_6",
      "label": "Brightness",
      "opens": options.showOsd !== false
    }
  ]
}
