pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Brightness on the OSD: the brightness bar, this screen's (or with
// `allMonitors` every monitor's mean), left out while there's no
// controller (`available`); with `showOsd` off it never opens a shut OSD.
// Only a level set through axiom counts (BrightnessWatch's settled), not
// one a refresh found or idle dimming. A plain bar: its drag and scroll
// set the monitors through the watcher (setLevel)
OSDSystem {
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
