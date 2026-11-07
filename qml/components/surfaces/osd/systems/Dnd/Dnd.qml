pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Do not disturb on the OSD: the do-not-disturb tile. A stub until its port
// (`stub`: the timelines skip it); only what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Do not disturb")
  exposes: [
    {
      "key": "dnd",
      "part": "tile",
      "icon": "do_not_disturb_on",
      "label": "Do not disturb"
    }
  ]
}
