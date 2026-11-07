pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Screenshots on the OSD: the screenshot card (card only). A stub until its
// port (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Screenshots")
  exposes: [
    {
      "key": "screenshot",
      "part": "card",
      "icon": "screenshot_monitor",
      "label": "Screenshots"
    }
  ]
}
