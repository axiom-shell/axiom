pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Monitors on the OSD: the monitor card (card only). A stub until its port
// (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Monitors")
  exposes: [
    {
      "key": "monitor",
      "part": "card",
      "icon": "monitor",
      "label": "Monitors"
    }
  ]
}
