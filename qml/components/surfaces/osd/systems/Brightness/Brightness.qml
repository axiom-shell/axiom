pragma ComponentBehavior: Bound
import QtQuick
import qs.components.surfaces.osd.engine

// Brightness on the OSD: the brightness bar, this screen's (or with
// `allMonitors` every monitor's mean), left out while there's no
// controller (`available`); quiet, it never opens a shut OSD. Only a
// level set through axiom counts (`countsWithin` its set time,
// BrightnessWatch's `setAt`), not one a refresh found or idle dimming;
// every such set counts, so a key at its limit still shows the bar. A
// plain bar: its drag and scroll set the monitors through the watcher
// (setLevel)
OSDSystem {
  // Within 500 ms of axiom's own set: its reading comes in the same pass
  countsWithin: ({
      "after": "setAt",
      "ms": 500
    })

  // I18n.tr("Brightness")
  exposes: [
    {
      "key": "brightness",
      "part": "bar",
      "icon": options.icon || "brightness_6",
      "label": "Brightness"
    }
  ]
}
