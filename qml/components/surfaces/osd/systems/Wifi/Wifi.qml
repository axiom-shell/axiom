pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Wi-Fi on the OSD: the Wi-Fi tile and its card. A stub until its port
// (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Wi-Fi")
  exposes: [
    {
      "key": "wifi",
      "part": "tile",
      "icon": "wifi",
      "label": "Wi-Fi"
    }
  ]
}
