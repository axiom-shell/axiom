pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Battery and charger on the OSD: the charger and low-battery tiles and
// their cards. A stub until its port (`stub`: the timelines skip it); only
// what it exposes is declared
OSDSystem {
  readonly property bool stub: true

  // I18n.tr("Charger") I18n.tr("Low battery")
  exposes: [
    {
      "key": "charger",
      "part": "tile",
      "icon": "power",
      "label": "Charger"
    },
    {
      "key": "battery",
      "part": "tile",
      "icon": "battery_alert",
      "label": "Low battery"
    }
  ]
}
